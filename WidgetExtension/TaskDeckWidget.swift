import AppIntents
import SwiftUI
import WidgetKit

private enum WidgetPalette {
    static let void = Color(red: 0.035, green: 0.047, blue: 0.071)
    static let panel = Color(red: 0.063, green: 0.082, blue: 0.118)
    static let cyan = Color(red: 0.20, green: 0.91, blue: 0.96)
    static let lime = Color(red: 0.56, green: 0.95, blue: 0.38)
    static let text = Color(red: 0.91, green: 0.95, blue: 0.98)
    static let muted = Color(red: 0.48, green: 0.57, blue: 0.66)
    static let border = Color(red: 0.15, green: 0.22, blue: 0.30)
}

struct TaskDeckWidgetEntry: TimelineEntry {
    let date: Date
    let tasks: [TaskItem]
    let language: AppLanguage
}

struct TaskDeckTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> TaskDeckWidgetEntry {
        TaskDeckWidgetEntry(
            date: Date(),
            tasks: [
                TaskItem(direction: "VIBE CODING", title: "Ship the next precise task", estimatedMinutes: 25),
                TaskItem(direction: "LEARNING", title: "Review WidgetKit notes", estimatedMinutes: 15)
            ],
            language: .english
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (TaskDeckWidgetEntry) -> Void) {
        completion(entry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TaskDeckWidgetEntry>) -> Void) {
        let value = entry()
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 15, to: value.date)
            ?? value.date.addingTimeInterval(900)
        completion(Timeline(entries: [value], policy: .after(nextRefresh)))
    }

    private func entry() -> TaskDeckWidgetEntry {
        TaskDeckWidgetEntry(
            date: Date(),
            tasks: ((try? TaskDeckShared.loadTasks()) ?? []).filter { !$0.isDeleted },
            language: TaskDeckShared.storedLanguage()
        )
    }
}

struct ToggleTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "Toggle Task"
    static let description = IntentDescription("Mark a TaskDeck task complete or restore it.")
    static let openAppWhenRun = false

    @Parameter(title: "Task ID")
    var taskID: String

    init() {
        taskID = ""
    }

    init(taskID: String) {
        self.taskID = taskID
    }

    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: taskID) else { return .result() }
        _ = try TaskDeckShared.toggleTask(id: id)
        WidgetCenter.shared.reloadTimelines(ofKind: TaskDeckShared.widgetKind)
        return .result()
    }
}

@main
struct TaskDeckWidgetBundle: WidgetBundle {
    var body: some Widget {
        TaskDeckTodayWidget()
    }
}

struct TaskDeckTodayWidget: Widget {
    let kind = TaskDeckShared.widgetKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TaskDeckTimelineProvider()) { entry in
            TaskDeckWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    WidgetPalette.void
                }
        }
        .configurationDisplayName("TaskDeck")
        .description("Today progress and interactive tasks from TaskDeck.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

private struct TaskDeckWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TaskDeckWidgetEntry

    var body: some View {
        Group {
            switch family {
            case .systemSmall:
                SmallProgressView(entry: entry)
            case .systemMedium:
                TaskListWidgetView(entry: entry, limit: 3, showsDirection: false)
            default:
                TaskListWidgetView(entry: entry, limit: 6, showsDirection: true)
            }
        }
        .fontDesign(.monospaced)
        .foregroundStyle(WidgetPalette.text)
    }
}

private struct SmallProgressView: View {
    let entry: TaskDeckWidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("TASKDECK", systemImage: "command")
                    .font(.system(size: 9, weight: .black))
                    .tracking(0.8)
                    .foregroundStyle(WidgetPalette.cyan)
                Spacer()
                Circle()
                    .fill(WidgetPalette.lime)
                    .frame(width: 6, height: 6)
            }

            Spacer(minLength: 0)

            ZStack {
                Circle()
                    .stroke(WidgetPalette.border, lineWidth: 8)
                Circle()
                    .trim(from: 0, to: max(progress, 0.015))
                    .stroke(WidgetPalette.cyan, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 1) {
                    Text("\(Int(progress * 100))%")
                        .font(.system(size: 23, weight: .black))
                    Text(text("今日", "TODAY"))
                        .font(.system(size: 7, weight: .bold))
                        .tracking(1)
                        .foregroundStyle(WidgetPalette.muted)
                }
            }
            .frame(maxWidth: .infinity)

            Spacer(minLength: 0)

            Text(text("完成 \(completed.count) / \(todayTasks.count)", "\(completed.count) / \(todayTasks.count) COMPLETE"))
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(WidgetPalette.muted)
                .frame(maxWidth: .infinity)
        }
        .widgetURL(URL(string: "taskdeck://today"))
    }

    private var todayTasks: [TaskItem] {
        entry.tasks.filter { task in
            if let completedAt = task.completedAt {
                return Calendar.current.isDateInToday(completedAt)
            }
            guard let dueAt = task.dueAt else { return true }
            return Calendar.current.isDateInToday(dueAt) || dueAt < Calendar.current.startOfDay(for: entry.date)
        }
    }

    private var completed: [TaskItem] { todayTasks.filter(\.isCompleted) }
    private var progress: Double {
        todayTasks.isEmpty ? 0 : Double(completed.count) / Double(todayTasks.count)
    }

    private func text(_ chinese: String, _ english: String) -> String {
        entry.language == .simplifiedChinese ? chinese : english
    }
}

