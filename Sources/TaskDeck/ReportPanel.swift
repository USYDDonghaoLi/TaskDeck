import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ReportPanel: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var focus: FocusStore
    @EnvironmentObject private var language: LanguageStore
    @Binding var period: ReportPeriod
    @State private var copied = false
    @State private var pdfExported = false
    @State private var exportError: String?

    private var report: ReportSnapshot { store.report(for: period) }
    private var focusSessions: [FocusSession] { focus.sessions(in: report.interval) }
    private var focusSeconds: Int { focusSessions.reduce(0) { $0 + $1.durationSeconds } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Rectangle().fill(DeckTheme.border).frame(height: 1)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        MetricCard(value: "\(report.completedCount)", label: language.text("已完成", "DONE"), color: DeckTheme.lime)
                        MetricCard(value: durationText(seconds: focusSeconds), label: language.text("实际专注", "ACTUAL FOCUS"), color: DeckTheme.cyan)
                        MetricCard(
                            value: language.format("%d 天", "%d DAYS", store.completionStreak()),
                            label: language.text("连续完成", "STREAK"),
                            color: DeckTheme.warning
                        )
                        MetricCard(value: durationText(minutes: report.estimatedMinutes), label: language.text("预计投入", "ESTIMATE"), color: DeckTheme.violet)
                    }

                    ActivityHeatmap()
                    DirectionDistribution(tasks: report.completed)

                    if !focusSessions.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            sectionHeader(title: language.text("专注记录", "Focus Sessions"), count: focusSessions.count, suffix: language.text("次", "SESSIONS"))
                            ForEach(focusSessions.prefix(6)) { session in
                                FocusLogRow(session: session)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        sectionHeader(title: language.text("已完成记录", "Completed Tasks"), count: report.completedCount, suffix: language.text("项", "ITEMS"))

                        if report.completed.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "waveform.path.ecg")
                                    .font(.system(size: 18, weight: .light))
                                    .foregroundStyle(DeckTheme.cyan.opacity(0.7))
                                Text(language.text("此周期暂无完成记录", "No completed tasks in this period"))
                                    .font(.system(size: 9))
                                    .foregroundStyle(DeckTheme.muted)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                            .background(DeckTheme.panel.opacity(0.55))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        } else {
                            ForEach(report.completed.prefix(20)) { task in
                                CompletedLogRow(task: task, actualSeconds: focus.seconds(for: task.id, in: report.interval))
                            }
                        }
                    }
                }
                .padding(18)
            }
            .scrollIndicators(.never)
        }
        .background(DeckTheme.panel.opacity(0.42))
        .alert(language.text("PDF 导出失败", "PDF Export Failed"), isPresented: Binding(
            get: { exportError != nil },
            set: { if !$0 { exportError = nil } }
        )) {
            Button(language.text("知道了", "OK"), role: .cancel) { exportError = nil }
        } message: {
            Text(exportError ?? language.text("未知错误", "Unknown error"))
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("ACTIVITY LOG")
                        .font(.system(size: 8, weight: .black))
                        .foregroundStyle(DeckTheme.cyan)
                        .tracking(1.4)
                    Text(language.text("战绩报告", "Activity Report"))
                        .font(.system(size: 16, weight: .black))
                }
                Spacer()
                Button(action: exportPDF) {
                    Image(systemName: pdfExported ? "checkmark" : "arrow.down.doc")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(pdfExported ? DeckTheme.lime : DeckTheme.muted)
                        .frame(width: 30, height: 30)
                        .background(DeckTheme.panelRaised)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(language.text("导出 PDF 报告", "Export PDF report"))
                .help(language.text("导出排版 PDF 报告", "Export a formatted PDF report"))

                Button(action: copyReport) {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(copied ? DeckTheme.lime : DeckTheme.muted)
                        .frame(width: 30, height: 30)
                        .background(DeckTheme.panelRaised)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(language.text("复制 Markdown 报告", "Copy Markdown report"))
                .help(language.text("复制 Markdown 报告", "Copy Markdown report"))
            }

            HStack(spacing: 3) {
                ForEach(ReportPeriod.allCases) { item in
                    Button(item.title(in: language.current)) { period = item }
                        .buttonStyle(.plain)
                        .font(.system(size: 9, weight: .black))
                        .foregroundStyle(period == item ? DeckTheme.void : DeckTheme.muted)
                        .frame(maxWidth: .infinity)
                        .frame(height: 29)
                        .background(period == item ? DeckTheme.cyan : DeckTheme.panelRaised)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }

            Text(intervalText)
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(DeckTheme.muted)
        }
        .padding(20)
    }

    private func sectionHeader(title: String, count: Int, suffix: String) -> some View {
        HStack {
            Text(title).font(.system(size: 10, weight: .black))
            Spacer()
            Text("\(count) \(suffix)")
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(DeckTheme.muted)
        }
    }

    private var intervalText: String {
        let start = report.interval.start.formatted(.dateTime.year().month(.twoDigits).day(.twoDigits))
        let inclusiveEnd = report.interval.end.addingTimeInterval(-1)
        if period == .day { return start }
        let end = inclusiveEnd.formatted(.dateTime.year().month(.twoDigits).day(.twoDigits))
        return "\(start) — \(end)"
    }

    private func durationText(minutes: Int) -> String {
        durationText(seconds: minutes * 60)
    }

    private func durationText(seconds: Int) -> String {
        let minutes = seconds / 60
        if minutes >= 60 {
            let hours = Double(minutes) / 60
            return hours.formatted(.number.precision(.fractionLength(hours.rounded() == hours ? 0 : 1))) + "H"
        }
        return "\(minutes)M"
    }

    private func copyReport() {
        let formatter = DateFormatter()
        formatter.locale = language.current.locale
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        let lines = report.completed.map { task in
            let actual = focus.seconds(for: task.id, in: report.interval) / 60
            if language.current == .simplifiedChinese {
                return "- [x] [\(task.displayDirection(in: language.current))] \(task.title)（预计 \(task.estimatedMinutes) 分钟，实际专注 \(actual) 分钟，完成于 \(formatter.string(from: task.completedAt ?? Date()))）"
            }
            return "- [x] [\(task.displayDirection(in: language.current))] \(task.title) (estimated \(task.estimatedMinutes) min, focused \(actual) min, completed \(formatter.string(from: task.completedAt ?? Date())))"
        }
        let title = "# TaskDeck \(period.reportTitle(in: language.current)) | \(intervalText)"
        let summary = language.current == .simplifiedChinese
            ? "完成 \(report.completedCount) 项｜实际专注 \(durationText(seconds: focusSeconds))｜连续 \(store.completionStreak()) 天｜覆盖 \(report.directionCount) 个方向"
            : "\(report.completedCount) completed | \(durationText(seconds: focusSeconds)) focused | \(store.completionStreak())-day streak | \(report.directionCount) directions"
        let empty = language.text("本周期暂无完成记录。", "No completed tasks in this period.")
        let body = ([title, "", summary, ""] + (lines.isEmpty ? [empty] : lines)).joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(body, forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
    }

    private func exportPDF() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.canCreateDirectories = true
        let reportFileLabel = language.current == .simplifiedChinese ? "\(period.title(in: language.current))报告" : "\(period.title(in: language.current))-Report"
        panel.nameFieldStringValue = "TaskDeck-\(reportFileLabel)-\(Date.now.formatted(.dateTime.year().month(.twoDigits).day(.twoDigits))).pdf"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try PDFReportExporter.write(
                PDFReportPayload(
                    periodTitle: period.reportTitle(in: language.current),
                    interval: report.interval,
                    completedTasks: report.completed,
                    focusSessions: focusSessions,
                    streak: store.completionStreak(),
                    generatedAt: Date(),
                    language: language.current
                ),
                to: url
            )
            pdfExported = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { pdfExported = false }
        } catch {
            exportError = error.localizedDescription
        }
    }
}

