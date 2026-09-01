import Foundation

enum TaskPriority: String, Codable, CaseIterable, Identifiable, Sendable {
    case normal
    case important
    case urgent

    var id: String { rawValue }

    var title: String {
        switch self {
        case .normal: return "普通"
        case .important: return "重要"
        case .urgent: return "紧急"
        }
    }

    var symbol: String {
        switch self {
        case .normal: return "minus"
        case .important: return "exclamationmark"
        case .urgent: return "bolt.fill"
        }
    }

    var sortOrder: Int {
        switch self {
        case .normal: return 0
        case .important: return 1
        case .urgent: return 2
        }
    }
}

enum TaskRecurrence: String, Codable, CaseIterable, Identifiable, Sendable {
    case none
    case daily
    case weekdays
    case weekly
    case monthly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "不重复"
        case .daily: return "每天"
        case .weekdays: return "工作日"
        case .weekly: return "每周"
        case .monthly: return "每月"
        }
    }

    var symbol: String { self == .none ? "arrow.right" : "repeat" }
}

struct TaskItem: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var direction: String
    var title: String
    var notes: String
    var estimatedMinutes: Int
    var priority: TaskPriority
    var dueAt: Date?
    var reminderEnabled: Bool
    var recurrence: TaskRecurrence
    let createdAt: Date
    var completedAt: Date?
    var generatedNextTaskID: UUID?

    init(
        id: UUID = UUID(),
        direction: String,
        title: String,
        notes: String = "",
        estimatedMinutes: Int,
        priority: TaskPriority = .normal,
        dueAt: Date? = nil,
        reminderEnabled: Bool = false,
        recurrence: TaskRecurrence = .none,
        createdAt: Date = Date(),
        completedAt: Date? = nil,
        generatedNextTaskID: UUID? = nil
    ) {
        self.id = id
        self.direction = direction.trimmingCharacters(in: .whitespacesAndNewlines)
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        self.estimatedMinutes = max(5, estimatedMinutes)
        self.priority = priority
        self.dueAt = dueAt
        self.reminderEnabled = reminderEnabled && dueAt != nil
        self.recurrence = dueAt == nil ? .none : recurrence
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.generatedNextTaskID = generatedNextTaskID
    }

    var isCompleted: Bool { completedAt != nil }

    var normalizedDirection: String {
        direction.isEmpty ? "未分类" : direction
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case direction
        case title
        case notes
        case estimatedMinutes
        case priority
        case dueAt
        case reminderEnabled
        case recurrence
        case createdAt
        case completedAt
        case generatedNextTaskID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        direction = try container.decodeIfPresent(String.self, forKey: .direction)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        title = try container.decodeIfPresent(String.self, forKey: .title)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        notes = try container.decodeIfPresent(String.self, forKey: .notes)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        estimatedMinutes = max(5, try container.decodeIfPresent(Int.self, forKey: .estimatedMinutes) ?? 25)
        priority = try container.decodeIfPresent(TaskPriority.self, forKey: .priority) ?? .normal
        dueAt = try container.decodeIfPresent(Date.self, forKey: .dueAt)
        reminderEnabled = (try container.decodeIfPresent(Bool.self, forKey: .reminderEnabled) ?? false) && dueAt != nil
        recurrence = dueAt == nil
            ? .none
            : try container.decodeIfPresent(TaskRecurrence.self, forKey: .recurrence) ?? .none
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)
        generatedNextTaskID = try container.decodeIfPresent(UUID.self, forKey: .generatedNextTaskID)
    }
}

enum TaskFilter: String, CaseIterable, Identifiable {
    case today = "今日任务"
    case inbox = "全部任务"
    case completed = "已完成"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .today: return "scope"
        case .inbox: return "tray.full"
        case .completed: return "checkmark.seal"
        }
    }
}

enum ReportPeriod: String, CaseIterable, Identifiable {
    case day = "日"
    case week = "周"
    case month = "月"

    var id: String { rawValue }
}

struct ReportSnapshot: Equatable {
    let interval: DateInterval
    let completed: [TaskItem]
    let createdCount: Int
    let directionCount: Int

    var completedCount: Int { completed.count }
    var estimatedMinutes: Int { completed.reduce(0) { $0 + $1.estimatedMinutes } }
}
