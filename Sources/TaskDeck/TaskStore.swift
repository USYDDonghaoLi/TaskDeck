import Foundation

@MainActor
final class TaskStore: ObservableObject {
    @Published private(set) var tasks: [TaskItem] = []
    @Published private(set) var persistenceError: String?

    private let fileURL: URL
    private let calendar: Calendar
    private var loadFailed = false

    init(fileURL: URL? = nil, calendar: Calendar = .current) {
        self.calendar = calendar
        self.fileURL = fileURL ?? Self.defaultFileURL()
        load()
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
        tasks.append(task)
        save()
        return task
    }

    @discardableResult
    func update(_ task: TaskItem) -> TaskItem? {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return nil }
        var normalized = task
        normalized.direction = task.direction.trimmingCharacters(in: .whitespacesAndNewlines)
        normalized.title = task.title.trimmingCharacters(in: .whitespacesAndNewlines)
        normalized.notes = task.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        normalized.estimatedMinutes = max(5, task.estimatedMinutes)
        normalized.reminderEnabled = task.reminderEnabled && task.dueAt != nil
        normalized.recurrence = task.dueAt == nil ? .none : task.recurrence
        tasks[index] = normalized
        save()
        return normalized
    }

    @discardableResult
    func toggle(_ task: TaskItem) -> TaskItem? {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return nil }
        var generatedTask: TaskItem?

        if tasks[index].completedAt == nil {
            tasks[index].completedAt = Date()
            let completedTask = tasks[index]
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
                tasks[index].generatedNextTaskID = nextTask.id
                tasks.append(nextTask)
                generatedTask = nextTask
            }
        } else {
            tasks[index].completedAt = nil
        }

        save()
        return generatedTask
    }

    @discardableResult
    func reschedule(_ task: TaskItem, to date: Date) -> TaskItem? {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return nil }
        tasks[index].dueAt = date
        save()
        return tasks[index]
    }

    func delete(_ task: TaskItem) {
        tasks.removeAll { $0.id == task.id }
        save()
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

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            if Self.needsV11Migration(data) {
                createBackup(data, named: "tasks-before-v1.1.json", overwrite: false)
            }
            tasks = try JSONDecoder.taskDeck.decode([TaskItem].self, from: data)
            persistenceError = nil
        } catch {
            loadFailed = true
            persistenceError = "任务数据读取失败，原文件已保留，TaskDeck 不会覆盖它。"
            NSLog("TaskDeck could not load tasks: %@", error.localizedDescription)
        }
    }

    private func save() {
        guard !loadFailed else { return }
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if let previousData = try? Data(contentsOf: fileURL) {
                createBackup(previousData, named: "tasks-last-known-good.json", overwrite: true)
            }
            let data = try JSONEncoder.taskDeck.encode(tasks)
            try data.write(to: fileURL, options: .atomic)
            persistenceError = nil
        } catch {
            persistenceError = "任务保存失败，请保留应用并检查磁盘权限。"
            NSLog("TaskDeck could not save tasks: %@", error.localizedDescription)
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

    private static func defaultFileURL() -> URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return root.appendingPathComponent("TaskDeck", isDirectory: true).appendingPathComponent("tasks.json")
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

    private func createBackup(_ data: Data, named name: String, overwrite: Bool) {
        do {
            let backupDirectory = fileURL.deletingLastPathComponent().appendingPathComponent("Backups", isDirectory: true)
            try FileManager.default.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
            let backupURL = backupDirectory.appendingPathComponent(name)
            guard overwrite || !FileManager.default.fileExists(atPath: backupURL.path) else { return }
            try data.write(to: backupURL, options: .atomic)
        } catch {
            NSLog("TaskDeck could not create backup: %@", error.localizedDescription)
        }
    }

    private static func needsV11Migration(_ data: Data) -> Bool {
        guard
            let value = try? JSONSerialization.jsonObject(with: data),
            let objects = value as? [[String: Any]],
            !objects.isEmpty
        else { return false }

        return objects.contains { object in
            object["priority"] == nil || object["recurrence"] == nil || object["notes"] == nil
        }
    }
}

private extension JSONEncoder {
    static var taskDeck: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var taskDeck: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
