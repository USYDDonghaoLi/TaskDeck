import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var notifications: NotificationManager
    @EnvironmentObject private var focus: FocusStore
    @EnvironmentObject private var experience: FocusExperienceController
    @EnvironmentObject private var language: LanguageStore

    @State private var statusMessage = ""
    @State private var statusIsError = false
    @State private var backups: [DatabaseBackupInfo] = []

    var body: some View {
        ZStack {
            DeckTheme.void.ignoresSafeArea()
            GridBackground().ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    languagePanel
                    editingPanel
                    focusExperiencePanel
                    dataPanel
                    trashPanel
                    backupPanel

                    if !statusMessage.isEmpty {
                        Label(
                            statusMessage,
                            systemImage: statusIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
                        )
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(statusIsError ? DeckTheme.warning : DeckTheme.lime)
                        .padding(.horizontal, 13)
                        .frame(minHeight: 36)
                        .background(DeckTheme.panelRaised)
                        .clipShape(RoundedRectangle(cornerRadius: 9))
                    }
                }
                .padding(26)
            }
            .scrollIndicators(.never)
        }
        .frame(width: 700, height: 700)
        .foregroundStyle(DeckTheme.text)
        .fontDesign(.monospaced)
        .onAppear(perform: refreshBackups)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("TASKDECK // CONFIG")
                .font(.system(size: 9, weight: .black))
                .tracking(1.6)
                .foregroundStyle(DeckTheme.cyan)
            Text(language.text("设置", "Settings"))
                .font(.system(size: 23, weight: .black))
            Text(language.text(
                "语言、专注体验、编辑方式与本地数据管理",
                "Language, focus experience, editing, and local data management"
            ))
            .font(.system(size: 10))
            .foregroundStyle(DeckTheme.muted)
        }
    }

    private var languagePanel: some View {
        settingsPanel(
            index: "01",
            title: language.text("界面语言", "Interface Language"),
            subtitle: language.text("修改后主窗口、悬浮窗口和 Widget 同步更新。", "The app, desktop board, and Widget update together.")
        ) {
            LanguageSelector(selection: $language.current)
                .frame(width: 280)
                .accessibilityLabel(language.text("界面语言", "Interface language"))
        }
    }

    private var editingPanel: some View {
        settingsPanel(
            index: "02",
            title: language.text("任务编辑", "Task Editing"),
            subtitle: language.text(
                "点击任务卡片右侧的铅笔，可修改名称、预计时长与优先级；任务 ID 和历史记录保持不变。",
                "Use the pencil on a task card to change its name, estimate, and priority without changing its ID or history."
            )
        ) {
            HStack(spacing: 8) {
                editBadge("pencil", language.text("名称", "NAME"))
                editBadge("timer", language.text("时长", "DURATION"))
                editBadge("bolt.fill", language.text("优先级", "PRIORITY"))
            }
        }
    }

    private var dataPanel: some View {
        settingsPanel(
            index: "04",
            title: language.text("数据与备份", "Data & Backups"),
            subtitle: language.text(
                "任务、专注记录和 Widget 共用 SQLite。每次修改前保留备份，最多保存最近 30 份。",
                "Tasks, focus history, and the Widget share SQLite. A backup is made before every change; the latest 30 are retained."
            )
        ) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 14) {
                    dataMetric(value: "\(store.activeTasks.count)", label: language.text("任务", "TASKS"))
                    dataMetric(value: "\(focus.sessions.count)", label: language.text("专注记录", "FOCUS"))
                    dataMetric(value: "\(store.trashedTasks.count)", label: language.text("回收站", "TRASH"))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(language.text("数据库位置", "DATABASE LOCATION"))
                        .font(.system(size: 7, weight: .black))
                        .tracking(0.8)
                        .foregroundStyle(DeckTheme.muted)
                    Text(store.databaseURL.path)
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(DeckTheme.cyan)
                        .textSelection(.enabled)
                        .lineLimit(2)
                }

                HStack(spacing: 10) {
                    Button(action: exportJSON) {
                        Label(language.text("导出 JSON", "Export JSON"), systemImage: "square.and.arrow.up")
                            .settingsAction(accented: true)
                    }
                    .buttonStyle(.plain)

                    Button(action: importJSON) {
                        Label(language.text("导入 JSON", "Import JSON"), systemImage: "square.and.arrow.down")
                            .settingsAction()
                    }
                    .buttonStyle(.plain)

                    Button {
                        NSWorkspace.shared.open(store.databaseURL.deletingLastPathComponent())
                    } label: {
                        Label(language.text("打开数据目录", "Open Data Folder"), systemImage: "folder")
                            .settingsAction()
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var trashPanel: some View {
        settingsPanel(
            index: "05",
            title: language.text("回收站", "Trash"),
            subtitle: language.text(
                "删除的任务会保留在这里；恢复不会改变任务 ID、完成记录或专注历史。永久删除仍会先创建数据库备份。",
                "Deleted tasks stay here. Restoring preserves IDs, completion records, and focus history. Permanent deletion still creates a database backup first."
            )
        ) {
            VStack(alignment: .leading, spacing: 9) {
                if store.trashedTasks.isEmpty {
                    Label(language.text("回收站为空", "Trash is empty"), systemImage: "trash")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(DeckTheme.muted)
                } else {
                    ForEach(store.trashedTasks.prefix(8)) { task in
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(task.title)
                                    .font(.system(size: 9, weight: .bold))
                                    .lineLimit(1)
                                Text(task.deletedAt?.formatted(date: .abbreviated, time: .shortened) ?? "—")
                                    .font(.system(size: 7))
                                    .foregroundStyle(DeckTheme.muted)
                            }
                            Spacer()
                            Button(language.text("恢复", "Restore")) { restoreTask(task) }
                                .buttonStyle(.plain)
                                .foregroundStyle(DeckTheme.cyan)
                                .font(.system(size: 8, weight: .black))
                            Button(language.text("永久删除", "Delete Forever")) { confirmPermanentDelete(task) }
                                .buttonStyle(.plain)
                                .foregroundStyle(DeckTheme.warning)
                                .font(.system(size: 8, weight: .bold))
                        }
                        .padding(.vertical, 4)
                    }
                    if store.trashedTasks.count > 8 {
                        Text(language.format("另有 %d 个任务未显示", "%d more tasks are not shown", store.trashedTasks.count - 8))
                            .font(.system(size: 7))
                            .foregroundStyle(DeckTheme.muted)
                    }
                    Button(action: confirmEmptyTrash) {
                        Label(language.text("清空回收站", "Empty Trash"), systemImage: "trash.slash")
                            .settingsAction()
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var backupPanel: some View {
        settingsPanel(
            index: "06",
            title: language.text("数据库备份", "Database Backups"),
            subtitle: language.text(
                "只显示 TaskDeck 自动生成的 SQLite 备份。恢复前会校验完整性，并额外保存当前数据库。",
                "Only TaskDeck's automatic SQLite backups are shown. Integrity is checked and the current database is backed up again before restoration."
            )
        ) {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 10) {
                    Button(action: refreshBackups) {
                        Label(language.text("刷新列表", "Refresh"), systemImage: "arrow.clockwise")
                            .settingsAction(accented: true)
                    }
                    .buttonStyle(.plain)
                    Button {
                        NSWorkspace.shared.open(store.databaseURL.deletingLastPathComponent().appendingPathComponent("Backups/Database"))
                    } label: {
                        Label(language.text("打开备份目录", "Open Backup Folder"), systemImage: "folder")
                            .settingsAction()
                    }
                    .buttonStyle(.plain)
                }

                if backups.isEmpty {
                    Text(language.text("还没有自动备份；首次修改数据后会出现在这里。", "No automatic backup yet. One appears after the first data change."))
                        .font(.system(size: 8))
                        .foregroundStyle(DeckTheme.muted)
                } else {
                    ForEach(backups.prefix(10)) { backup in
                        HStack(spacing: 10) {
                            Image(systemName: backup.isValid ? "externaldrive.fill.badge.checkmark" : "externaldrive.badge.xmark")
                                .foregroundStyle(backup.isValid ? DeckTheme.lime : DeckTheme.warning)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(backup.createdAt.formatted(date: .abbreviated, time: .standard))
                                    .font(.system(size: 8, weight: .bold))
                                Text(backupDescription(backup))
                                    .font(.system(size: 7))
                                    .foregroundStyle(DeckTheme.muted)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Button(language.text("恢复", "Restore")) { confirmRestore(backup) }
                                .buttonStyle(.plain)
                                .font(.system(size: 8, weight: .black))
                                .foregroundStyle(DeckTheme.cyan)
                                .disabled(!backup.isValid)
                        }
                        .padding(.vertical, 3)
                    }
                }
            }
        }
    }

    private var focusExperiencePanel: some View {
        settingsPanel(
            index: "03",
            title: language.text("专注体验", "Focus Experience"),
            subtitle: language.text(
                "设置番茄钟、自动休息与闲置检测；这些偏好不会修改已有专注记录。",
                "Configure Pomodoro rounds, automatic breaks, and idle detection without changing existing focus history."
            )
        ) {
            VStack(alignment: .leading, spacing: 13) {
                Toggle(language.text("启用番茄钟与完成提醒", "Enable Pomodoro rounds and alerts"), isOn: $experience.pomodoroEnabled)
                    .toggleStyle(.switch)
                    .font(.system(size: 9, weight: .bold))

                HStack(spacing: 18) {
                    focusDurationField(
                        title: language.text("专注时长", "Focus Length"),
                        value: $experience.focusMinutes,
                        range: 1...180
                    )
                    focusDurationField(
                        title: language.text("休息时长", "Break Length"),
                        value: $experience.breakMinutes,
                        range: 1...60
                    )
                }
                .disabled(!experience.pomodoroEnabled)
                .opacity(experience.pomodoroEnabled ? 1 : 0.5)

                Toggle(language.text("完成一轮后自动暂停并开始休息", "Automatically pause and start a break after each round"), isOn: $experience.autoStartBreak)
                    .toggleStyle(.switch)
                    .font(.system(size: 9, weight: .bold))
                    .disabled(!experience.pomodoroEnabled)

                Rectangle().fill(DeckTheme.border).frame(height: 1)

                Toggle(language.text("启用闲置检测", "Enable idle detection"), isOn: $experience.idleDetectionEnabled)
                    .toggleStyle(.switch)
                    .font(.system(size: 9, weight: .bold))

                focusDurationField(
                    title: language.text("连续闲置多久后询问", "Ask after this much idle time"),
                    value: $experience.idleThresholdMinutes,
                    range: 1...120
                )
                .disabled(!experience.idleDetectionEnabled)
                .opacity(experience.idleDetectionEnabled ? 1 : 0.5)

                if notifications.authorizationStatus == .denied {
                    Label(
                        language.text(
                            "系统通知权限已关闭；应用内提醒仍然有效。",
                            "System notifications are disabled; in-app alerts still work."
                        ),
                        systemImage: "bell.slash"
                    )
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(DeckTheme.warning)
                } else if notifications.authorizationStatus == .notDetermined {
                    Button {
                        notifications.requestAuthorization()
                    } label: {
                        Label(language.text("允许专注提醒", "Allow Focus Notifications"), systemImage: "bell.badge")
                            .settingsAction()
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func focusDurationField(
        title: String,
        value: Binding<Int>,
        range: ClosedRange<Int>
    ) -> some View {
        HStack(spacing: 9) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title.uppercased())
                    .font(.system(size: 7, weight: .black))
                    .foregroundStyle(DeckTheme.muted)
                HStack(spacing: 5) {
                    TextField("", value: value, format: .number)
                        .textFieldStyle(.plain)
                        .multilineTextAlignment(.trailing)
                        .font(.system(size: 10, weight: .black))
                        .frame(width: 44, height: 26)
                        .padding(.horizontal, 6)
                        .background(DeckTheme.panelRaised)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(DeckTheme.border))
                    Text(language.text("分钟", "MIN"))
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(DeckTheme.muted)
                }
            }
            Stepper("", value: value, in: range)
                .labelsHidden()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func settingsPanel<Content: View>(
        index: String,
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .top, spacing: 11) {
                Text(index)
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(DeckTheme.cyan)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title.uppercased())
                        .font(.system(size: 11, weight: .black))
                        .tracking(0.8)
                    Text(subtitle)
                        .font(.system(size: 9))
                        .foregroundStyle(DeckTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            content()
        }
        .padding(16)
        .background(DeckTheme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(DeckTheme.border))
    }

    private func editBadge(_ symbol: String, _ label: String) -> some View {
        Label(label, systemImage: symbol)
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(DeckTheme.cyan)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(DeckTheme.cyan.opacity(0.08))
            .clipShape(Capsule())
    }

    private func dataMetric(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 15, weight: .black))
            Text(label)
                .font(.system(size: 7, weight: .bold))
                .tracking(0.7)
                .foregroundStyle(DeckTheme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func exportJSON() {
        do {
            let data = try store.exportArchive(focusStore: focus)
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.json]
            panel.canCreateDirectories = true
            panel.nameFieldStringValue = "TaskDeck-backup-\(Self.fileDateFormatter.string(from: Date())).json"
            panel.title = language.text("导出 TaskDeck 数据", "Export TaskDeck Data")
            guard panel.runModal() == .OK, let url = panel.url else { return }
            try data.write(to: url, options: .atomic)
            showStatus(language.text("JSON 导出完成。", "JSON export completed."), isError: false)
        } catch {
            showStatus(language.text("导出失败：", "Export failed: ") + error.localizedDescription, isError: true)
        }
    }

    private func importJSON() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = language.text("选择 TaskDeck JSON", "Choose a TaskDeck JSON File")
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let data = try Data(contentsOf: url)
            _ = try TaskDeckArchiveCodec.decode(data)
            guard confirmImport() else { return }
            try store.importArchive(data, focusStore: focus)
            refreshBackups()
            showStatus(
                language.format("导入完成：%d 个任务。修改前数据库已备份。", "Import complete: %d tasks. The previous database was backed up.", store.activeTasks.count),
                isError: false
            )
        } catch {
            showStatus(language.text("导入失败：", "Import failed: ") + error.localizedDescription, isError: true)
        }
    }

    private func confirmImport() -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = language.text("确认导入？", "Import this file?")
        alert.informativeText = language.text(
            "导入会替换相应数据。TaskDeck 会先自动备份当前数据库，旧 JSON 文件也不会被删除。",
            "Imported content replaces the corresponding data. TaskDeck backs up the current database first and never deletes legacy JSON files."
        )
        alert.addButton(withTitle: language.text("导入", "Import"))
        alert.addButton(withTitle: language.text("取消", "Cancel"))
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func restoreTask(_ task: TaskItem) {
        guard let restored = store.restore(task) else { return }
        notifications.schedule(for: restored)
        refreshBackups()
        showStatus(language.text("任务已恢复。", "Task restored."), isError: false)
    }

    private func confirmPermanentDelete(_ task: TaskItem) {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = language.text("永久删除这个任务？", "Delete this task forever?")
        alert.informativeText = language.text(
            "任务会从当前数据库移除，但操作前生成的自动备份仍可用于恢复。",
            "The task is removed from the current database, but the automatic pre-change backup remains available."
        )
        alert.addButton(withTitle: language.text("永久删除", "Delete Forever"))
        alert.addButton(withTitle: language.text("取消", "Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        store.permanentlyDelete(task)
        refreshBackups()
        showStatus(language.text("任务已永久删除；安全备份已保留。", "Task deleted permanently; the safety backup was retained."), isError: false)
    }

    private func confirmEmptyTrash() {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = language.text("清空回收站？", "Empty Trash?")
        alert.informativeText = language.format(
            "将从当前数据库永久删除 %d 个任务。TaskDeck 会先生成自动备份。",
            "%d tasks will be removed from the current database. TaskDeck creates an automatic backup first.",
            store.trashedTasks.count
        )
        alert.addButton(withTitle: language.text("清空", "Empty Trash"))
        alert.addButton(withTitle: language.text("取消", "Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        store.emptyTrash()
        refreshBackups()
        showStatus(language.text("回收站已清空；安全备份已保留。", "Trash emptied; the safety backup was retained."), isError: false)
    }

    private func refreshBackups() {
        do {
            backups = try store.listBackups()
        } catch {
            backups = []
            showStatus(language.text("备份列表读取失败：", "Could not read backups: ") + error.localizedDescription, isError: true)
        }
    }

    private func confirmRestore(_ backup: DatabaseBackupInfo) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = language.text("恢复这个数据库备份？", "Restore this database backup?")
        alert.informativeText = language.text(
            "当前任务、回收站和专注状态将替换为备份中的内容。恢复前会再次保存当前数据库。",
            "Current tasks, Trash, and focus state will be replaced by the backup. The current database is saved again before restoration."
        )
        alert.addButton(withTitle: language.text("恢复备份", "Restore Backup"))
        alert.addButton(withTitle: language.text("取消", "Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let previousTasks = store.activeTasks
        do {
            try store.restoreBackup(backup, focusStore: focus)
            previousTasks.forEach(notifications.cancel)
            store.activeTasks.forEach(notifications.schedule)
            refreshBackups()
            showStatus(language.text("数据库恢复完成；恢复前状态也已备份。", "Database restored; the pre-restore state was also backed up."), isError: false)
        } catch {
            showStatus(language.text("恢复失败：", "Restore failed: ") + error.localizedDescription, isError: true)
        }
    }

    private func backupDescription(_ backup: DatabaseBackupInfo) -> String {
        if let error = backup.validationError {
            return language.text("备份无效：", "Invalid backup: ") + error
        }
        let size = ByteCountFormatter.string(fromByteCount: backup.size, countStyle: .file)
        return language.format(
            "%d 个任务 · %d 条专注 · %@",
            "%d tasks · %d focus sessions · %@",
            backup.taskCount ?? 0,
            backup.focusSessionCount ?? 0,
            size
        )
    }

    private func showStatus(_ message: String, isError: Bool) {
        statusMessage = message
        statusIsError = isError
    }

    private static let fileDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

private extension View {
    func settingsAction(accented: Bool = false) -> some View {
        self
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(accented ? DeckTheme.void : DeckTheme.text)
            .padding(.horizontal, 11)
            .frame(height: 32)
            .background(accented ? DeckTheme.cyan : DeckTheme.panelRaised)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                if !accented {
                    RoundedRectangle(cornerRadius: 8).stroke(DeckTheme.border)
                }
            }
    }
}