private struct TaskListWidgetView: View {
    let entry: TaskDeckWidgetEntry
    let limit: Int
    let showsDirection: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: showsDirection ? 8 : 7) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("TASKDECK // TODAY")
                        .font(.system(size: 10, weight: .black))
                        .tracking(0.8)
                        .foregroundStyle(WidgetPalette.cyan)
                    Text(text("精准任务队列", "PRECISE TASK QUEUE"))
                        .font(.system(size: 7, weight: .bold))
                        .tracking(0.7)
                        .foregroundStyle(WidgetPalette.muted)
                }
                Spacer()
                Text("\(pending.count)")
                    .font(.system(size: 16, weight: .black))
                Text(text("待办", "OPEN"))
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(WidgetPalette.muted)
            }

            Rectangle()
                .fill(WidgetPalette.border)
                .frame(height: 1)

            if visibleTasks.isEmpty {
                Spacer()
                Label(text("今日队列已清空", "TODAY'S QUEUE IS CLEAR"), systemImage: "checkmark.seal.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(WidgetPalette.lime)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ForEach(visibleTasks) { task in
                    WidgetTaskRow(task: task, language: entry.language, showsDirection: showsDirection)
                    if task.id != visibleTasks.last?.id {
                        Rectangle()
                            .fill(WidgetPalette.border.opacity(0.65))
                            .frame(height: 1)
                    }
                }
                Spacer(minLength: 0)
            }

            if pending.count > visibleTasks.count {
                Text(text("还有 \(pending.count - visibleTasks.count) 项 · 点击任务打开应用", "+\(pending.count - visibleTasks.count) MORE · CLICK A TASK TO OPEN"))
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(WidgetPalette.muted)
            }
        }
    }

    private var pending: [TaskItem] {
        entry.tasks
            .filter { !$0.isCompleted }
            .sorted(by: taskSort)
    }

    private var todayPending: [TaskItem] {
        pending.filter { task in
            guard let dueAt = task.dueAt else { return true }
            return Calendar.current.isDateInToday(dueAt) || dueAt < Calendar.current.startOfDay(for: entry.date)
        }
    }

    private var visibleTasks: [TaskItem] {
        Array((todayPending.isEmpty ? pending : todayPending).prefix(limit))
    }

    private func taskSort(_ lhs: TaskItem, _ rhs: TaskItem) -> Bool {
        if lhs.priority != rhs.priority { return lhs.priority.sortOrder > rhs.priority.sortOrder }
        switch (lhs.dueAt, rhs.dueAt) {
        case let (left?, right?) where left != right: return left < right
        case (_?, nil): return true
        case (nil, _?): return false
        default: return lhs.createdAt > rhs.createdAt
        }
    }

    private func text(_ chinese: String, _ english: String) -> String {
        entry.language == .simplifiedChinese ? chinese : english
    }
}

private struct WidgetTaskRow: View {
    let task: TaskItem
    let language: AppLanguage
    let showsDirection: Bool

    var body: some View {
        HStack(spacing: 9) {
            Button(intent: ToggleTaskIntent(taskID: task.id.uuidString)) {
                Image(systemName: "square")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(WidgetPalette.cyan)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(text("标记完成", "Mark complete"))

            Link(destination: URL(string: "taskdeck://task/\(task.id.uuidString)")!) {
                VStack(alignment: .leading, spacing: showsDirection ? 3 : 1) {
                    if showsDirection {
                        Text("// \(task.displayDirection(in: language).uppercased())")
                            .font(.system(size: 7, weight: .black))
                            .tracking(0.7)
                            .foregroundStyle(WidgetPalette.cyan)
                            .lineLimit(1)
                    }
                    Text(task.title)
                        .font(.system(size: showsDirection ? 11 : 10, weight: .semibold))
                        .foregroundStyle(WidgetPalette.text)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Label(durationText, systemImage: "timer")
                .labelStyle(.titleAndIcon)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(WidgetPalette.muted)
                .fixedSize()
        }
        .frame(maxWidth: .infinity)
    }

    private var durationText: String {
        task.estimatedMinutes >= 60
            ? String(format: "%.1fH", Double(task.estimatedMinutes) / 60)
            : "\(task.estimatedMinutes)M"
    }

    private func text(_ chinese: String, _ english: String) -> String {
        language == .simplifiedChinese ? chinese : english
    }
}
