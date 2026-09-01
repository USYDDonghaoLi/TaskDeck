import SwiftUI

struct TaskBoardView: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var language: LanguageStore
    let filter: TaskFilter
    let direction: String?
    let onEdit: (TaskItem) -> Void

    private var tasks: [TaskItem] { store.tasks(for: filter, direction: direction) }

    private var groupedTasks: [(String, [TaskItem])] {
        Dictionary(grouping: tasks, by: \.normalizedDirection)
            .map { ($0.key, $0.value) }
            .sorted { $0.0.localizedCompare($1.0) == .orderedAscending }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                TodayPulse()

                if groupedTasks.isEmpty {
                    EmptyTasksView(filter: filter)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 54)
                } else {
                    ForEach(groupedTasks, id: \.0) { group in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("// \((group.0 == "未分类" ? language.text("未分类", "Uncategorized") : group.0).uppercased())")
                                    .font(.system(size: 9, weight: .black))
                                    .foregroundStyle(DeckTheme.cyan)
                                    .tracking(1.2)
                                Rectangle()
                                    .fill(DeckTheme.border)
                                    .frame(height: 1)
                                Text("\(group.1.count)")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(DeckTheme.muted)
                            }

                            ForEach(group.1) { task in
                                TaskCard(task: task, onEdit: onEdit)
                            }
                        }
                    }
                }
            }
            .padding(24)
        }
        .scrollIndicators(.never)
    }
}

private struct TodayPulse: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var language: LanguageStore

    var body: some View {
        HStack(spacing: 18) {
            ProgressRing(progress: store.todayProgress)
                .frame(width: 58, height: 58)

            VStack(alignment: .leading, spacing: 5) {
                Text("TODAY'S SIGNAL")
                    .font(.system(size: 8, weight: .black))
                    .foregroundStyle(DeckTheme.muted)
                    .tracking(1.5)
                Text(store.todayTotalCount == 0
                    ? language.text("等待任务注入", "Waiting for a task")
                    : language.format("已清除 %d / %d 个节点", "%d / %d nodes cleared", store.todayCompleted.count, store.todayTotalCount))
                    .font(.system(size: 13, weight: .bold))
                Text(store.todayTotalCount == 0
                    ? language.text("添加一个可执行、可计时的精准任务", "Add a precise, actionable task with a timer")
                    : statusLine)
                    .font(.system(size: 9))
                    .foregroundStyle(DeckTheme.muted)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text("\(Int(store.todayProgress * 100))%")
                    .font(.system(size: 23, weight: .black))
                    .foregroundStyle(DeckTheme.cyan)
                Text("COMPLETE")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(DeckTheme.muted)
                    .tracking(1.2)
            }
        }
        .deckPanel()
    }

    private var statusLine: String {
        switch store.todayProgress {
        case 0..<0.34: return language.text("系统已就绪，先拿下最小的一件事", "System ready. Start with the smallest action.")
        case 0..<0.75: return language.text("节奏建立中，保持当前推进速度", "Momentum established. Keep the current pace.")
        case 0..<1: return language.text("即将清空今日任务队列", "The queue is almost clear.")
        default: return language.text("今日任务队列已全部清空", "Today's queue is fully cleared.")
        }
    }
}

private struct ProgressRing: View {
    let progress: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(DeckTheme.panelRaised, lineWidth: 6)
            Circle()
                .trim(from: 0, to: max(0.015, progress))
                .stroke(
                    DeckTheme.cyan,
                    style: StrokeStyle(lineWidth: 6, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: DeckTheme.cyan.opacity(0.45), radius: 4)
            Image(systemName: progress >= 1 ? "checkmark" : "bolt.fill")
                .font(.system(size: 14, weight: .black))
                .foregroundStyle(progress >= 1 ? DeckTheme.lime : DeckTheme.cyan)
        }
    }
}

