import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var focus: FocusStore
    @EnvironmentObject private var language: LanguageStore

    @State private var statusMessage = ""
    @State private var statusIsError = false

    var body: some View {
        ZStack {
            DeckTheme.void.ignoresSafeArea()
            GridBackground().ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    languagePanel
                    editingPanel
                    dataPanel

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
        .frame(width: 620, height: 560)
        .foregroundStyle(DeckTheme.text)
        .fontDesign(.monospaced)
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
                "语言、编辑方式与本地数据管理",
                "Language, editing, and local data management"
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
            Picker(language.text("界面语言", "Interface Language"), selection: $language.current) {
                ForEach(AppLanguage.allCases) { item in
                    Text(item.label).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 280)
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
            index: "03",
            title: language.text("数据与备份", "Data & Backups"),
            subtitle: language.text(
                "任务、专注记录和 Widget 共用 SQLite。每次修改前保留备份，最多保存最近 30 份。",
                "Tasks, focus history, and the Widget share SQLite. A backup is made before every change; the latest 30 are retained."
            )
        ) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 14) {
                    dataMetric(value: "\(store.tasks.count)", label: language.text("任务", "TASKS"))
                    dataMetric(value: "\(focus.sessions.count)", label: language.text("专注记录", "FOCUS"))
                    dataMetric(value: "SQLite", label: language.text("存储引擎", "ENGINE"))
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
            showStatus(
                language.format("导入完成：%d 个任务。修改前数据库已备份。", "Import complete: %d tasks. The previous database was backed up.", store.tasks.count),
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
