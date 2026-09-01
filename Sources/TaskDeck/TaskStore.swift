import Foundation
import WidgetKit

@MainActor
final class TaskStore: ObservableObject {
    @Published private(set) var tasks: [TaskItem] = []
    @Published private(set) var persistenceError: String?

    let databaseURL: URL
    private let calendar: Calendar
    private var database: TaskDatabase?
    private var loadFailed = false
    private var sharedChangeObserver: NSObjectProtocol?

    init(
        databaseURL: URL? = nil,
        legacyTaskURL: URL? = nil,
        calendar: Calendar = .current
    ) {
        self.calendar = calendar
        self.databaseURL = databaseURL ?? TaskDeckShared.databaseURL()
        do {
            let database = try TaskDeckShared.taskDatabase(
                at: databaseURL,
                legacyTaskURL: legacyTaskURL
            )
            self.database = database
            tasks = try database.loadTasks()
        } catch {
            loadFailed = true
            persistenceError = "任务数据库读取失败，旧 JSON 与数据库文件均已保留。"
            NSLog("TaskDeck could not initialize task database: %@", error.localizedDescription)
        }
        sharedChangeObserver = DistributedNotificationCenter.default().addObserver(
            forName: TaskDeckShared.changeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshFromDisk() }
        }
    }

    var directions: [String] {
        Array(Set(tasks.map(\.normalizedDirection))).sorted { $0.localizedCompare($1) == .orderedAscending }
    }

    var pendingTasks: [TaskItem] {
        tasks.filter { !$0.isCompleted }.sorted(by: Self.taskSort)
    }

    var todayPending: [TaskItem] {
        pendingTasks.filter { task in
            guard let dueAt = task.dueAt else { return true }
            return calendar.isDateInToday(dueAt) || dueAt < calendar.startOfDay(for: Date())
        }
    }

    var todayCompleted: [TaskItem] {
        tasks.filter { task in
            guard let completedAt = task.completedAt else { return false }
            return calendar.isDateInToday(completedAt)
        }.sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
    }

    var todayTotalCount: Int { todayPending.count + todayCompleted.count }

    var todayProgress: Double {
        guard todayTotalCount > 0 else { return 0 }
        return Double(todayCompleted.count) / Double(todayTotalCount)
    }

    func tasks(for filter: TaskFilter, direction: String? = nil) -> [TaskItem] {
        let base: [TaskItem]
        switch filter {
        case .today:
            base = tasks.filter { task in
                if let completedAt = task.completedAt {
                    return calendar.isDateInToday(completedAt)
                }
                guard let dueAt = task.dueAt else { return true }
                return calendar.isDateInToday(dueAt) || dueAt < calendar.startOfDay(for: Date())
            }
        case .inbox:
            base = tasks.filter { !$0.isCompleted }
        case .completed:
            base = tasks.filter(\.isCompleted)
        }

        return base
            .filter { direction == nil || $0.normalizedDirection == direction }
            .sorted(by: Self.taskSort)
    }

    func add(
        direction: String,
        title: String,
        notes: String = "",
        estimatedMinutes: Int,
        priority: TaskPriority = .normal,
        dueAt: Date?,
        reminderEnabled: Bool,
        recurrence: TaskRecurrence = .none
    ) -> TaskItem {
        let task = TaskItem(
            direction: direction,
            title: title,
            notes: notes,
            estimatedMinutes: estimatedMinutes,
            priority: priority,
            dueAt: dueAt,
            reminderEnabled: reminderEnabled,
            recurrence: recurrence
        )
        _ = mutateTasks(reason: "task-add") { persistedTasks in
            persistedTasks.append(task)
            return true
        }
        return task
    }

    @discardableResult
    func update(_ task: TaskItem) -> TaskItem? {
        var normalized = task
        normalized.direction = task.direction.trimmingCharacters(in: .whitespacesAndNewlines)
        normalized.title = task.title.trimmingCharacters(in: .whitespacesAndNewlines)
        normalized.notes = task.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        normalized.estimatedMinutes = max(5, task.estimatedMinutes)
        normalized.reminderEnabled = task.reminderEnabled && task.dueAt != nil
        normalized.recurrence = task.dueAt == nil ? .none : task.recurrence
        let changed = mutateTasks(reason: "task-edit") { persistedTasks in
            guard let index = persistedTasks.firstIndex(where: { $0.id == normalized.id }) else {
                return false
            }
            persistedTasks[index] = normalized
            return true
        }
        return changed ? normalized : nil
    }

    @discardableResult
    func toggle(_ task: TaskItem) -> TaskItem? {
        var generatedTask: TaskItem?
        _ = mutateTasks(reason: "task-toggle") { persistedTasks in
            guard let index = persistedTasks.firstIndex(where: { $0.id == task.id }) else {
                return false
            }

            if persistedTasks[index].completedAt == nil {
                persistedTasks[index].completedAt = Date()
                let completedTask = persistedTasks[index]
                if completedTask.recurrence != .none,
                   completedTask.generatedNextTaskID == nil,
                   let nextDueAt = nextOccurrence(after: completedTask.dueAt, recurrence: completedTask.recurrence) {
                    let nextTask = TaskItem(
                        direction: completedTask.direction,
                        title: completedTask.title,
                        notes: completedTask.notes,
                        estimatedMinutes: completedTask.estimatedMinutes,
                        priority: completedTask.priority,
                        dueAt: nextDueAt,
                        reminderEnabled: completedTask.reminderEnabled,
                        recurrence: completedTask.recurrence
                    )
                    persistedTasks[index].generatedNextTaskID = nextTask.id
                    persistedTasks.append(nextTask)
                    generatedTask = nextTask
                }
            } else {
                persistedTasks[index].completedAt = nil
            }
            return true
        }
        return generatedTask
    }

    @discardableResult
    func reschedule(_ task: TaskItem, to date: Date) -> TaskItem? {
        var updatedTask: TaskItem?
        _ = mutateTasks(reason: "task-reschedule") { persistedTasks in
            guard let index = persistedTasks.firstIndex(where: { $0.id == task.id }) else {
                return false
            }
            persistedTasks[index].dueAt = date
            updatedTask = persistedTasks[index]
            return true
        }
        return updatedTask
    }

    func delete(_ task: TaskItem) {
        _ = mutateTasks(reason: "task-delete") { persistedTasks in
            guard persistedTasks.contains(where: { $0.id == task.id }) else { return false }
            persistedTasks.removeAll { $0.id == task.id }
            return true
        }
    }

    func report(for period: ReportPeriod, reference: Date = Date()) -> ReportSnapshot {
        let interval = Self.interval(for: period, reference: reference, calendar: calendar)
        let completed = tasks
            .filter { task in
                guard let date = task.completedAt else { return false }
                return interval.contains(date)
            }
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
        let created = tasks.filter { interval.contains($0.createdAt) }
        let directionCount = Set(completed.map(\.normalizedDirection)).count
        return ReportSnapshot(
            interval: interval,
            completed: completed,
            createdCount: created.count,
            directionCount: directionCount
        )
    }

    func count(for direction: String) -> Int {
        pendingTasks.filter { $0.normalizedDirection == direction }.count
    }

    func completionCount(on date: Date) -> Int {
        tasks.reduce(0) { count, task in
            guard let completedAt = task.completedAt, calendar.isDate(completedAt, inSameDayAs: date) else { return count }
            return count + 1
        }
    }

    func completionStreak(reference: Date = Date()) -> Int {
        let completedDays = Set(tasks.compactMap { task in
            task.completedAt.map { calendar.startOfDay(for: $0) }
        })
        guard !completedDays.isEmpty else { return 0 }

        var cursor = calendar.startOfDay(for: reference)
        if !completedDays.contains(cursor) {
            cursor = calendar.date(byAdding: .day, value: -1, to: cursor) ?? cursor
        }

        var streak = 0
        while completedDays.contains(cursor) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return streak
    }

    func refreshFromDisk() {
        guard let database else { return }
        do {
            tasks = try database.loadTasks()
            loadFailed = false
            persistenceError = nil
        } catch {
            persistenceError = "任务数据库刷新失败，当前界面继续保留已有数据。"
            NSLog("TaskDeck could not reload shared database: %@", error.localizedDescription)
        }
    }

    func exportArchive(focusStore: FocusStore) throws -> Data {
        try TaskDeckArchiveCodec.encode(TaskDeckArchive(
            tasks: tasks,
            focusSessions: focusStore.sessions,
            activeFocus: focusStore.active
        ))
    }

    func importArchive(_ data: Data, focusStore: FocusStore) throws {
        guard let database else {
            throw TaskDatabaseError(operation: "Import JSON", message: "Database is unavailable")
        }
        switch try TaskDeckArchiveCodec.decode(data) {
        case let .archive(archive):
            try database.replaceAll(
                tasks: archive.tasks,
                sessions: archive.focusSessions,
                active: archive.activeFocus
            )
        case let .legacyTasks(importedTasks):
            try database.replaceTasks(importedTasks, reason: "legacy-json-import")
        }
        refreshFromDisk()
        focusStore.refreshFromDatabase()
        WidgetCenter.shared.reloadTimelines(ofKind: TaskDeckShared.widgetKind)
    }

    @discardableResult
    private func mutateTasks(
        reason: String,
        _ mutation: (inout [TaskItem]) -> Bool
    ) -> Bool {
        guard !loadFailed, let database else { return false }
        do {
            var latestTasks = tasks
            let changed = try database.mutateTasks(reason: reason) { persistedTasks in
                let changed = mutation(&persistedTasks)
                latestTasks = persistedTasks
                return changed
            }
            tasks = latestTasks
            persistenceError = nil
            if changed {
                WidgetCenter.shared.reloadTimelines(ofKind: TaskDeckShared.widgetKind)
            }
            return changed
        } catch {
            persistenceError = "任务数据库保存失败，修改前备份仍然保留。"
            NSLog("TaskDeck could not save task database: %@", error.localizedDescription)
            return false
        }
    }

    private static func taskSort(_ lhs: TaskItem, _ rhs: TaskItem) -> Bool {
        if lhs.isCompleted != rhs.isCompleted { return !lhs.isCompleted }
        if lhs.priority != rhs.priority { return lhs.priority.sortOrder > rhs.priority.sortOrder }
        switch (lhs.dueAt, rhs.dueAt) {
        case let (left?, right?) where left != right: return left < right
        case (_?, nil): return true
        case (nil, _?): return false
        default: return lhs.createdAt > rhs.createdAt
        }
    }

    private static func interval(for period: ReportPeriod, reference: Date, calendar: Calendar) -> DateInterval {
        switch period {
        case .day:
            let start = calendar.startOfDay(for: reference)
            return DateInterval(start: start, end: calendar.date(byAdding: .day, value: 1, to: start) ?? reference)
        case .week:
            return calendar.dateInterval(of: .weekOfYear, for: reference)
                ?? DateInterval(start: reference, duration: 7 * 86_400)
        case .month:
            return calendar.dateInterval(of: .month, for: reference)
                ?? DateInterval(start: reference, duration: 30 * 86_400)
        }
    }

    private func nextOccurrence(after date: Date?, recurrence: TaskRecurrence) -> Date? {
        guard let date else { return nil }
        switch recurrence {
        case .none:
            return nil
        case .daily:
            return calendar.date(byAdding: .day, value: 1, to: date)
        case .weekdays:
            var candidate = calendar.date(byAdding: .day, value: 1, to: date)
            while let value = candidate {
                let weekday = calendar.component(.weekday, from: value)
                if weekday != 1 && weekday != 7 { return value }
                candidate = calendar.date(byAdding: .day, value: 1, to: value)
            }
            return nil
        case .weekly:
            return calendar.date(byAdding: .weekOfYear, value: 1, to: date)
        case .monthly:
            return calendar.date(byAdding: .month, value: 1, to: date)
        }
    }

}
