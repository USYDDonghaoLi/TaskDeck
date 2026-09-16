import SwiftUI

struct FocusConsoleView: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var notifications: NotificationManager
    @EnvironmentObject private var focus: FocusStore
    @EnvironmentObject private var experience: FocusExperienceController
    @EnvironmentObject private var language: LanguageStore

    var body: some View {
        if let active = focus.active {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let elapsed = focus.elapsed(at: context.date)
                VStack(spacing: 0) {
                    HStack(spacing: 13) {
                        Button {
                            active.isPaused ? focus.resume() : focus.pause()
                        } label: {
                            Image(systemName: active.isPaused ? "play.fill" : "pause.fill")
                                .font(.system(size: 10, weight: .black))
                                .foregroundStyle(DeckTheme.void)
                                .frame(width: 30, height: 30)
                                .background(active.isPaused ? DeckTheme.lime : DeckTheme.cyan)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(active.isPaused
                            ? language.text("继续专注", "Resume focus")
                            : language.text("暂停专注", "Pause focus"))

                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 7) {
                                Text(active.isPaused
                                    ? language.text("专注已暂停", "FOCUS PAUSED")
                                    : language.text("专注频道运行中", "FOCUS CHANNEL ACTIVE"))
                                    .font(.system(size: 7, weight: .black))
                                    .foregroundStyle(active.isPaused ? DeckTheme.lime : DeckTheme.cyan)
                                    .tracking(1.1)
                                Text("// \((active.direction == "未分类" ? language.text("未分类", "Uncategorized") : active.direction).uppercased())")
                                    .font(.system(size: 7, weight: .bold))
                                    .foregroundStyle(DeckTheme.muted)
                            }
                            Text(active.taskTitle)
                                .font(.system(size: 10, weight: .bold))
                                .lineLimit(1)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 2) {
                            Text(formatDuration(Int(elapsed)))
                                .font(.system(size: 18, weight: .black))
                                .foregroundStyle(DeckTheme.text)
                                .monospacedDigit()
                            Text(language.format("目标 %d 分钟", "TARGET %d MIN", active.estimatedMinutes))
                                .font(.system(size: 7, weight: .bold))
                                .foregroundStyle(DeckTheme.muted)
                        }

                        FocusFinishButton(variant: .console)

                        Menu {
                            Button(language.text("放弃本次记录", "Discard This Session"), role: .destructive) { focus.discardActive() }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(DeckTheme.muted)
                                .frame(width: 24, height: 28)
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .fixedSize()
                        .accessibilityLabel(language.text("更多专注操作", "More focus actions"))
                    }
                    .padding(.horizontal, 20)
                    .frame(height: 56)

                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Rectangle().fill(DeckTheme.panelRaised)
                            Rectangle()
                                .fill(elapsed >= Double(active.estimatedMinutes * 60) ? DeckTheme.lime : DeckTheme.cyan)
                                .frame(width: geometry.size.width * min(1, elapsed / Double(max(60, active.estimatedMinutes * 60))))
                        }
                    }
                    .frame(height: 2)
                }
                .background(DeckTheme.panel.opacity(0.88))
            }
        }
    }

    private func formatDuration(_ seconds: Int) -> String {
        let hours = seconds / 3_600
        let minutes = (seconds % 3_600) / 60
        let remaining = seconds % 60
        return hours > 0
            ? String(format: "%02d:%02d:%02d", hours, minutes, remaining)
            : String(format: "%02d:%02d", minutes, remaining)
    }
}

enum FocusFinishButtonVariant {
    case hud
    case console
    case desktop
}

private enum FocusFinishAction: Equatable {
    case stop
    case complete
    case next
}

