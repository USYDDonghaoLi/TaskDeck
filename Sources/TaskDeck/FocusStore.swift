import Foundation

@MainActor
final class FocusStore: ObservableObject {
    @Published private(set) var sessions: [FocusSession] = []
    @Published private(set) var active: ActiveFocus?
    @Published private(set) var persistenceError: String?

    let databaseURL: URL
    private let calendar: Calendar
    private var database: TaskDatabase?
    private var sharedChangeObserver: NSObjectProtocol?

    init(
        databaseURL: URL? = nil,
        legacyDirectory: URL? = nil,
        calendar: Calendar = .current
    ) {
        self.databaseURL = databaseURL ?? TaskDeckShared.databaseURL()
        self.calendar = calendar
        do {
            let database = try TaskDatabase(url: self.databaseURL)
            if databaseURL == nil || legacyDirectory != nil {
                try TaskDeckShared.migrateLegacyFocusIfNeeded(
                    into: database,
                    legacyDirectory: legacyDirectory
                )
            }
            self.database = database
            try load(from: database)
        } catch {
            persistenceError = error.localizedDescription
            NSLog("TaskDeck could not initialize focus database: %@", error.localizedDescription)
        }
        sharedChangeObserver = DistributedNotificationCenter.default().addObserver(
            forName: TaskDeckShared.changeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshFromDatabase() }
        }
    }

    @discardableResult
    func beginOrToggle(_ task: TaskItem, now: Date = Date()) -> Bool {
        if let current = active {
            guard current.taskID == task.id else { return false }
            var updated = current
            if let runningSince = updated.runningSince {
                updated.accumulatedSeconds += max(0, now.timeIntervalSince(runningSince))
                updated.runningSince = nil
            } else {
                updated.runningSince = now
            }
            return persistActive(updated, matching: current, reason: "focus-toggle")
        }

        let started = ActiveFocus(
            taskID: task.id,
            taskTitle: task.title,
            direction: task.normalizedDirection,
            initiatedAt: now,
            estimatedMinutes: task.estimatedMinutes,
            runningSince: now,
            accumulatedSeconds: 0
        )
        return persistActive(started, matching: nil, reason: "focus-start")
    }

    func pause(now: Date = Date()) {
        guard let current = active, let runningSince = current.runningSince else { return }
        var updated = current
        updated.accumulatedSeconds += max(0, now.timeIntervalSince(runningSince))
        updated.runningSince = nil
        _ = persistActive(updated, matching: current, reason: "focus-pause")
    }

    func resume(now: Date = Date()) {
        guard let current = active, current.runningSince == nil else { return }
        var updated = current
        updated.runningSince = now
        _ = persistActive(updated, matching: current, reason: "focus-resume")
    }

    @discardableResult
    func finish(now: Date = Date()) -> FocusSession? {
        guard let active else { return nil }
        let seconds = Int(elapsed(for: active, at: now).rounded())
        let session = FocusSession(
            taskID: active.taskID,
            taskTitle: active.taskTitle,
            direction: active.direction,
            startedAt: active.initiatedAt,
            endedAt: now,
            durationSeconds: seconds
        )
        guard let database else { return nil }
        do {
            let changed = try database.finishFocus(session, matching: active)
            try load(from: database)
            persistenceError = nil
            if changed {
                TaskDeckShared.notifyDataChanged()
                return session
            }
            return nil
        } catch {
            persistenceError = error.localizedDescription
            NSLog("TaskDeck could not finish focus data: %@", error.localizedDescription)
            return nil
        }
    }

    func discardActive() {
        guard let active, let database else { return }
        do {
            let changed = try database.discardActiveFocus(matching: active)
            try load(from: database)
            persistenceError = nil
            if changed { TaskDeckShared.notifyDataChanged() }
        } catch {
            persistenceError = error.localizedDescription
            NSLog("TaskDeck could not discard focus data: %@", error.localizedDescription)
        }
    }

    func elapsed(at date: Date = Date()) -> TimeInterval {
        guard let active else { return 0 }
        return elapsed(for: active, at: date)
    }

    func sessions(in interval: DateInterval) -> [FocusSession] {
        sessions.filter { interval.contains($0.endedAt) }.sorted { $0.endedAt > $1.endedAt }
    }

    func totalSeconds(in interval: DateInterval) -> Int {
        sessions(in: interval).reduce(0) { $0 + $1.durationSeconds }
    }

    func seconds(for taskID: UUID, in interval: DateInterval? = nil) -> Int {
        sessions.reduce(0) { result, session in
            guard session.taskID == taskID else { return result }
            if let interval, !interval.contains(session.endedAt) { return result }
            return result + session.durationSeconds
        }
    }

    func seconds(on date: Date) -> Int {
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        return totalSeconds(in: DateInterval(start: start, end: end))
    }

    func refreshFromDatabase() {
        guard let database else { return }
        do {
            try load(from: database)
            persistenceError = nil
        } catch {
            persistenceError = error.localizedDescription
            NSLog("TaskDeck could not refresh focus database: %@", error.localizedDescription)
        }
    }

    private func elapsed(for active: ActiveFocus, at date: Date) -> TimeInterval {
        let runningSeconds = active.runningSince.map { max(0, date.timeIntervalSince($0)) } ?? 0
        return active.accumulatedSeconds + runningSeconds
    }

    private func load(from database: TaskDatabase) throws {
        sessions = try database.loadFocusSessions().sorted { $0.endedAt > $1.endedAt }
        active = try database.loadActiveFocus()
    }

    private func persistActive(
        _ updated: ActiveFocus,
        matching expected: ActiveFocus?,
        reason: String
    ) -> Bool {
        guard let database else { return false }
        do {
            let changed = try database.saveActiveFocus(updated, matching: expected, reason: reason)
            try load(from: database)
            persistenceError = nil
            if changed { TaskDeckShared.notifyDataChanged() }
            return changed
        } catch {
            persistenceError = error.localizedDescription
            NSLog("TaskDeck could not save focus data: %@", error.localizedDescription)
            return false
        }
    }
}