private struct TaskCard: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var notifications: NotificationManager
    @EnvironmentObject private var focus: FocusStore
    @EnvironmentObject private var language: LanguageStore
    let task: TaskItem
    let onEdit: (TaskItem) -> Void

    var body: some View {
        HStack(spacing: 14) {
            Button(action: toggle) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(task.isCompleted ? DeckTheme.lime : DeckTheme.panelRaised)
                        .frame(width: 27, height: 27)
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(task.isCompleted ? DeckTheme.lime : DeckTheme.cyan.opacity(0.45), lineWidth: 1)
                        .frame(width: 27, height: 27)
                    if task.isCompleted {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .black))
                            .foregroundStyle(DeckTheme.void)
                    }
                }
            }
            .buttonStyle(.plain)
            .help(task.isCompleted
                ? language.text("恢复为未完成", "Restore as incomplete")
                : language.text("标记完成", "Mark as completed"))

            VStack(alignment: .leading, spacing: 7) {
                Text(task.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(task.isCompleted ? DeckTheme.muted : DeckTheme.text)
                    .strikethrough(task.isCompleted, color: DeckTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)

                if !task.notes.isEmpty {
                    Text(task.notes)
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(DeckTheme.muted)
                        .lineLimit(2)
                }

                HStack(spacing: 12) {
                    if task.priority != .normal {
                        Label(task.priority.title(in: language.current), systemImage: task.priority.symbol)
                            .foregroundStyle(priorityColor)
                    }
                    Label(durationText, systemImage: "timer")
                    if focus.seconds(for: task.id) > 0 {
                        Label(actualFocusText, systemImage: "waveform.path.ecg")
                            .foregroundStyle(DeckTheme.cyan)
                    }
                    if let dueAt = task.dueAt {
                        Label(dueText(dueAt), systemImage: task.reminderEnabled ? "bell.fill" : "calendar")
                            .foregroundStyle(isOverdue(dueAt) && !task.isCompleted ? DeckTheme.warning : DeckTheme.muted)
                    }
                    if task.recurrence != .none {
                        Label(task.recurrence.title(in: language.current), systemImage: "repeat")
                    }
                }
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(DeckTheme.muted)
            }

            Spacer(minLength: 10)

            Button {
                _ = focus.beginOrToggle(task)
            } label: {
                Image(systemName: focusSymbol)
                    .font(.system(size: 10, weight: .black))
                    .foregroundStyle(isFocused ? DeckTheme.void : DeckTheme.cyan)
                    .frame(width: 28, height: 28)
                    .background(isFocused ? DeckTheme.cyan : DeckTheme.cyan.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(.plain)
            .disabled(task.isCompleted || (focus.active != nil && !isFocused))
            .opacity(task.isCompleted || (focus.active != nil && !isFocused) ? 0.35 : 1)
            .help(focusActionTitle)

            Menu {
                Button(language.text("编辑任务", "Edit Task")) { onEdit(task) }
                Button(task.isCompleted
                    ? language.text("恢复任务", "Restore Task")
                    : language.text("标记完成", "Mark Completed"), action: toggle)
                if !task.isCompleted && (focus.active == nil || isFocused) {
                    Button(focusActionTitle) {
                        _ = focus.beginOrToggle(task)
                    }
                }
                if !task.isCompleted {
                    Menu(language.text("推迟任务", "Postpone Task")) {
                        Button(language.text("一小时后", "In One Hour")) { reschedule(to: Date().addingTimeInterval(3_600)) }
                        Button(language.text("明天 09:00", "Tomorrow 09:00")) { reschedule(to: tomorrowMorning) }
                        Button(language.text("下周一 09:00", "Next Monday 09:00")) { reschedule(to: nextMondayMorning) }
                    }
                }
                Divider()
                Button(language.text("删除任务", "Delete Task"), role: .destructive) {
                    notifications.cancel(for: task)
                    withAnimation(.easeOut(duration: 0.18)) { store.delete(task) }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(DeckTheme.muted)
                    .frame(width: 28, height: 28)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(14)
        .background(task.isCompleted ? DeckTheme.panel.opacity(0.48) : DeckTheme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(task.isCompleted ? DeckTheme.border.opacity(0.5) : DeckTheme.border)
        )
        .overlay(alignment: .leading) {
            if task.priority != .normal && !task.isCompleted {
                RoundedRectangle(cornerRadius: 2)
                    .fill(priorityColor)
                    .frame(width: 3, height: 32)
                    .padding(.leading, 1)
            }
        }
    }

    private var durationText: String {
        task.estimatedMinutes >= 60
            ? String(format: "%.1f H", Double(task.estimatedMinutes) / 60.0)
            : "\(task.estimatedMinutes) MIN"
    }

    private var actualFocusText: String {
        let minutes = max(1, Int(round(Double(focus.seconds(for: task.id)) / 60)))
        return language.format("实投 %dM", "FOCUS %dM", minutes)
    }

    private var isFocused: Bool { focus.active?.taskID == task.id }

    private var focusSymbol: String {
        guard isFocused else { return "play.fill" }
        return focus.active?.isPaused == true ? "play.fill" : "pause.fill"
    }

    private var focusActionTitle: String {
        guard isFocused else { return language.text("开始专注", "Start Focus") }
        return focus.active?.isPaused == true
            ? language.text("继续专注", "Resume Focus")
            : language.text("暂停专注", "Pause Focus")
    }

    private func dueText(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return "\(language.text("今天", "Today")) \(date.formatted(date: .omitted, time: .shortened))"
        }
        return date.formatted(.dateTime.month(.twoDigits).day(.twoDigits).hour().minute())
    }

    private func isOverdue(_ date: Date) -> Bool { date < Date() }

    private var priorityColor: Color {
        switch task.priority {
        case .normal: return DeckTheme.cyan
        case .important: return DeckTheme.violet
        case .urgent: return DeckTheme.warning
        }
    }

    private var tomorrowMorning: Date {
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date().addingTimeInterval(86_400)
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) ?? tomorrow
    }

    private var nextMondayMorning: Date {
        let calendar = Calendar.current
        let now = Date()
        let weekday = calendar.component(.weekday, from: now)
        let daysUntilNextMonday = (9 - weekday) % 7
        let monday = calendar.date(byAdding: .day, value: daysUntilNextMonday, to: now) ?? now.addingTimeInterval(7 * 86_400)
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: monday) ?? monday
    }

    private func toggle() {
        let wasCompleted = task.isCompleted
        if !wasCompleted && isFocused { _ = focus.finish() }
        var generatedTask: TaskItem?
        withAnimation(.easeInOut(duration: 0.2)) { generatedTask = store.toggle(task) }
        if wasCompleted {
            notifications.schedule(for: task)
        } else {
            notifications.cancel(for: task)
        }
        if let generatedTask { notifications.schedule(for: generatedTask) }
    }

    private func reschedule(to date: Date) {
        notifications.cancel(for: task)
        if let updated = store.reschedule(task, to: date) {
            notifications.schedule(for: updated)
        }
    }
}

private struct EmptyTasksView: View {
    @EnvironmentObject private var language: LanguageStore
    let filter: TaskFilter

    var body: some View {
        VStack(spacing: 13) {
            ZStack {
                Circle()
                    .stroke(DeckTheme.cyan.opacity(0.15), lineWidth: 1)
                    .frame(width: 72, height: 72)
                Circle()
                    .stroke(DeckTheme.cyan.opacity(0.08), lineWidth: 1)
                    .frame(width: 52, height: 52)
                Image(systemName: filter == .completed ? "clock.arrow.circlepath" : "checkmark")
                    .font(.system(size: 20, weight: .light))
                    .foregroundStyle(DeckTheme.cyan)
            }
            Text(filter == .completed
                ? language.text("还没有完成记录", "No completed tasks yet")
                : language.text("任务队列为空", "Task queue is empty"))
                .font(.system(size: 12, weight: .bold))
            Text(filter == .completed
                ? language.text("完成任务后，战绩会出现在这里", "Your completed work will appear here.")
                : language.text("现在很安静。也许正适合开始一件重要的事。", "It is quiet here—perhaps a good time to begin something important."))
                .font(.system(size: 9))
                .foregroundStyle(DeckTheme.muted)
        }
    }
}
