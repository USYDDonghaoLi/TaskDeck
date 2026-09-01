import AppKit
import SwiftUI

struct DesktopWidgetView: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var notifications: NotificationManager
    @EnvironmentObject private var focus: FocusStore
    @EnvironmentObject private var language: LanguageStore
    @State private var showingComposer = false
    @State private var editingTask: TaskItem?

    var body: some View {
        ZStack {
            DeckTheme.void.ignoresSafeArea()
            GridBackground().ignoresSafeArea()

            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Circle()
                        .fill(DeckTheme.cyan)
                        .frame(width: 8, height: 8)
                        .shadow(color: DeckTheme.cyan, radius: 5)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("TASKDECK // DESKTOP")
                            .font(.system(size: 10, weight: .black))
                            .tracking(1.0)
                        Text(Date.now.formatted(.dateTime.weekday(.wide).month().day().locale(language.current.locale)))
                            .font(.system(size: 8, weight: .medium))
                            .foregroundStyle(DeckTheme.muted)
                    }
                    Spacer()
                    Button {
                        editingTask = nil
                        showingComposer = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .black))
                            .foregroundStyle(DeckTheme.void)
                            .frame(width: 28, height: 28)
                            .background(DeckTheme.cyan)
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                    }
                    .buttonStyle(.plain)
                }
                .padding(17)

                Rectangle().fill(DeckTheme.border).frame(height: 1)

                if focus.active != nil {
                    DesktopFocusStrip()
                    Rectangle().fill(DeckTheme.border).frame(height: 1)
                }

                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(language.text("今日推进", "Today's Progress"))
                            .font(.system(size: 11, weight: .black))
                        Text("\(store.todayCompleted.count) DONE / \(store.todayPending.count) PENDING")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(DeckTheme.muted)
                            .tracking(0.6)
                    }
                    Spacer()
                    Text("\(Int(store.todayProgress * 100))%")
                        .font(.system(size: 20, weight: .black))
                        .foregroundStyle(DeckTheme.cyan)
                }
                .padding(.horizontal, 17)
                .padding(.vertical, 14)

                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(DeckTheme.panelRaised)
                        Capsule().fill(DeckTheme.cyan).frame(width: geometry.size.width * store.todayProgress)
                    }
                }
                .frame(height: 4)
                .padding(.horizontal, 17)

                ScrollView {
                    LazyVStack(spacing: 8) {
                        if store.todayPending.isEmpty {
                            VStack(spacing: 10) {
                                Image(systemName: "checkmark.seal.fill")
                                    .font(.system(size: 27, weight: .light))
                                    .foregroundStyle(DeckTheme.lime)
                                Text(language.text("队列已清空", "Queue Cleared"))
                                    .font(.system(size: 10, weight: .bold))
                                Text(language.text("享受片刻安静，或者注入新的任务。", "Enjoy the quiet, or inject a new task."))
                                    .font(.system(size: 8))
                                    .foregroundStyle(DeckTheme.muted)
                            }
                            .padding(.top, 55)
                        } else {
                            ForEach(store.todayPending) { task in
                                DesktopTaskRow(task: task) {
                                    editingTask = task
                                    showingComposer = true
                                }
                            }
                        }
                    }
                    .padding(17)
                }
                .scrollIndicators(.never)
            }
        }
        .foregroundStyle(DeckTheme.text)
        .fontDesign(.monospaced)
        .sheet(isPresented: $showingComposer, onDismiss: { editingTask = nil }) {
            TaskComposerView(editingTask: editingTask)
                .environmentObject(store)
                .environmentObject(notifications)
                .environmentObject(language)
        }
        .background(
            WindowAccessor { window in
                window.level = .floating
                window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
                window.titlebarAppearsTransparent = true
                window.isMovableByWindowBackground = true
                window.minSize = NSSize(width: 330, height: 400)
                window.backgroundColor = .clear
            }
        )
    }
}

