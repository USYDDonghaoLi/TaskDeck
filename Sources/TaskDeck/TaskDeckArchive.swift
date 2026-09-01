import Foundation

struct TaskDeckArchive: Codable {
    let schemaVersion: Int
    let exportedAt: Date
    let tasks: [TaskItem]
    let focusSessions: [FocusSession]
    let activeFocus: ActiveFocus?

    init(
        schemaVersion: Int = 4,
        exportedAt: Date = Date(),
        tasks: [TaskItem],
        focusSessions: [FocusSession],
        activeFocus: ActiveFocus?
    ) {
        self.schemaVersion = schemaVersion
        self.exportedAt = exportedAt
        self.tasks = tasks
        self.focusSessions = focusSessions
        self.activeFocus = activeFocus
    }
}

enum TaskDeckImport {
    case archive(TaskDeckArchive)
    case legacyTasks([TaskItem])
}

enum TaskDeckArchiveCodec {
    static func encode(_ archive: TaskDeckArchive) throws -> Data {
        try encoder.encode(archive)
    }

    static func decode(_ data: Data) throws -> TaskDeckImport {
        guard data.count <= 50 * 1_024 * 1_024 else {
            throw TaskDatabaseError(operation: "Import JSON", message: "File exceeds the 50 MB safety limit")
        }

        if let archive = try? decoder.decode(TaskDeckArchive.self, from: data) {
            try validate(tasks: archive.tasks, sessions: archive.focusSessions)
            return .archive(archive)
        }

        let tasks = try decoder.decode([TaskItem].self, from: data)
        try validate(tasks: tasks, sessions: [])
        return .legacyTasks(tasks)
    }

    static func decodeLegacyTasks(_ data: Data) throws -> [TaskItem] {
        let tasks = try decoder.decode([TaskItem].self, from: data)
        try validate(tasks: tasks, sessions: [])
        return tasks
    }

    static func decodeLegacySessions(_ data: Data) throws -> [FocusSession] {
        let sessions = try decoder.decode([FocusSession].self, from: data)
        try validate(tasks: [], sessions: sessions)
        return sessions
    }

    static func decodeLegacyRuntime(_ data: Data) throws -> ActiveFocus? {
        try decoder.decode(FocusRuntimeState.self, from: data).active
    }

    private static func validate(tasks: [TaskItem], sessions: [FocusSession]) throws {
        guard Set(tasks.map(\.id)).count == tasks.count else {
            throw TaskDatabaseError(operation: "Import JSON", message: "Duplicate task IDs")
        }
        guard tasks.allSatisfy({ !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            throw TaskDatabaseError(operation: "Import JSON", message: "Every task must have a name")
        }
        guard Set(sessions.map(\.id)).count == sessions.count else {
            throw TaskDatabaseError(operation: "Import JSON", message: "Duplicate focus session IDs")
        }
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