private struct MetricCard: View {
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(value)
                .font(.system(size: 16, weight: .black))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            Text(label)
                .font(.system(size: 7, weight: .black))
                .foregroundStyle(DeckTheme.muted)
                .tracking(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(DeckTheme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(color.opacity(0.13)))
    }
}

private struct ActivityHeatmap: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var focus: FocusStore
    @EnvironmentObject private var language: LanguageStore

    private let weeks = 12
    private let calendar = Calendar.current

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(language.text("近 12 周活跃度", "Activity · Last 12 Weeks"))
                    .font(.system(size: 10, weight: .black))
                Spacer()
                Text(language.text("少", "Less"))
                    .foregroundStyle(DeckTheme.muted)
                ForEach(0..<4, id: \.self) { level in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color(level: level))
                        .frame(width: 8, height: 8)
                }
                Text(language.text("多", "More"))
                    .foregroundStyle(DeckTheme.muted)
            }
            .font(.system(size: 7, weight: .bold))

            HStack(alignment: .top, spacing: 4) {
                ForEach(0..<weeks, id: \.self) { week in
                    VStack(spacing: 4) {
                        ForEach(0..<7, id: \.self) { day in
                            let date = date(forWeek: week, day: day)
                            RoundedRectangle(cornerRadius: 2.5)
                                .fill(date > Date() ? DeckTheme.panelRaised.opacity(0.35) : color(level: level(for: date)))
                                .aspectRatio(1, contentMode: .fit)
                                .help(helpText(for: date))
                        }
                    }
                }
            }
        }
        .deckPanel(radius: 11, padding: 13)
    }

    private var startDate: Date {
        let startOfThisWeek = calendar.dateInterval(of: .weekOfYear, for: Date())?.start ?? calendar.startOfDay(for: Date())
        return calendar.date(byAdding: .weekOfYear, value: -(weeks - 1), to: startOfThisWeek) ?? startOfThisWeek
    }

    private func date(forWeek week: Int, day: Int) -> Date {
        calendar.date(byAdding: .day, value: week * 7 + day, to: startDate) ?? startDate
    }

    private func level(for date: Date) -> Int {
        let completed = store.completionCount(on: date)
        let focusBlocks = focus.seconds(on: date) / 1_500
        return min(4, completed + focusBlocks)
    }

    private func color(level: Int) -> Color {
        switch level {
        case 0: return DeckTheme.panelRaised
        case 1: return DeckTheme.cyan.opacity(0.25)
        case 2: return DeckTheme.cyan.opacity(0.48)
        case 3: return DeckTheme.cyan.opacity(0.72)
        default: return DeckTheme.cyan
        }
    }

    private func helpText(for date: Date) -> String {
        let completed = store.completionCount(on: date)
        let minutes = focus.seconds(on: date) / 60
        return language.current == .simplifiedChinese
            ? "\(date.formatted(.dateTime.year().month().day()))：完成 \(completed) 项，专注 \(minutes) 分钟"
            : "\(date.formatted(.dateTime.year().month().day())): \(completed) completed, \(minutes) focus minutes"
    }
}

