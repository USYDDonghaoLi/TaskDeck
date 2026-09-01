import Foundation

struct Subtask: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var title: String
    var position: Int
    let createdAt: Date
    var completedAt: Date?

    init(
        id: UUID = UUID(),
        title: String,
        position: Int = 0,
        createdAt: Date = Date(),
        completedAt: Date? = nil
    ) {
        self.id = id
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.position = max(0, position)
        self.createdAt = createdAt
        self.completedAt = completedAt
    }

    var isCompleted: Bool { completedAt != nil }
}

enum TaskPriority: String, Codable, CaseIterable, Identifiable, Sendable {
    case normal
    case important
    case urgent

    var id: String { rawValue }

    var title: String {
        title(in: .simplifiedChinese)
    }

    func title(in language: AppLanguage) -> String {
        switch self {
        case .normal: return language == .simplifiedChinese ? "普通" : "Normal"
        case .important: return language == .simplifiedChinese ? "重要" : "Important"
        case .urgent: return language == .simplifiedChinese ? "紧急" : "Urgent"
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
        title(in: .simplifiedChinese)
    }

    func title(in language: AppLanguage) -> String {
        switch self {
        case .none: return language == .simplifiedChinese ? "不重复" : "Never"
        case .daily: return language == .simplifiedChinese ? "每天" : "Daily"
        case .weekdays: return language == .simplifiedChinese ? "工作日" : "Weekdays"
        case .weekly: return language == .simplifiedChinese ? "每周" : "Weekly"
        case .monthly: return language == .simplifiedChinese ? "每月" : "Monthly"
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
    var deletedAt: Date?
    var subtasks: [Subtask]

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
        generatedNextTaskID: UUID? = nil,
        deletedAt: Date? = nil,
        subtasks: [Subtask] = []
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
        self.deletedAt = deletedAt
        self.subtasks = subtasks.sorted { $0.position < $1.position }
    }

    var isCompleted: Bool { completedAt != nil }
    var isDeleted: Bool { deletedAt != nil }
    var completedSubtaskCount: Int { subtasks.filter(\.isCompleted).count }

    var normalizedDirection: String {
        direction.isEmpty ? "未分类" : direction
    }

    func displayDirection(in language: AppLanguage) -> String {
        direction.isEmpty && language == .english ? "Uncategorized" : normalizedDirection
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
        case deletedAt
        case subtasks
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
        deletedAt = try container.decodeIfPresent(Date.self, forKey: .deletedAt)
        subtasks = (try container.decodeIfPresent([Subtask].self, forKey: .subtasks) ?? [])
            .sorted { $0.position < $1.position }
    }
}

enum TaskPriorityFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case normal
    case important
    case urgent

    var id: String { rawValue }

    func title(in language: AppLanguage) -> String {
        switch self {
        case .all: return language == .simplifiedChinese ? "全部优先级" : "All Priorities"
        case .normal: return TaskPriority.normal.title(in: language)
        case .important: return TaskPriority.important.title(in: language)
        case .urgent: return TaskPriority.urgent.title(in: language)
        }
    }

    var priority: TaskPriority? { self == .all ? nil : TaskPriority(rawValue: rawValue) }
}

enum TaskDateFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case overdue
    case today
    case upcoming
    case unscheduled

    var id: String { rawValue }

    func title(in language: AppLanguage) -> String {
        switch self {
        case .all: return language == .simplifiedChinese ? "全部日期" : "All Dates"
        case .overdue: return language == .simplifiedChinese ? "已逾期" : "Overdue"
        case .today: return language == .simplifiedChinese ? "今天" : "Today"
        case .upcoming: return language == .simplifiedChinese ? "未来计划" : "Upcoming"
        case .unscheduled: return language == .simplifiedChinese ? "未安排" : "Unscheduled"
        }
    }
}

enum TaskFilter: String, CaseIterable, Identifiable {
    case today
    case inbox
    case completed

    var id: String { rawValue }

    func title(in language: AppLanguage) -> String {
        switch self {
        case .today: return language == .simplifiedChinese ? "今日任务" : "Today"
        case .inbox: return language == .simplifiedChinese ? "全部任务" : "All Tasks"
        case .completed: return language == .simplifiedChinese ? "已完成" : "Completed"
        }
    }

    var symbol: String {
        switch self {
        case .today: return "scope"
        case .inbox: return "tray.full"
        case .completed: return "checkmark.seal"
        }
    }
}

enum ReportPeriod: String, CaseIterable, Identifiable {
    case day
    case week
    case month

    var id: String { rawValue }

    func title(in language: AppLanguage) -> String {
        switch self {
        case .day: return language == .simplifiedChinese ? "日" : "Day"
        case .week: return language == .simplifiedChinese ? "周" : "Week"
        case .month: return language == .simplifiedChinese ? "月" : "Month"
        }
    }

    func reportTitle(in language: AppLanguage) -> String {
        switch self {
        case .day: return language == .simplifiedChinese ? "日度行动报告" : "Daily Action Report"
        case .week: return language == .simplifiedChinese ? "周度行动报告" : "Weekly Action Report"
        case .month: return language == .simplifiedChinese ? "月度行动报告" : "Monthly Action Report"
        }
    }
}

struct ReportSnapshot: Equatable {
    let interval: DateInterval
    let completed: [TaskItem]
    let createdCount: Int
    let directionCount: Int

    var completedCount: Int { completed.count }
    var estimatedMinutes: Int { completed.reduce(0) { $0 + $1.estimatedMinutes } }
}
