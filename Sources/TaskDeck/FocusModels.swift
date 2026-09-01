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
}

struct ActiveFocus: Codable, Equatable, Sendable {
    let taskID: UUID
    let taskTitle: String
    let direction: String
    let initiatedAt: Date
    let estimatedMinutes: Int
    var runningSince: Date?
    var accumulatedSeconds: TimeInterval

    var isPaused: Bool { runningSince == nil }
}

struct FocusRuntimeState: Codable {
    var active: ActiveFocus?
}
