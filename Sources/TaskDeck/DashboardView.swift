import AppKit
import SwiftUI

extension Notification.Name {
    static let taskDeckNewTask = Notification.Name("TaskDeck.command.newTask")
    static let taskDeckFocusSearch = Notification.Name("TaskDeck.command.focusSearch")
    static let taskDeckClearFilters = Notification.Name("TaskDeck.command.clearFilters")
    static let taskDeckOpenDesktop = Notification.Name("TaskDeck.command.openDesktop")
}

struct DashboardView: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var notifications: NotificationManager
    @EnvironmentObject private var language: LanguageStore
    @Environment(\.openWindow) private var openWindow

    @State private var filter: TaskFilter = .today
    @State private var selectedDirection: String?
    @State private var reportPeriod: ReportPeriod = .day
    @State private var showingComposer = false
    @State private var editingTask: TaskItem?
    @State private var highlightedTaskID: UUID?
    @State private var searchText = ""
    @State private var priorityFilter: TaskPriorityFilter = .all
    @State private var dateFilter: TaskDateFilter = .all
    @FocusState private var searchFocused: Bool

    var body: some View {
        ZStack {
            DeckTheme.void.ignoresSafeArea()
            GridBackground().ignoresSafeArea()

            HStack(spacing: 0) {
                SidebarView(
                    filter: $filter,
                    selectedDirection: $selectedDirection,
                    onAdd: presentNewTask
                )
                .frame(width: 224)

                Rectangle()
                    .fill(DeckTheme.border)
                    .frame(width: 1)

                VStack(spacing: 0) {
                    CommandHeader(
                        filter: filter,
                        selectedDirection: selectedDirection,
                        onAdd: presentNewTask,
                        showDesktop: { openWindow(id: "desktop") }
                    )

                    SearchFilterBar(
                        searchText: $searchText,
                        priorityFilter: $priorityFilter,
                        dateFilter: $dateFilter,
                        searchFocus: $searchFocused
                    )

                    Rectangle()
                        .fill(DeckTheme.border)
                        .frame(height: 1)

                    FocusConsoleView()

                    HStack(spacing: 0) {
                        TaskBoardView(
                            filter: filter,
                            direction: selectedDirection,
                            searchText: searchText,
                            priorityFilter: priorityFilter,
                            dateFilter: dateFilter,
                            highlightedTaskID: highlightedTaskID,
                            onEdit: presentEditor
                        )
                            .frame(minWidth: 470, maxWidth: .infinity, maxHeight: .infinity)

                        Rectangle()
                            .fill(DeckTheme.border)
                            .frame(width: 1)

                        ReportPanel(period: $reportPeriod)
                            .frame(width: 310)
                            .frame(maxHeight: .infinity)
                    }
                }
            }
        }
        .foregroundStyle(DeckTheme.text)
        .fontDesign(.monospaced)
        .overlay(alignment: .bottom) {
            VStack(spacing: 8) {
                if let deleted = store.lastDeletedTask {
                    HStack(spacing: 12) {
                        Label(
                            language.format("“%@”已移到回收站", "“%@” moved to Trash", deleted.title),
                            systemImage: "trash"
                        )
                        Button(language.text("撤销", "Undo")) {
                            if let restored = store.undoLastDelete() {
                                notifications.schedule(for: restored)
                            }
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(DeckTheme.cyan)
                        .fontWeight(.black)
                    }
                    .font(.system(size: 9, weight: .bold))
                    .padding(.horizontal, 14)
                    .frame(height: 34)
                    .background(DeckTheme.panelRaised)
                    .clipShape(Capsule())
                }
                if let error = store.persistenceError {
                    Label(localizedPersistenceError(error), systemImage: "externaldrive.badge.exclamationmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(DeckTheme.warning)
                        .padding(.horizontal, 14)
                        .frame(height: 34)
                        .background(DeckTheme.panelRaised)
                        .clipShape(Capsule())
                }
            }
            .padding(.bottom, 12)
        }
        .sheet(isPresented: $showingComposer, onDismiss: { editingTask = nil }) {
            TaskComposerView(editingTask: editingTask)
                .environmentObject(store)
                .environmentObject(notifications)
                .environmentObject(language)
        }
        .background(
            WindowAccessor { window in
                window.title = "TaskDeck"
                window.titlebarAppearsTransparent = true
                window.isMovableByWindowBackground = true
                window.minSize = NSSize(width: 1_020, height: 680)
            }
        )
        .onOpenURL(perform: openDeepLink)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            store.refreshFromDisk()
        }
        .onReceive(NotificationCenter.default.publisher(for: .taskDeckNewTask)) { _ in presentNewTask() }
        .onReceive(NotificationCenter.default.publisher(for: .taskDeckFocusSearch)) { _ in searchFocused = true }
        .onReceive(NotificationCenter.default.publisher(for: .taskDeckClearFilters)) { _ in
            searchText = ""
            priorityFilter = .all
            dateFilter = .all
            selectedDirection = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: .taskDeckOpenDesktop)) { _ in openWindow(id: "desktop") }
    }

    private func presentNewTask() {
        editingTask = nil
        showingComposer = true
    }

    private func presentEditor(_ task: TaskItem) {
        editingTask = task
        showingComposer = true
    }

    private func openDeepLink(_ url: URL) {
        guard url.scheme?.lowercased() == "taskdeck" else { return }

        if url.host?.lowercased() == "today" {
            filter = .today
            selectedDirection = nil
            highlightedTaskID = nil
            return
        }

        guard
            url.host?.lowercased() == "task",
            let idText = url.pathComponents.dropFirst().first,
            let id = UUID(uuidString: idText),
            let task = store.activeTasks.first(where: { $0.id == id })
        else { return }

        filter = task.isCompleted ? .completed : .inbox
        selectedDirection = task.normalizedDirection
        highlightedTaskID = nil
        DispatchQueue.main.async {
            highlightedTaskID = id
        }
    }

    private func localizedPersistenceError(_ error: String) -> String {
        guard language.current == .english else { return error }
        if error.contains("读取失败") {
            return "The task database could not be loaded. The legacy JSON and database files were preserved."
        }
        if error.contains("保存失败") {
            return "The task database could not be saved. The pre-change backup is still available."
        }
        if error.contains("刷新失败") {
            return "The shared database could not be refreshed. Existing on-screen data was retained."
        }
        return error
    }
}