private struct DirectionDistribution: View {
    @EnvironmentObject private var language: LanguageStore
    let tasks: [TaskItem]

    private var rows: [(String, Int)] {
        Dictionary(grouping: tasks, by: \.normalizedDirection)
            .map { ($0.key, $0.value.count) }
            .sorted { $0.1 > $1.1 }
            .prefix(4)
            .map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(language.text("方向完成分布", "Completion by Direction"))
                .font(.system(size: 10, weight: .black))

            if rows.isEmpty {
                Text(language.text("完成任务后自动生成", "Generated after you complete tasks"))
                    .font(.system(size: 8))
                    .foregroundStyle(DeckTheme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(rows, id: \.0) { row in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(row.0 == "未分类" ? language.text("未分类", "Uncategorized") : row.0).lineLimit(1)
                            Spacer()
                            Text("\(row.1)")
                        }
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(DeckTheme.muted)

                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                Capsule().fill(DeckTheme.panelRaised)
                                Capsule()
                                    .fill(DeckTheme.cyan)
                                    .frame(width: geometry.size.width * CGFloat(row.1) / CGFloat(max(1, rows.first?.1 ?? 1)))
                            }
                        }
                        .frame(height: 4)
                    }
                }
            }
        }
        .deckPanel(radius: 11, padding: 13)
    }
}

private struct FocusLogRow: View {
    let session: FocusSession

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(DeckTheme.cyan)
            VStack(alignment: .leading, spacing: 3) {
                Text(session.taskTitle)
                    .font(.system(size: 8, weight: .semibold))
                    .lineLimit(1)
                Text(session.endedAt.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 7))
                    .foregroundStyle(DeckTheme.muted)
            }
            Spacer()
            Text("\(max(1, session.durationSeconds / 60))M")
                .font(.system(size: 9, weight: .black))
                .foregroundStyle(DeckTheme.cyan)
        }
        .padding(9)
        .background(DeckTheme.panel.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct CompletedLogRow: View {
    @EnvironmentObject private var language: LanguageStore
    let task: TaskItem
    let actualSeconds: Int

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 11))
                .foregroundStyle(DeckTheme.lime)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .font(.system(size: 9, weight: .semibold))
                    .lineLimit(2)
                HStack {
                    Text(task.displayDirection(in: language.current).uppercased())
                    if actualSeconds > 0 { Text("FOCUS \(max(1, actualSeconds / 60))M") }
                    Spacer()
                    Text(task.completedAt?.formatted(date: .omitted, time: .shortened) ?? "")
                }
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(DeckTheme.muted)
            }
        }
        .padding(10)
        .background(DeckTheme.panel.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
