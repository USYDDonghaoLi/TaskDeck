import SwiftUI

@main
struct TaskDeckApp: App {
    @StateObject private var store = TaskStore()
    @StateObject private var notifications = NotificationManager()
    @StateObject private var focus = FocusStore()
    @StateObject private var language = LanguageStore()

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

            HStack(spacing: 8) {
                Picker(language.text("预计时间", "Estimate"), selection: $estimatedMinutes) {
                    ForEach([15, 25, 45, 60, 90], id: \.self) { minutes in
                        Text("\(minutes)M").tag(minutes)
                    }
                }
                .labelsHidden()
                .accessibilityLabel(language.text("预计时间", "Estimate"))
                Picker(language.text("优先级", "Priority"), selection: $priority) {
                    ForEach(TaskPriority.allCases) { item in
                        Text(item.title(in: language.current)).tag(item)
                    }
                }
                .labelsHidden()
                .accessibilityLabel(language.text("优先级", "Priority"))
            }

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
