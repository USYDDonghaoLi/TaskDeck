import AppKit
import SwiftUI

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

                    Rectangle()
                        .fill(DeckTheme.border)
                        .frame(height: 1)

                    FocusConsoleView()

                    HStack(spacing: 0) {
                        TaskBoardView(
                            filter: filter,
                            direction: selectedDirection,
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
            if let error = store.persistenceError {
                Label(localizedPersistenceError(error), systemImage: "externaldrive.badge.exclamationmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(DeckTheme.warning)
                    .padding(.horizontal, 14)
                    .frame(height: 34)
                    .background(DeckTheme.panelRaised)
                    .clipShape(Capsule())
                    .padding(.bottom, 12)
            }
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
            let task = store.tasks.first(where: { $0.id == id })
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
            return "Task data could not be loaded. The original file was preserved and will not be overwritten."
        }
        if error.contains("保存失败") {
            return "Task data could not be saved. Keep the app open and check disk permissions."
        }
        return error
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

            Menu {
                ForEach(AppLanguage.allCases) { item in
                    Button {
                        language.current = item
                    } label: {
                        if language.current == item {
                            Label(item.label, systemImage: "checkmark")
                        } else {
                            Text(item.label)
                        }
                    }
                }
            } label: {
                Label(language.current.shortLabel, systemImage: "globe")
                    .headerButton()
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help(language.text("切换界面语言", "Switch interface language"))

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