private struct SearchFilterBar: View {
    @EnvironmentObject private var language: LanguageStore
    @Binding var searchText: String
    @Binding var priorityFilter: TaskPriorityFilter
    @Binding var dateFilter: TaskDateFilter
    let searchFocus: FocusState<Bool>.Binding

    private var isFiltering: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || priorityFilter != .all
            || dateFilter != .all
    }

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(DeckTheme.cyan)
                TextField(language.text("全局搜索任务、方向、备注或子任务", "Search tasks, directions, notes, or subtasks"), text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 10, weight: .medium))
                    .focused(searchFocus)
                Text("⌘F")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(DeckTheme.muted)
            }
            .padding(.horizontal, 11)
            .frame(maxWidth: 410)
            .frame(height: 32)
            .background(DeckTheme.panelRaised)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(searchFocus.wrappedValue ? DeckTheme.cyan.opacity(0.7) : DeckTheme.border))

            Picker(language.text("优先级", "Priority"), selection: $priorityFilter) {
                ForEach(TaskPriorityFilter.allCases) { item in
                    Text(item.title(in: language.current)).tag(item)
                }
            }
            .labelsHidden()
            .frame(width: 140)

            Picker(language.text("日期", "Date"), selection: $dateFilter) {
                ForEach(TaskDateFilter.allCases) { item in
                    Text(item.title(in: language.current)).tag(item)
                }
            }
            .labelsHidden()
            .frame(width: 130)

            if isFiltering {
                Button {
                    searchText = ""
                    priorityFilter = .all
                    dateFilter = .all
                } label: {
                    Label(language.text("清除", "Clear"), systemImage: "xmark.circle.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(DeckTheme.muted)
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .frame(height: 48)
        .background(DeckTheme.void.opacity(0.72))
    }
}

private struct SidebarView: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var language: LanguageStore
    @Binding var filter: TaskFilter
    @Binding var selectedDirection: String?
    let onAdd: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(DeckTheme.cyan)
                        .frame(width: 34, height: 34)
                    Image(systemName: "command")
                        .font(.system(size: 17, weight: .black))
                        .foregroundStyle(DeckTheme.void)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text("TASKDECK")
                        .font(.system(size: 14, weight: .black))
                        .tracking(1.2)
                    Text("PERSONAL OPS")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(DeckTheme.muted)
                        .tracking(1.4)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 20)
            .padding(.bottom, 24)

            Button(action: onAdd) {
                HStack {
                    Image(systemName: "plus")
                    Text(language.text("新建精准任务", "New Precise Task"))
                    Spacer()
                    Text("⌘N")
                        .foregroundStyle(DeckTheme.void.opacity(0.6))
                }
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(DeckTheme.void)
                .padding(.horizontal, 13)
                .frame(height: 39)
                .background(DeckTheme.cyan)
                .clipShape(RoundedRectangle(cornerRadius: 9))
            }
            .buttonStyle(.plain)
            .keyboardShortcut("n", modifiers: .command)
            .padding(.horizontal, 14)
            .padding(.bottom, 20)

            Text(language.text("任务流", "Task Flow"))
                .sidebarLabel()

            VStack(spacing: 4) {
                ForEach(TaskFilter.allCases) { item in
                    SidebarRow(
                        title: item.title(in: language.current),
                        symbol: item.symbol,
                        count: count(for: item),
                        isSelected: filter == item && selectedDirection == nil
                    ) {
                        filter = item
                        selectedDirection = nil
                    }
                }
            }
            .padding(.horizontal, 10)

            Text(language.text("作战方向", "Directions"))
                .sidebarLabel()
                .padding(.top, 22)

            ScrollView {
                VStack(spacing: 4) {
                    ForEach(store.directions, id: \.self) { direction in
                        SidebarRow(
                            title: direction,
                            symbol: "arrow.up.right",
                            count: store.count(for: direction),
                            isSelected: selectedDirection == direction
                        ) {
                            filter = .inbox
                            selectedDirection = direction
                        }
                    }
                }
                .padding(.horizontal, 10)
            }

            Spacer(minLength: 16)

            HStack(spacing: 7) {
                Circle()
                    .fill(DeckTheme.lime)
                    .frame(width: 6, height: 6)
                    .shadow(color: DeckTheme.lime, radius: 5)
                Text("LOCAL DATA + BACKUP // ONLINE")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(DeckTheme.muted)
                    .tracking(0.6)
            }
            .padding(18)
        }
        .background(DeckTheme.panel.opacity(0.58))
    }

    private func count(for item: TaskFilter) -> Int {
        switch item {
        case .today: return store.tasks(for: .today).filter { !$0.isCompleted }.count
        case .inbox: return store.pendingTasks.count
        case .completed: return store.tasks(for: .completed).count
        }
    }
}

