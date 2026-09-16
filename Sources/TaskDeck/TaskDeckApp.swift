import AppKit
import Combine
import SwiftUI

@main
@MainActor
struct TaskDeckApp: App {
    @StateObject private var store: TaskStore
    @StateObject private var notifications: NotificationManager
    @StateObject private var focus: FocusStore
    @StateObject private var language: LanguageStore
    @StateObject private var focusHUD: FocusHUDController

    init() {
        let store = TaskStore()
        let notifications = NotificationManager()
        let focus = FocusStore()
        let language = LanguageStore()
        _store = StateObject(wrappedValue: store)
        _notifications = StateObject(wrappedValue: notifications)
        _focus = StateObject(wrappedValue: focus)
        _language = StateObject(wrappedValue: language)
        _focusHUD = StateObject(
            wrappedValue: FocusHUDController(
                store: store,
                notifications: notifications,
                focus: focus,
                language: language
            )
        )
    }

    var body: some Scene {
        WindowGroup("TaskDeck") {
            DashboardView()
                .environmentObject(store)
                .environmentObject(notifications)
                .environmentObject(focus)
                .environmentObject(language)
                .environment(\.locale, language.current.locale)
                .frame(minWidth: 1_020, minHeight: 680)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1_260, height: 800)
        .commands {
            CommandMenu("TaskDeck") {
                Button(language.text("新建精准任务", "New Precise Task")) {
                    NotificationCenter.default.post(name: .taskDeckNewTask, object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)

                Button(language.text("全局搜索", "Global Search")) {
                    NotificationCenter.default.post(name: .taskDeckFocusSearch, object: nil)
                }
                .keyboardShortcut("f", modifiers: .command)

                Button(language.text("清除搜索与筛选", "Clear Search & Filters")) {
                    NotificationCenter.default.post(name: .taskDeckClearFilters, object: nil)
                }
                .keyboardShortcut("f", modifiers: [.command, .option])

                Divider()

                Button(language.text("今日任务", "Today")) {
                    selectFilter(.today)
                }
                .keyboardShortcut("1", modifiers: .command)

                Button(language.text("全部任务", "All Tasks")) {
                    selectFilter(.inbox)
                }
                .keyboardShortcut("2", modifiers: .command)

                Button(language.text("已完成", "Completed")) {
                    selectFilter(.completed)
                }
                .keyboardShortcut("3", modifiers: .command)

                Divider()

                Button(language.text("打开桌面悬浮", "Open Desktop Board")) {
                    NotificationCenter.default.post(name: .taskDeckOpenDesktop, object: nil)
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])
            }
        }

        MenuBarExtra("TaskDeck", systemImage: "command") {
            MenuBarQuickAddView()
                .environmentObject(store)
                .environmentObject(language)
                .environment(\.locale, language.current.locale)
        }
        .menuBarExtraStyle(.window)

        WindowGroup("TaskDeck Desktop", id: "desktop") {
            DesktopWidgetView()
                .environmentObject(store)
                .environmentObject(notifications)
                .environmentObject(focus)
                .environmentObject(language)
                .environment(\.locale, language.current.locale)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 370, height: 520)

        Settings {
            SettingsView()
                .environmentObject(store)
                .environmentObject(notifications)
                .environmentObject(focus)
                .environmentObject(language)
                .environment(\.locale, language.current.locale)
        }
    }

    private func selectFilter(_ filter: TaskFilter) {
        NotificationCenter.default.post(name: .taskDeckSelectFilter, object: filter.rawValue)
    }
}