private struct DesktopTaskRow: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var notifications: NotificationManager
    @EnvironmentObject private var focus: FocusStore
    @EnvironmentObject private var language: LanguageStore
    let task: TaskItem
    let onEdit: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Button {
                notifications.cancel(for: task)
                if focus.active?.taskID == task.id { _ = focus.finish() }
                var generatedTask: TaskItem?
                withAnimation(.easeInOut(duration: 0.2)) { generatedTask = store.toggle(task) }
                if let generatedTask { notifications.schedule(for: generatedTask) }
            } label: {
                RoundedRectangle(cornerRadius: 5)
                    .stroke(DeckTheme.cyan.opacity(0.7), lineWidth: 1)
                    .frame(width: 23, height: 23)
                    .overlay {
                        Circle().fill(DeckTheme.cyan.opacity(0.16)).frame(width: 7, height: 7)
                    }
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 6) {
                Text(task.title)
                    .font(.system(size: 10, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 9) {
                    if task.priority != .normal {
                        Label(task.priority.title(in: language.current), systemImage: task.priority.symbol)
                            .foregroundStyle(task.priority == .urgent ? DeckTheme.warning : DeckTheme.violet)
                    }
                    Text(task.displayDirection(in: language.current).uppercased())
                    Label("\(task.estimatedMinutes)M", systemImage: "timer")
                    if let dueAt = task.dueAt {
                        Label(dueAt.formatted(date: .omitted, time: .shortened), systemImage: task.reminderEnabled ? "bell.fill" : "clock")
                    }
                }
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(DeckTheme.muted)
            }
            Spacer(minLength: 2)
            Button { _ = focus.beginOrToggle(task) } label: {
                Image(systemName: focus.active?.taskID == task.id && focus.active?.isPaused == false ? "pause.fill" : "play.fill")
                    .font(.system(size: 8, weight: .black))
                    .foregroundStyle(focus.active?.taskID == task.id ? DeckTheme.void : DeckTheme.cyan)
                    .frame(width: 22, height: 22)
                    .background(focus.active?.taskID == task.id ? DeckTheme.cyan : DeckTheme.cyan.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .disabled(focus.active != nil && focus.active?.taskID != task.id)
            Button(action: onEdit) {
                Image(systemName: "pencil")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(DeckTheme.muted)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(DeckTheme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(DeckTheme.border))
    }
}

private struct DesktopFocusStrip: View {
    @EnvironmentObject private var focus: FocusStore
    @EnvironmentObject private var language: LanguageStore

    var body: some View {
        if let active = focus.active {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                HStack(spacing: 10) {
                    Button { active.isPaused ? focus.resume() : focus.pause() } label: {
                        Image(systemName: active.isPaused ? "play.fill" : "pause.fill")
                            .font(.system(size: 8, weight: .black))
                            .foregroundStyle(DeckTheme.void)
                            .frame(width: 24, height: 24)
                            .background(DeckTheme.cyan)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(active.taskTitle)
                            .font(.system(size: 8, weight: .bold))
                            .lineLimit(1)
                        Text(active.isPaused
                            ? language.text("已暂停", "PAUSED")
                            : language.text("专注进行中", "FOCUS ACTIVE"))
                            .font(.system(size: 6, weight: .black))
                            .foregroundStyle(active.isPaused ? DeckTheme.lime : DeckTheme.cyan)
                            .tracking(0.7)
                    }
                    Spacer()
                    Text(format(Int(focus.elapsed(at: context.date))))
                        .font(.system(size: 13, weight: .black))
                        .monospacedDigit()
                    Button(language.text("结束", "Finish")) { _ = focus.finish() }
                        .buttonStyle(.plain)
                        .font(.system(size: 7, weight: .black))
                        .foregroundStyle(DeckTheme.muted)
                }
                .padding(.horizontal, 17)
                .frame(height: 46)
                .background(DeckTheme.cyan.opacity(0.035))
            }
        }
    }

    private func format(_ seconds: Int) -> String {
        String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}