private struct SidebarRow: View {
    let title: String
    let symbol: String
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 18)
                    .foregroundStyle(isSelected ? DeckTheme.cyan : DeckTheme.muted)
                Text(title)
                    .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                    .lineLimit(1)
                Spacer()
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(isSelected ? DeckTheme.cyan : DeckTheme.muted)
                }
            }
            .foregroundStyle(isSelected ? DeckTheme.text : DeckTheme.muted)
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(isSelected ? DeckTheme.cyan.opacity(0.09) : .clear)
            .overlay(alignment: .leading) {
                if isSelected {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(DeckTheme.cyan)
                        .frame(width: 2, height: 18)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
    }
}

private struct CommandHeader: View {
    @EnvironmentObject private var language: LanguageStore
    let filter: TaskFilter
    let selectedDirection: String?
    let onAdd: () -> Void
    let showDesktop: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(selectedDirection ?? filter.title(in: language.current))
                    .font(.system(size: 18, weight: .black))
                Text(Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day().locale(language.current.locale)))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(DeckTheme.muted)
            }

            Spacer()

            settingsControl

            Button(action: showDesktop) {
                Label(language.text("桌面悬浮", "Desktop Board"), systemImage: "rectangle.on.rectangle")
                    .headerButton()
            }
            .buttonStyle(.plain)
            .help(language.text("打开一个可置顶的紧凑任务板", "Open the compact always-on-top task board"))

            Button(action: onAdd) {
                Label(language.text("添加任务", "Add Task"), systemImage: "plus")
                    .headerButton(accented: true)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .frame(height: 78)
        .background(DeckTheme.void.opacity(0.72))
    }

    @ViewBuilder
    private var settingsControl: some View {
        if #available(macOS 14.0, *) {
            SettingsLink {
                settingsLabel
            }
            .buttonStyle(.plain)
            .help(language.text("打开设置与数据管理", "Open settings and data management"))
        } else {
            Button {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            } label: {
                settingsLabel
            }
            .buttonStyle(.plain)
            .help(language.text("打开设置与数据管理", "Open settings and data management"))
        }
    }

    private var settingsLabel: some View {
        Label(
            "\(language.text("设置", "Settings")) · \(language.current.shortLabel)",
            systemImage: "gearshape"
        )
        .headerButton()
    }
}

private extension View {
    func sidebarLabel() -> some View {
        self
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(DeckTheme.muted)
            .textCase(.uppercase)
            .tracking(1.4)
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
    }

    func headerButton(accented: Bool = false) -> some View {
        self
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(accented ? DeckTheme.void : DeckTheme.text)
            .padding(.horizontal, 13)
            .frame(height: 34)
            .background(accented ? DeckTheme.cyan : DeckTheme.panelRaised)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                if !accented {
                    RoundedRectangle(cornerRadius: 8).stroke(DeckTheme.border)
                }
            }
    }
}

struct WindowAccessor: NSViewRepresentable {
    let configure: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window { configure(window) }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let window = nsView.window { configure(window) }
        }
    }
}