private struct MenuBarQuickAddView: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var language: LanguageStore
    @State private var direction = ""
    @State private var title = ""
    @State private var estimatedMinutes = 25
    @State private var priority: TaskPriority = .normal
    @State private var didSave = false

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("TASKDECK // QUICK INJECT")
                        .font(.system(size: 8, weight: .black))
                        .tracking(1.0)
                        .foregroundStyle(DeckTheme.cyan)
                    Text(language.text("菜单栏快速添加", "Menu Bar Quick Add"))
                        .font(.system(size: 14, weight: .black))
                }
                Spacer()
                if didSave {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(DeckTheme.lime)
                }
            }

            TextField(language.text("大方向（可选）", "Direction (optional)"), text: $direction)
                .quickAddField()
                .accessibilityLabel(language.text("大方向", "Direction"))
            TextField(language.text("精准任务描述", "Precise task description"), text: $title)
                .quickAddField()
                .onSubmit(save)
                .accessibilityLabel(language.text("精准任务描述", "Precise task description"))

            VStack(alignment: .leading, spacing: 5) {
                Text(language.text("预计时间", "Estimate").uppercased())
                    .font(.system(size: 7, weight: .black))
                    .foregroundStyle(DeckTheme.muted)
                DurationInputField(estimatedMinutes: $estimatedMinutes, showsHint: false)
            }

            Picker(language.text("优先级", "Priority"), selection: $priority) {
                ForEach(TaskPriority.allCases) { item in
                    Text(item.title(in: language.current)).tag(item)
                }
            }
            .labelsHidden()
            .frame(maxWidth: .infinity)
            .accessibilityLabel(language.text("优先级", "Priority"))

            Button(action: save) {
                Label(language.text("写入任务队列", "Add to Task Queue"), systemImage: "plus")
                    .font(.system(size: 10, weight: .black))
                    .foregroundStyle(DeckTheme.void)
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .background(canSave ? DeckTheme.cyan : DeckTheme.muted)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .disabled(!canSave)
            .keyboardShortcut(.defaultAction)

            Text(language.text("不必打开主窗口；任务会立即同步到桌面板和 Widget。", "No main window required; the task syncs to the desktop board and Widget immediately."))
                .font(.system(size: 7))
                .foregroundStyle(DeckTheme.muted)
        }
        .padding(16)
        .frame(width: 320)
        .background(DeckTheme.void)
        .foregroundStyle(DeckTheme.text)
        .fontDesign(.monospaced)
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func save() {
        guard canSave else { return }
        _ = store.add(
            direction: direction,
            title: title,
            estimatedMinutes: estimatedMinutes,
            priority: priority,
            dueAt: nil,
            reminderEnabled: false
        )
        title = ""
        didSave = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { didSave = false }
    }
}

private extension View {
    func quickAddField() -> some View {
        textFieldStyle(.plain)
            .font(.system(size: 10, weight: .medium))
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(DeckTheme.panelRaised)
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(DeckTheme.border))
    }
}

@MainActor
private final class FocusHUDController: ObservableObject {
    private let store: TaskStore
    private let notifications: NotificationManager
    private let focus: FocusStore
    private let language: LanguageStore
    private var panel: FocusHUDPanel?
    private var cancellables: Set<AnyCancellable> = []

    init(
        store: TaskStore,
        notifications: NotificationManager,
        focus: FocusStore,
        language: LanguageStore
    ) {
        self.store = store
        self.notifications = notifications
        self.focus = focus
        self.language = language

        focus.$active
            .receive(on: RunLoop.main)
            .sink { [weak self] active in
                let hasActiveFocus = active != nil
                Task { @MainActor [weak self] in
                    self?.synchronizeVisibility(hasActiveFocus: hasActiveFocus)
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.positionPanel()
            }
            .store(in: &cancellables)
    }

    private func synchronizeVisibility(hasActiveFocus: Bool) {
        if hasActiveFocus {
            let panel = panel ?? makePanel()
            self.panel = panel
            positionPanel()
            panel.orderFrontRegardless()
        } else {
            panel?.orderOut(nil)
        }
    }

    private func makePanel() -> FocusHUDPanel {
        let size = NSSize(width: 566, height: 78)
        let panel = FocusHUDPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.isExcludedFromWindowsMenu = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.animationBehavior = .utilityWindow
        panel.setAccessibilityLabel(language.text("专注悬浮控制条", "Focus floating controls"))

        let content = FocusHUDView(onCompleteTask: { [weak self] in
            self?.completeActiveTask()
        })
        .environmentObject(store)
        .environmentObject(notifications)
        .environmentObject(focus)
        .environmentObject(language)
        .environment(\.locale, language.current.locale)

        let hostingView = NSHostingView(rootView: content)
        hostingView.frame = NSRect(origin: .zero, size: size)
        panel.contentView = hostingView
        return panel
    }

    private func positionPanel() {
        guard let panel, panel.isVisible || focus.active != nil else { return }
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let visibleFrame = screen?.visibleFrame else { return }
        let origin = NSPoint(
            x: visibleFrame.midX - panel.frame.width / 2,
            y: visibleFrame.maxY - panel.frame.height - 10
        )
        panel.setFrameOrigin(origin)
    }

    private func completeActiveTask() {
        guard let active = focus.active else { return }
        let task = store.activeTasks.first { $0.id == active.taskID }
        _ = focus.finish()
        guard focus.active == nil, let task, !task.isCompleted else { return }
        notifications.cancel(for: task)
        if let generatedTask = store.toggle(task) {
            notifications.schedule(for: generatedTask)
        }
    }
}

private final class FocusHUDPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private struct FocusHUDView: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var focus: FocusStore
    @EnvironmentObject private var language: LanguageStore
    let onCompleteTask: () -> Void

