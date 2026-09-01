import SwiftUI
import UserNotifications

struct TaskComposerView: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var notifications: NotificationManager
    @EnvironmentObject private var language: LanguageStore
    @Environment(\.dismiss) private var dismiss

    private let editingTask: TaskItem?
    private let durationPresets = [15, 25, 45, 60, 90]

    @State private var direction: String
    @State private var title: String
    @State private var notes: String
    @State private var estimatedMinutes: Int
    @State private var priority: TaskPriority
    @State private var hasDueDate: Bool
    @State private var dueAt: Date
    @State private var reminderEnabled: Bool
    @State private var recurrence: TaskRecurrence
    @State private var subtasks: [Subtask]
    @State private var newSubtaskTitle = ""

    init(editingTask: TaskItem? = nil) {
        self.editingTask = editingTask
        _direction = State(initialValue: editingTask?.direction ?? "")
        _title = State(initialValue: editingTask?.title ?? "")
        _notes = State(initialValue: editingTask?.notes ?? "")
        _estimatedMinutes = State(initialValue: editingTask?.estimatedMinutes ?? 25)
        _priority = State(initialValue: editingTask?.priority ?? .normal)
        _hasDueDate = State(initialValue: editingTask?.dueAt != nil || editingTask == nil)
        _dueAt = State(initialValue: editingTask?.dueAt ?? Date().addingTimeInterval(3_600))
        _reminderEnabled = State(initialValue: editingTask?.reminderEnabled ?? false)
        _recurrence = State(initialValue: editingTask?.recurrence ?? .none)
        _subtasks = State(initialValue: editingTask?.subtasks ?? [])
    }

    var body: some View {
        ZStack {
            DeckTheme.void.ignoresSafeArea()
            GridBackground().ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                header

                Rectangle()
                    .fill(DeckTheme.border)
                    .frame(height: 1)
                    .padding(.vertical, 18)

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        directionSection
                        descriptionSection
                        subtaskSection
                        prioritySection
                        durationSection
                        schedulingSection
                    }
                    .padding(.trailing, 4)
                }
                .scrollIndicators(.never)

                actionBar
                    .padding(.top, 18)
            }
            .padding(26)
        }
        .frame(width: 560, height: 780)
        .foregroundStyle(DeckTheme.text)
        .fontDesign(.monospaced)
        .onChange(of: recurrence) { value in
            if value != .none { hasDueDate = true }
        }
        .onChange(of: hasDueDate) { enabled in
            if !enabled {
                reminderEnabled = false
                recurrence = .none
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 5) {
                Text(editingTask == nil ? "INJECT NEW TASK" : "PATCH TASK NODE")
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(DeckTheme.cyan)
                    .tracking(1.7)
                Text(editingTask == nil
                    ? language.text("创建精准任务", "Create Precise Task")
                    : language.text("编辑精准任务", "Edit Precise Task"))
                    .font(.system(size: 21, weight: .black))
                Text(editingTask == nil
                    ? language.text("方向决定为什么做，描述明确下一步做什么。", "The direction explains why; the description defines the next action.")
                    : language.text("任务 ID 与历史记录保持不变。", "The task ID and history remain unchanged."))
                    .font(.system(size: 10))
                    .foregroundStyle(DeckTheme.muted)
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(DeckTheme.muted)
                    .frame(width: 30, height: 30)
                    .background(DeckTheme.panelRaised)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
        }
    }

    private var directionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            FieldLabel(number: "01", text: language.text("大方向", "Direction"))
            TextField(language.text("例如：产品发布 / 健身 / 学习", "e.g. Product Launch / Fitness / Learning"), text: $direction)
                .deckTextField()

            if !store.directions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        ForEach(store.directions, id: \.self) { item in
                            Button(item) { direction = item }
                                .buttonStyle(.plain)
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(direction == item ? DeckTheme.void : DeckTheme.muted)
                                .padding(.horizontal, 9)
                                .frame(height: 24)
                                .background(direction == item ? DeckTheme.cyan : DeckTheme.panelRaised)
                                .clipShape(Capsule())
                        }
                    }
                }
            }
        }
    }

    private var descriptionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            FieldLabel(number: "02", text: language.text("精准任务描述", "Precise Task Description"))
            ZStack(alignment: .topLeading) {
                if title.isEmpty {
                    Text(language.text("用动词开头，例如：整理反馈并输出 3 条改版结论", "Start with a verb, e.g. Review feedback and write three decisions"))
                        .font(.system(size: 11))
                        .foregroundStyle(DeckTheme.muted.opacity(0.72))
                        .padding(.horizontal, 13)
                        .padding(.vertical, 12)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $title)
                    .font(.system(size: 12, weight: .medium))
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(height: 72)
            }
            .background(DeckTheme.panel)
            .clipShape(RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(DeckTheme.border))

            TextField(language.text("补充备注（可选）", "Additional notes (optional)"), text: $notes)
                .deckTextField()
        }
    }

    private var prioritySection: some View {
        VStack(alignment: .leading, spacing: 9) {
            FieldLabel(number: "04", text: language.text("优先级", "Priority"))
            HStack(spacing: 7) {
                ForEach(TaskPriority.allCases) { item in
                    Button { priority = item } label: {
                        Label(item.title(in: language.current), systemImage: item.symbol)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(priority == item ? DeckTheme.void : priorityColor(item))
                            .frame(maxWidth: .infinity)
                            .frame(height: 32)
                            .background(priority == item ? priorityColor(item) : DeckTheme.panelRaised)
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var subtaskSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                FieldLabel(number: "03", text: language.text("子任务", "Subtasks"))
                Spacer()
                if !subtasks.isEmpty {
                    Text("\(subtasks.filter(\.isCompleted).count)/\(subtasks.count)")
                        .font(.system(size: 8, weight: .black))
                        .foregroundStyle(DeckTheme.cyan)
                }
            }

            ForEach($subtasks) { $subtask in
                HStack(spacing: 9) {
                    Button {
                        subtask.completedAt = subtask.isCompleted ? nil : Date()
                    } label: {
                        Image(systemName: subtask.isCompleted ? "checkmark.square.fill" : "square")
                            .foregroundStyle(subtask.isCompleted ? DeckTheme.lime : DeckTheme.cyan)
                    }
                    .buttonStyle(.plain)
                    TextField(language.text("子任务描述", "Subtask description"), text: $subtask.title)
                        .textFieldStyle(.plain)
                        .font(.system(size: 10, weight: .medium))
                        .strikethrough(subtask.isCompleted)
                    Button {
                        subtasks.removeAll { $0.id == subtask.id }
                        normalizeSubtaskPositions()
                    } label: {
                        Image(systemName: "xmark")
                            .foregroundStyle(DeckTheme.muted)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 11)
                .frame(height: 34)
                .background(DeckTheme.panelRaised)
                .clipShape(RoundedRectangle(cornerRadius: 7))
            }

            HStack(spacing: 8) {
                TextField(language.text("添加一个可勾选的步骤", "Add a checkable step"), text: $newSubtaskTitle)
                    .deckTextField()
                    .onSubmit(addSubtaskDraft)
                Button(action: addSubtaskDraft) {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(DeckTheme.void)
                        .frame(width: 34, height: 34)
                        .background(DeckTheme.cyan)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .disabled(newSubtaskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private var durationSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            FieldLabel(number: "05", text: language.text("预计时间", "Estimated Time"))
            HStack(spacing: 7) {
                ForEach(durationPresets, id: \.self) { minutes in
                    Button(durationLabel(minutes)) { estimatedMinutes = minutes }
                        .buttonStyle(.plain)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(estimatedMinutes == minutes ? DeckTheme.void : DeckTheme.muted)
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                        .background(estimatedMinutes == minutes ? DeckTheme.cyan : DeckTheme.panelRaised)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                }
            }
            Stepper(language.format("自定义：%d 分钟", "Custom: %d minutes", estimatedMinutes), value: $estimatedMinutes, in: 5...480, step: 5)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(DeckTheme.muted)
        }
    }

    private var schedulingSection: some View {
        VStack(alignment: .leading, spacing: 11) {
            Toggle(isOn: $hasDueDate) {
                FieldLabel(number: "06", text: language.text("计划与重复", "Schedule & Repeat"))
            }
            .toggleStyle(.switch)

            if hasDueDate {
                DatePicker(
                    language.text("执行 / 提醒时间", "Schedule / Reminder Time"),
                    selection: $dueAt,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .font(.system(size: 10, weight: .medium))
                .datePickerStyle(.field)

                HStack {
                    Text(language.text("重复规则", "Repeat"))
                        .font(.system(size: 10, weight: .medium))
                    Spacer()
                    Picker(language.text("重复规则", "Repeat"), selection: $recurrence) {
                        ForEach(TaskRecurrence.allCases) { item in
                            Text(item.title(in: language.current)).tag(item)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 150)
                }

                Toggle(language.text("到时间发送系统通知", "Send a macOS notification"), isOn: $reminderEnabled)
                    .toggleStyle(.switch)
                    .font(.system(size: 10, weight: .medium))

                if notifications.authorizationStatus == .denied {
                    Label(language.text(
                        "通知权限已关闭，可在“系统设置 → 通知 → TaskDeck”中开启",
                        "Notifications are disabled. Enable TaskDeck in System Settings → Notifications."
                    ), systemImage: "exclamationmark.triangle")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(DeckTheme.warning)
                }
            }
        }
    }

    private var actionBar: some View {
        HStack(spacing: 10) {
            Button(language.text("取消", "Cancel")) { dismiss() }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(DeckTheme.muted)
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .background(DeckTheme.panelRaised)
                .clipShape(RoundedRectangle(cornerRadius: 9))

            Button(action: saveTask) {
                Label(
                    editingTask == nil
                        ? language.text("写入任务队列", "Add to Task Queue")
                        : language.text("保存任务修改", "Save Changes"),
                    systemImage: editingTask == nil ? "arrow.down.to.line" : "checkmark"
                )
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(DeckTheme.void)
                    .frame(maxWidth: .infinity)
                    .frame(height: 42)
                    .background(canSave ? DeckTheme.cyan : DeckTheme.muted)
                    .clipShape(RoundedRectangle(cornerRadius: 9))
            }
            .buttonStyle(.plain)
            .disabled(!canSave)
            .keyboardShortcut(.return, modifiers: .command)
        }
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func durationLabel(_ minutes: Int) -> String {
        minutes >= 60 ? "\(minutes / 60)H\(minutes % 60 == 0 ? "" : "\(minutes % 60)")" : "\(minutes)M"
    }

    private func priorityColor(_ item: TaskPriority) -> Color {
        switch item {
        case .normal: return DeckTheme.cyan
        case .important: return DeckTheme.violet
        case .urgent: return DeckTheme.warning
        }
    }

    private func saveTask() {
        guard canSave else { return }
        if reminderEnabled && hasDueDate && notifications.authorizationStatus == .notDetermined {
            notifications.requestAuthorization()
        }

        let savedTask: TaskItem?
        if var task = editingTask {
            notifications.cancel(for: task)
            task.direction = direction
            task.title = title
            task.notes = notes
            task.estimatedMinutes = estimatedMinutes
            task.priority = priority
            task.dueAt = hasDueDate ? dueAt : nil
            task.reminderEnabled = reminderEnabled && hasDueDate
            task.recurrence = hasDueDate ? recurrence : .none
            task.subtasks = subtasks
            savedTask = store.update(task)
        } else {
            savedTask = store.add(
                direction: direction,
                title: title,
                notes: notes,
                estimatedMinutes: estimatedMinutes,
                priority: priority,
                dueAt: hasDueDate ? dueAt : nil,
                reminderEnabled: reminderEnabled && hasDueDate,
                recurrence: hasDueDate ? recurrence : .none,
                subtasks: subtasks
            )
        }

        if let savedTask { notifications.schedule(for: savedTask) }
        dismiss()
    }

    private func addSubtaskDraft() {
        let cleanTitle = newSubtaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { return }
        subtasks.append(Subtask(title: cleanTitle, position: subtasks.count))
        newSubtaskTitle = ""
    }

    private func normalizeSubtaskPositions() {
        subtasks = subtasks.enumerated().map { position, value in
            var subtask = value
            subtask.position = position
            return subtask
        }
    }
}

private struct FieldLabel: View {
    let number: String
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Text(number).foregroundStyle(DeckTheme.cyan)
            Text(text.uppercased()).foregroundStyle(DeckTheme.muted)
        }
        .font(.system(size: 8, weight: .black))
        .tracking(1.1)
    }
}

private extension View {
    func deckTextField() -> some View {
        self
            .textFieldStyle(.plain)
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 13)
            .frame(height: 40)
            .background(DeckTheme.panel)
            .clipShape(RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(DeckTheme.border))
    }
}