struct FocusFinishButton: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var notifications: NotificationManager
    @EnvironmentObject private var focus: FocusStore
    @EnvironmentObject private var experience: FocusExperienceController
    @EnvironmentObject private var language: LanguageStore

    let variant: FocusFinishButtonVariant
    @State private var isPresented = false
    @State private var note = ""

    var body: some View {
        Button { isPresented.toggle() } label: {
            buttonLabel
        }
        .buttonStyle(.plain)
        .help(language.text("选择如何结束本次专注", "Choose how to finish this focus session"))
        .accessibilityLabel(language.text("结束专注选项", "Finish focus options"))
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            finishPopover
        }
        .onChange(of: focus.active?.taskID) { _ in
            isPresented = false
            note = ""
        }
    }

    @ViewBuilder
    private var buttonLabel: some View {
        switch variant {
        case .hud:
            Label(language.text("结束", "Finish"), systemImage: "stop.fill")
                .font(.system(size: 8, weight: .black))
                .foregroundStyle(DeckTheme.text)
                .padding(.horizontal, 11)
                .frame(height: 34)
                .background(DeckTheme.panelRaised)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(DeckTheme.border))
        case .console:
            Text(language.text("结束专注", "Finish Focus"))
                .font(.system(size: 8, weight: .black))
                .foregroundStyle(DeckTheme.text)
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(DeckTheme.panelRaised)
                .clipShape(RoundedRectangle(cornerRadius: 7))
        case .desktop:
            Text(language.text("结束", "Finish"))
                .font(.system(size: 7, weight: .black))
                .foregroundStyle(DeckTheme.muted)
        }
    }

    private var finishPopover: some View {
        VStack(alignment: .leading, spacing: 13) {
            VStack(alignment: .leading, spacing: 3) {
                Text("FOCUS // WRAP UP")
                    .font(.system(size: 8, weight: .black))
                    .tracking(1.1)
                    .foregroundStyle(DeckTheme.cyan)
                Text(language.text("结束本次专注", "Finish This Focus Session"))
                    .font(.system(size: 14, weight: .black))
                Text(focus.active?.taskTitle ?? "")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(DeckTheme.muted)
                    .lineLimit(1)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(language.text("本次完成了什么（可选）", "What did you accomplish? (optional)"))
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(DeckTheme.muted)
                TextField(language.text("用一句话记录成果", "Capture the outcome in one sentence"), text: $note)
                    .textFieldStyle(.plain)
                    .font(.system(size: 9, weight: .medium))
                    .padding(.horizontal, 10)
                    .frame(height: 34)
                    .background(DeckTheme.panelRaised)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(DeckTheme.border))
            }

            VStack(spacing: 7) {
                finishOption(
                    title: language.text("仅结束专注", "Finish Focus Only"),
                    detail: language.text("任务仍保持未完成", "Keep the task open"),
                    symbol: "stop.circle",
                    color: DeckTheme.cyan,
                    action: .stop
                )
                finishOption(
                    title: language.text("结束并完成任务", "Finish and Complete Task"),
                    detail: language.text("勾选任务并保留专注记录", "Complete the task and keep the focus history"),
                    symbol: "checkmark.circle.fill",
                    color: DeckTheme.lime,
                    action: .complete
                )
                finishOption(
                    title: language.text("结束并切换到下一项", "Finish and Start Next"),
                    detail: nextTask.map { language.text("下一项：", "Next: ") + $0.title }
                        ?? language.text("没有其他待办任务", "No other pending task"),
                    symbol: "arrow.right.circle.fill",
                    color: DeckTheme.warning,
                    action: .next,
                    isDisabled: nextTask == nil
                )
            }
        }
        .padding(16)
        .frame(width: 380)
        .background(DeckTheme.void)
        .foregroundStyle(DeckTheme.text)
        .fontDesign(.monospaced)
    }

    private func finishOption(
        title: String,
        detail: String,
        symbol: String,
        color: Color,
        action: FocusFinishAction,
        isDisabled: Bool = false
    ) -> some View {
        Button { finish(action) } label: {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(color)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 9, weight: .black))
                    Text(detail)
                        .font(.system(size: 7))
                        .foregroundStyle(DeckTheme.muted)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(DeckTheme.muted)
            }
            .padding(.horizontal, 10)
            .frame(height: 46)
            .background(DeckTheme.panel)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(DeckTheme.border))
            .opacity(isDisabled ? 0.45 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }

    private var nextTask: TaskItem? {
        guard let activeTaskID = focus.active?.taskID else { return nil }
        return store.pendingTasks.first { $0.id != activeTaskID }
    }

    private func finish(_ action: FocusFinishAction) {
        guard let active = focus.active else { return }
        let currentTask = store.activeTasks.first { $0.id == active.taskID }
        let followingTask = nextTask
        _ = focus.finish(note: note)
        guard focus.active == nil else { return }

        if action == .complete, let currentTask, !currentTask.isCompleted {
            notifications.cancel(for: currentTask)
            if let generatedTask = store.toggle(currentTask) {
                notifications.schedule(for: generatedTask)
            }
        } else if action == .next, let followingTask,
                  focus.beginOrToggle(followingTask) {
            experience.recordRecentTask(followingTask.id)
        }

        note = ""
        isPresented = false
    }
}
