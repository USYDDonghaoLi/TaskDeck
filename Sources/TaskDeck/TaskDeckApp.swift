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
    @StateObject private var focusExperience: FocusExperienceController
    @StateObject private var focusHUD: FocusHUDController

    init() {
        let store = TaskStore()
        let notifications = NotificationManager()
        let focus = FocusStore()
        let language = LanguageStore()
        let focusExperience = FocusExperienceController(
            focus: focus,
            notifications: notifications,
            language: language
        )
        _store = StateObject(wrappedValue: store)
        _notifications = StateObject(wrappedValue: notifications)
        _focus = StateObject(wrappedValue: focus)
        _language = StateObject(wrappedValue: language)
        _focusExperience = StateObject(wrappedValue: focusExperience)
        _focusHUD = StateObject(
            wrappedValue: FocusHUDController(
                store: store,
                notifications: notifications,
                focus: focus,
                language: language,
                experience: focusExperience
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
                .environmentObject(focusExperience)
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

                Button(language.text("切换专注任务", "Switch Focus Task")) {
                    NotificationCenter.default.post(name: .taskDeckOpenFocusSwitcher, object: nil)
                }
                .keyboardShortcut("k", modifiers: [.command, .option])

                Button(language.text("切换到最近任务", "Switch to Recent Task")) {
                    switchToRecentTask()
                }
                .keyboardShortcut("j", modifiers: [.command, .option])
                .disabled(focus.active == nil)
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
                .environmentObject(focusExperience)
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
                .environmentObject(focusExperience)
                .environment(\.locale, language.current.locale)
        }
    }

    private func selectFilter(_ filter: TaskFilter) {
        NotificationCenter.default.post(name: .taskDeckSelectFilter, object: filter.rawValue)
    }

    private func switchToRecentTask() {
        guard let activeTaskID = focus.active?.taskID else { return }
        let pending = store.pendingTasks.filter { $0.id != activeTaskID }
        let recent = focusExperience.recentTaskIDs
            .compactMap { id in pending.first { $0.id == id } }
            .first
        guard let target = recent ?? pending.first, focus.switchTo(target) else { return }
        focusExperience.recordRecentTask(target.id)
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
    private let experience: FocusExperienceController
    private var panel: FocusHUDPanel?
    private var cancellables: Set<AnyCancellable> = []

    init(
        store: TaskStore,
        notifications: NotificationManager,
        focus: FocusStore,
        language: LanguageStore,
        experience: FocusExperienceController
    ) {
        self.store = store
        self.notifications = notifications
        self.focus = focus
        self.language = language
        self.experience = experience

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
        let size = NSSize(width: 640, height: 82)
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

        let content = FocusHUDView()
        .environmentObject(store)
        .environmentObject(notifications)
        .environmentObject(focus)
        .environmentObject(language)
        .environmentObject(experience)
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

}

private final class FocusHUDPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private struct FocusHUDView: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var focus: FocusStore
    @EnvironmentObject private var experience: FocusExperienceController
    @EnvironmentObject private var language: LanguageStore
    @State private var isSwitcherPresented = false
    @State private var switchSearch = ""

    var body: some View {
        Group {
            if let review = experience.pendingIdleReview {
                idleReviewHUD(review)
            } else if let currentBreak = experience.pomodoroBreak {
                breakHUD(currentBreak)
            } else if let active = focus.active {
                activeHUD(active)
            } else {
                Color.clear
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .taskDeckOpenFocusSwitcher)) { _ in
            guard focus.active != nil, experience.pendingIdleReview == nil else { return }
            switchSearch = ""
            isSwitcherPresented = true
        }
        .onChange(of: focus.active?.taskID) { _ in
            isSwitcherPresented = false
            switchSearch = ""
        }
    }

    private func activeHUD(_ active: ActiveFocus) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let elapsed = focus.elapsed(at: context.date)
            VStack(spacing: 0) {
                HStack(spacing: 11) {
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
                            Text(experience.roundMessage ?? (active.isPaused
                                ? language.text("专注已暂停", "FOCUS PAUSED")
                                : language.text("专注进行中", "FOCUS ACTIVE")))
                                .font(.system(size: 7, weight: .black))
                                .tracking(0.9)
                                .foregroundStyle(experience.roundMessage == nil
                                    ? (active.isPaused ? DeckTheme.lime : DeckTheme.cyan)
                                    : DeckTheme.warning)
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

                    Button {
                        switchSearch = ""
                        isSwitcherPresented.toggle()
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
                    .buttonStyle(.plain)
                    .popover(isPresented: $isSwitcherPresented, arrowEdge: .bottom) {
                        FocusTaskSwitcherPopover(
                            isPresented: $isSwitcherPresented,
                            searchText: $switchSearch
                        )
                    }
                    .help(language.text("切换专注任务（⌘⌥K）", "Switch focus task (⌘⌥K)"))
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

                    FocusFinishButton(variant: .hud)
                }
                .padding(.horizontal, 14)
                .frame(height: 74)

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
            .focusHUDShell(stroke: active.isPaused ? DeckTheme.lime : DeckTheme.cyan)
        }
    }

    private func idleReviewHUD(_ review: IdleFocusReview) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "moon.zzz.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(DeckTheme.warning)
                .frame(width: 38, height: 38)
                .background(DeckTheme.warning.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 3) {
                Text(language.text("检测到闲置时间", "IDLE TIME DETECTED"))
                    .font(.system(size: 8, weight: .black))
                    .tracking(0.8)
                    .foregroundStyle(DeckTheme.warning)
                Text(language.format(
                    "刚才的 %d 分钟是否计入专注时间？计时已暂停。",
                    "Count the last %d minutes as focus time? The timer is paused.",
                    max(1, review.durationSeconds / 60)
                ))
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(DeckTheme.text)
                .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(language.text("排除并继续", "Exclude & Resume")) {
                experience.resolveIdleReview(include: false)
            }
            .idleChoiceButton(accented: false)

            Button(language.text("计入并继续", "Count & Resume")) {
                experience.resolveIdleReview(include: true)
            }
            .idleChoiceButton(accented: true)
        }
        .padding(.horizontal, 14)
        .frame(height: 78)
        .focusHUDShell(stroke: DeckTheme.warning)
    }

    private func breakHUD(_ currentBreak: PomodoroBreak) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = currentBreak.remainingSeconds(at: context.date)
            let total = max(60, Int(currentBreak.endsAt.timeIntervalSince(currentBreak.startedAt)))
            HStack(spacing: 12) {
                Image(systemName: remaining > 0 ? "cup.and.saucer.fill" : "bell.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(DeckTheme.violet)
                    .frame(width: 38, height: 38)
                    .background(DeckTheme.violet.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 3) {
                    Text(remaining > 0
                        ? language.text("自动休息进行中", "POMODORO BREAK")
                        : language.text("休息结束", "BREAK COMPLETE"))
                        .font(.system(size: 8, weight: .black))
                        .tracking(0.9)
                        .foregroundStyle(DeckTheme.violet)
                    Text(currentBreak.taskTitle)
                        .font(.system(size: 10, weight: .bold))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(formatDuration(remaining))
                    .font(.system(size: 18, weight: .black))
                    .monospacedDigit()

                Button(remaining > 0
                    ? language.text("结束休息", "End Break")
                    : language.text("继续专注", "Resume Focus")) {
                    experience.finishBreakAndResume()
                }
                .buttonStyle(.plain)
                .font(.system(size: 8, weight: .black))
                .foregroundStyle(DeckTheme.void)
                .padding(.horizontal, 12)
                .frame(height: 34)
                .background(DeckTheme.violet)
                .clipShape(RoundedRectangle(cornerRadius: 9))
            }
            .padding(.horizontal, 14)
            .frame(height: 78)
            .overlay(alignment: .bottomLeading) {
                GeometryReader { geometry in
                    Rectangle()
                        .fill(DeckTheme.violet)
                        .frame(width: geometry.size.width * (1 - Double(remaining) / Double(total)), height: 2)
                }
                .frame(height: 2)
            }
            .focusHUDShell(stroke: DeckTheme.violet)
        }
    }

    private func displayDirection(_ direction: String) -> String {
        direction == "未分类" ? language.text("未分类", "Uncategorized") : direction
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

private struct FocusTaskSwitcherPopover: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var focus: FocusStore
    @EnvironmentObject private var experience: FocusExperienceController
    @EnvironmentObject private var language: LanguageStore
    @Binding var isPresented: Bool
    @Binding var searchText: String
    @FocusState private var searchIsFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("FOCUS // TASK SWITCHER")
                        .font(.system(size: 8, weight: .black))
                        .tracking(1.1)
                        .foregroundStyle(DeckTheme.cyan)
                    Text(language.text("切换专注任务", "Switch Focus Task"))
                        .font(.system(size: 14, weight: .black))
                }
                Spacer()
                Button { isPresented = false } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .black))
                        .frame(width: 26, height: 26)
                        .background(DeckTheme.panelRaised)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(DeckTheme.cyan)
                TextField(language.text("搜索任务或方向", "Search task or direction"), text: $searchText)
                    .textFieldStyle(.plain)
                    .focused($searchIsFocused)
                    .font(.system(size: 9, weight: .medium))
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(DeckTheme.muted)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(DeckTheme.panelRaised)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(DeckTheme.border))

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 11) {
                    if candidates.isEmpty {
                        Text(language.text("没有可切换的待办任务", "No pending task to switch to"))
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(DeckTheme.muted)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 32)
                    } else {
                        if !recentTasks.isEmpty {
                            taskSection(
                                title: language.text("最近切换", "RECENT"),
                                tasks: recentTasks,
                                showsRecentShortcut: true
                            )
                        }
                        ForEach(directionGroups) { group in
                            taskSection(title: displayDirection(group.direction).uppercased(), tasks: group.tasks)
                        }
                    }
                }
            }
            .frame(height: 300)
            .scrollIndicators(.never)

            HStack {
                Text(language.text("选择任务会先保存当前专注时间片", "Selecting a task saves the current focus segment first"))
                Spacer()
                Text("⌘⌥K · " + language.text("打开", "OPEN") + "   ⌘⌥J · " + language.text("最近", "RECENT"))
            }
            .font(.system(size: 6.5, weight: .bold))
            .foregroundStyle(DeckTheme.muted)
        }
        .padding(16)
        .frame(width: 430)
        .background(DeckTheme.void)
        .foregroundStyle(DeckTheme.text)
        .fontDesign(.monospaced)
        .onAppear { searchIsFocused = true }
    }

    private var candidates: [TaskItem] {
        guard let activeTaskID = focus.active?.taskID else { return [] }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return store.pendingTasks.filter { task in
            guard task.id != activeTaskID else { return false }
            return query.isEmpty
                || task.title.localizedCaseInsensitiveContains(query)
                || task.direction.localizedCaseInsensitiveContains(query)
        }
    }

    private var recentTasks: [TaskItem] {
        guard searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        return experience.recentTaskIDs
            .compactMap { id in candidates.first { $0.id == id } }
            .prefix(3)
            .map { $0 }
    }

    private var directionGroups: [TaskDirectionGroup] {
        let recentIDs = Set(recentTasks.map(\.id))
        return Dictionary(grouping: candidates.filter { !recentIDs.contains($0.id) }, by: \.normalizedDirection)
            .map { TaskDirectionGroup(direction: $0.key, tasks: $0.value) }
            .sorted { $0.direction.localizedCaseInsensitiveCompare($1.direction) == .orderedAscending }
    }

    private func taskSection(
        title: String,
        tasks: [TaskItem],
        showsRecentShortcut: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("// \(title)")
                .font(.system(size: 7, weight: .black))
                .tracking(0.8)
                .foregroundStyle(DeckTheme.cyan)
            ForEach(Array(tasks.enumerated()), id: \.element.id) { index, task in
                Button { switchTo(task) } label: {
                    HStack(spacing: 10) {
                        Image(systemName: task.priority.symbol)
                            .font(.system(size: 9, weight: .black))
                            .foregroundStyle(priorityColor(task.priority))
                            .frame(width: 24, height: 24)
                            .background(priorityColor(task.priority).opacity(0.09))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(task.title)
                                .font(.system(size: 9, weight: .bold))
                                .lineLimit(1)
                            Text("\(task.priority.title(in: language.current).uppercased()) · \(task.estimatedMinutes) MIN")
                                .font(.system(size: 6.5, weight: .bold))
                                .foregroundStyle(DeckTheme.muted)
                        }
                        Spacer()
                        if showsRecentShortcut && index == 0 {
                            Text("⌘⌥J")
                                .font(.system(size: 6.5, weight: .black))
                                .foregroundStyle(DeckTheme.muted)
                        }
                        Image(systemName: "arrow.right")
                            .font(.system(size: 7, weight: .black))
                            .foregroundStyle(DeckTheme.cyan)
                    }
                    .padding(.horizontal, 9)
                    .frame(height: 40)
                    .background(DeckTheme.panel)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(DeckTheme.border))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(language.format(
                    "切换到 %@，预计 %d 分钟，%@优先级",
                    "Switch to %@, estimated %d minutes, %@ priority",
                    task.title,
                    task.estimatedMinutes,
                    task.priority.title(in: language.current)
                ))
            }
        }
    }

    private func switchTo(_ task: TaskItem) {
        guard focus.switchTo(task) else { return }
        experience.recordRecentTask(task.id)
        searchText = ""
        isPresented = false
    }

    private func displayDirection(_ direction: String) -> String {
        direction == "未分类" ? language.text("未分类", "Uncategorized") : direction
    }

    private func priorityColor(_ priority: TaskPriority) -> Color {
        switch priority {
        case .normal: return DeckTheme.cyan
        case .important: return DeckTheme.warning
        case .urgent: return DeckTheme.lime
        }
    }
}

private struct TaskDirectionGroup: Identifiable {
    let direction: String
    let tasks: [TaskItem]
    var id: String { direction }
}

private extension View {
    func focusHUDShell(stroke: Color) -> some View {
        self
            .background(DeckTheme.void.opacity(0.97))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(stroke.opacity(0.28), lineWidth: 1)
            )
            .padding(2)
    }

    func idleChoiceButton(accented: Bool) -> some View {
        self
            .buttonStyle(.plain)
            .font(.system(size: 8, weight: .black))
            .foregroundStyle(accented ? DeckTheme.void : DeckTheme.text)
            .padding(.horizontal, 11)
            .frame(height: 34)
            .background(accented ? DeckTheme.warning : DeckTheme.panelRaised)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                if !accented { RoundedRectangle(cornerRadius: 8).stroke(DeckTheme.border) }
            }
    }
}
