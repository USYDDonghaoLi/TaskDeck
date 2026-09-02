import Foundation

struct FocusSession: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let taskID: UUID
    let taskTitle: String
    let direction: String
    let startedAt: Date
    let endedAt: Date
    let durationSeconds: Int

    init(
        id: UUID = UUID(),
        taskID: UUID,
        taskTitle: String,
        direction: String,
        startedAt: Date,
        endedAt: Date,
        durationSeconds: Int
    ) {
        self.id = id
        self.taskID = taskID
        self.taskTitle = taskTitle
        self.direction = direction
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.durationSeconds = max(1, durationSeconds)
    }

    /// Returns only the recorded focus time that belongs to `interval`.
    /// Cumulative rounding keeps adjacent day slices additive, so splitting a
    /// cross-midnight session never invents or loses recorded seconds overall.
    func clipped(to interval: DateInterval) -> FocusSession? {
        guard endedAt > interval.start, startedAt < interval.end else { return nil }

        let clippedStart = max(startedAt, interval.start)
        let clippedEnd = min(endedAt, interval.end)
        guard clippedEnd > clippedStart else { return nil }

        let wallSeconds = endedAt.timeIntervalSince(startedAt)
        let allocatedSeconds: Int
        if wallSeconds > 0 {
            let startOffset = max(0, clippedStart.timeIntervalSince(startedAt))
            let endOffset = min(wallSeconds, clippedEnd.timeIntervalSince(startedAt))
            let startUnits = Int((Double(durationSeconds) * startOffset / wallSeconds).rounded(.down))
            let endUnits = Int((Double(durationSeconds) * endOffset / wallSeconds).rounded(.down))
            allocatedSeconds = endUnits - startUnits
        } else {
            allocatedSeconds = interval.contains(endedAt) ? durationSeconds : 0
        }
        guard allocatedSeconds > 0 else { return nil }

        return FocusSession(
            id: id,
            taskID: taskID,
            taskTitle: taskTitle,
            direction: direction,
            startedAt: clippedStart,
            endedAt: clippedEnd,
            durationSeconds: allocatedSeconds
        )
    }

    func seconds(in interval: DateInterval) -> Int {
        clipped(to: interval)?.durationSeconds ?? 0
    }
}

struct ActiveFocus: Codable, Equatable, Sendable {
    let taskID: UUID
    var taskTitle: String
    var direction: String
    let initiatedAt: Date
    var estimatedMinutes: Int
    var runningSince: Date?
    var accumulatedSeconds: TimeInterval

    var isPaused: Bool { runningSince == nil }
}

struct FocusRuntimeState: Codable {
    var active: ActiveFocus?
}
