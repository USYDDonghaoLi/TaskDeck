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
            if current.taskID != task.id {
                guard current.isPaused else { return false }
                return switchFocus(from: current, to: task, now: now)
            }
            var updated = current
            if let runningSince = updated.runningSince {
                let segmentSeconds = max(0, now.timeIntervalSince(runningSince))
                updated.accumulatedSeconds += segmentSeconds
                updated.runningSince = nil
                let session = makeSession(
                    for: current,
                    startedAt: runningSince,
                    endedAt: now,
                    seconds: segmentSeconds
                )
                return persistPause(session, updated: updated, matching: current)
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
        let segmentSeconds = max(0, now.timeIntervalSince(runningSince))
        updated.accumulatedSeconds += segmentSeconds
        updated.runningSince = nil
        let session = makeSession(
            for: current,
            startedAt: runningSince,
            endedAt: now,
            seconds: segmentSeconds
        )
        _ = persistPause(session, updated: updated, matching: current)
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
        let finalSessions = sessionsNeededToFinish(active, now: now)
        guard let database else { return nil }
        do {
            let changed = try database.finishFocus(finalSessions, matching: active)
            try load(from: database)
            persistenceError = nil
            if changed {
                TaskDeckShared.notifyDataChanged()
                return finalSessions.last
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
        sessions.compactMap { $0.clipped(to: interval) }.sorted { $0.endedAt > $1.endedAt }
    }

    func totalSeconds(in interval: DateInterval) -> Int {
        sessions(in: interval).reduce(0) { $0 + $1.durationSeconds }
    }

    func seconds(for taskID: UUID, in interval: DateInterval? = nil) -> Int {
        sessions.reduce(0) { result, session in
            guard session.taskID == taskID else { return result }
            return result + (interval.map(session.seconds(in:)) ?? session.durationSeconds)
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

    func updateActiveTaskDetails(from task: TaskItem) {
        guard let current = active, current.taskID == task.id else { return }
        var updated = current
        updated.taskTitle = task.title
        updated.direction = task.normalizedDirection
        updated.estimatedMinutes = task.estimatedMinutes
        _ = persistActive(updated, matching: current, reason: "focus-task-edit")
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

    private func persistPause(
        _ session: FocusSession?,
        updated: ActiveFocus,
        matching expected: ActiveFocus
    ) -> Bool {
        guard let database else { return false }
        do {
            let changed = try database.pauseFocus(session, active: updated, matching: expected)
            try load(from: database)
            persistenceError = nil
            if changed { TaskDeckShared.notifyDataChanged() }
            return changed
        } catch {
            persistenceError = error.localizedDescription
            NSLog("TaskDeck could not pause focus data: %@", error.localizedDescription)
            return false
        }
    }

    private func switchFocus(from current: ActiveFocus, to task: TaskItem, now: Date) -> Bool {
        guard let database else { return false }
        let newActive = ActiveFocus(
            taskID: task.id,
            taskTitle: task.title,
            direction: task.normalizedDirection,
            initiatedAt: now,
            estimatedMinutes: task.estimatedMinutes,
            runningSince: now,
            accumulatedSeconds: 0
        )
        do {
            let changed = try database.switchFocus(
                from: current,
                finalSessions: sessionsNeededToFinish(current, now: now),
                to: newActive
            )
            try load(from: database)
            persistenceError = nil
            if changed { TaskDeckShared.notifyDataChanged() }
            return changed
        } catch {
            persistenceError = error.localizedDescription
            NSLog("TaskDeck could not switch focus task: %@", error.localizedDescription)
            return false
        }
    }

    private func sessionsNeededToFinish(_ active: ActiveFocus, now: Date) -> [FocusSession] {
        var result: [FocusSession] = []
        let alreadyRecorded = sessions.reduce(0) { total, session in
            guard session.taskID == active.taskID, session.startedAt >= active.initiatedAt else { return total }
            return total + session.durationSeconds
        }
        let unrecorded = max(0, active.accumulatedSeconds - Double(alreadyRecorded))
        if let legacy = makeSession(
            for: active,
            startedAt: active.initiatedAt,
            endedAt: active.runningSince ?? now,
            seconds: unrecorded
        ) {
            result.append(legacy)
        }
        if let runningSince = active.runningSince,
           let running = makeSession(
               for: active,
               startedAt: runningSince,
               endedAt: now,
               seconds: max(0, now.timeIntervalSince(runningSince))
           ) {
            result.append(running)
        }
        return result
    }

    private func makeSession(
        for active: ActiveFocus,
        startedAt: Date,
        endedAt: Date,
        seconds: TimeInterval
    ) -> FocusSession? {
        guard endedAt > startedAt, seconds >= 0.5 else { return nil }
        return FocusSession(
            taskID: active.taskID,
            taskTitle: active.taskTitle,
            direction: active.direction,
            startedAt: startedAt,
            endedAt: endedAt,
            durationSeconds: Int(seconds.rounded())
        )
    }
}