    var body: some View {
        if let active = focus.active {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let elapsed = focus.elapsed(at: context.date)
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        Button {
                            active.isPaused ? focus.resume() : focus.pause()
                        } label: {
                            Image(systemName: active.isPaused ? "play.fill" : "pause.fill")
                                .font(.system(size: 11, weight: .black))
                                .foregroundStyle(DeckTheme.void)
                                .frame(width: 34, height: 34)
                                .background(active.isPaused ? DeckTheme.lime : DeckTheme.cyan)
                                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .help(active.isPaused
                            ? language.text("继续专注", "Resume focus")
                            : language.text("暂停专注", "Pause focus"))
                        .accessibilityLabel(active.isPaused
                            ? language.text("继续专注", "Resume focus")
                            : language.text("暂停专注", "Pause focus"))

                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(active.isPaused ? DeckTheme.lime : DeckTheme.cyan)
                                    .frame(width: 6, height: 6)
                                    .shadow(color: active.isPaused ? DeckTheme.lime : DeckTheme.cyan, radius: 4)
                                Text(active.isPaused
                                    ? language.text("专注已暂停", "FOCUS PAUSED")
                                    : language.text("专注进行中", "FOCUS ACTIVE"))
                                    .font(.system(size: 7, weight: .black))
                                    .tracking(0.9)
                                    .foregroundStyle(active.isPaused ? DeckTheme.lime : DeckTheme.cyan)
                                Text("// \(displayDirection(active.direction).uppercased())")
                                    .font(.system(size: 7, weight: .bold))
                                    .foregroundStyle(DeckTheme.muted)
                                    .lineLimit(1)
                            }
                            Text(active.taskTitle)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(DeckTheme.text)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Menu {
                            if switchableTasks.isEmpty {
                                Text(language.text("没有其他待办任务", "No other pending tasks"))
                            } else {
                                ForEach(switchableTasks) { task in
                                    Button {
                                        _ = focus.switchTo(task)
                                    } label: {
                                        Label(
                                            "\(task.title) · \(task.displayDirection(in: language.current))",
                                            systemImage: task.priority.symbol
                                        )
                                    }
                                }
                            }
                        } label: {
                            Image(systemName: "arrow.left.arrow.right")
                                .font(.system(size: 10, weight: .black))
                                .foregroundStyle(DeckTheme.cyan)
                                .frame(width: 34, height: 34)
                                .background(DeckTheme.cyan.opacity(0.10))
                                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                                        .stroke(DeckTheme.cyan.opacity(0.22), lineWidth: 1)
                                )
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .fixedSize()
                        .help(language.text("切换专注任务", "Switch focus task"))
                        .accessibilityLabel(language.text("打开任务切换菜单", "Open task switcher"))

                        VStack(alignment: .trailing, spacing: 2) {
                            Text(formatDuration(Int(elapsed)))
                                .font(.system(size: 17, weight: .black))
                                .foregroundStyle(DeckTheme.text)
                                .monospacedDigit()
                            Text(language.format("目标 %d 分钟", "TARGET %d MIN", active.estimatedMinutes))
                                .font(.system(size: 6, weight: .bold))
                                .foregroundStyle(DeckTheme.muted)
                        }

                        Button(action: onCompleteTask) {
                            Label(language.text("完成任务", "Complete"), systemImage: "checkmark")
                                .font(.system(size: 8, weight: .black))
                                .foregroundStyle(DeckTheme.void)
                                .padding(.horizontal, 11)
                                .frame(height: 34)
                                .background(DeckTheme.lime)
                                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .help(language.text("结束专注并完成任务", "Finish focus and complete task"))
                        .accessibilityLabel(language.text("结束专注并完成任务", "Finish focus and complete task") + " " + active.taskTitle)
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 72)

                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Rectangle().fill(DeckTheme.panelRaised)
                            Rectangle()
                                .fill(elapsed >= Double(active.estimatedMinutes * 60) ? DeckTheme.lime : DeckTheme.cyan)
                                .frame(width: geometry.size.width * progress(elapsed, targetMinutes: active.estimatedMinutes))
                        }
                    }
                    .frame(height: 2)
                }
                .background(DeckTheme.void.opacity(0.97))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(active.isPaused ? DeckTheme.lime.opacity(0.28) : DeckTheme.cyan.opacity(0.28), lineWidth: 1)
                )
                .padding(2)
            }
        } else {
            Color.clear
        }
    }

    private func displayDirection(_ direction: String) -> String {
        direction == "未分类" ? language.text("未分类", "Uncategorized") : direction
    }

    private var switchableTasks: [TaskItem] {
        guard let activeTaskID = focus.active?.taskID else { return [] }
        return store.pendingTasks.filter { $0.id != activeTaskID }
    }

    private func progress(_ elapsed: TimeInterval, targetMinutes: Int) -> Double {
        min(1, elapsed / Double(max(60, targetMinutes * 60)))
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
