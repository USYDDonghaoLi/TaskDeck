import AppKit
import CoreGraphics
import Foundation

struct PDFReportPayload {
    let periodTitle: String
    let interval: DateInterval
    let completedTasks: [TaskItem]
    let focusSessions: [FocusSession]
    let streak: Int
    let generatedAt: Date
}

enum PDFReportError: LocalizedError {
    case cannotCreateFile

    var errorDescription: String? {
        "无法创建 PDF 文件，请检查保存位置和磁盘权限。"
    }
}

@MainActor
enum PDFReportExporter {
    static func write(_ payload: PDFReportPayload, to url: URL) throws {
        let renderer = PDFRenderer(payload: payload, pageSize: CGSize(width: 595, height: 842))
        let data = try renderer.renderPage(1)
        try data.write(to: url, options: .atomic)
    }
}

@MainActor
private final class PDFRenderer {
    private let payload: PDFReportPayload
    private let pageSize: CGSize
    private let calendar = Calendar.current
    private let margin: CGFloat = 46
    private let firstPageCount = 5

    private let ink = NSColor(red: 0.035, green: 0.055, blue: 0.085, alpha: 1)
    private let muted = NSColor(red: 0.35, green: 0.42, blue: 0.50, alpha: 1)
    private let cyan = NSColor(red: 0.0, green: 0.72, blue: 0.66, alpha: 1)
    private let cyanPale = NSColor(red: 0.91, green: 0.98, blue: 0.97, alpha: 1)
    private let lime = NSColor(red: 0.38, green: 0.66, blue: 0.12, alpha: 1)
    private let violet = NSColor(red: 0.43, green: 0.31, blue: 0.78, alpha: 1)
    private let orange = NSColor(red: 0.88, green: 0.40, blue: 0.12, alpha: 1)
    private let rule = NSColor(red: 0.88, green: 0.90, blue: 0.92, alpha: 1)

    init(payload: PDFReportPayload, pageSize: CGSize) {
        self.payload = payload
        self.pageSize = pageSize
    }

    var totalPages: Int {
        1
    }

    func renderPage(_ pageNumber: Int) throws -> Data {
        let canvas = PDFCanvasView(frame: CGRect(origin: .zero, size: pageSize))
        canvas.drawContent = { [self] in
            NSColor.white.setFill()
            NSBezierPath(rect: CGRect(origin: .zero, size: pageSize)).fill()

            drawSummaryPage(tasks: Array(payload.completedTasks.prefix(firstPageCount)))
            drawFooter(page: pageNumber, total: totalPages)
        }
        return canvas.dataWithPDF(inside: canvas.bounds)
    }

    private func drawSummaryPage(tasks: [TaskItem]) {
        drawBrandHeader()
        drawText(payload.periodTitle, in: CGRect(x: margin, y: 83, width: 380, height: 32), font: .systemFont(ofSize: 25, weight: .bold), color: ink)
        drawText(intervalText, in: CGRect(x: margin, y: 116, width: 430, height: 18), font: mono(size: 9, weight: .semibold), color: muted)

        let estimated = payload.completedTasks.reduce(0) { $0 + $1.estimatedMinutes * 60 }
        let actual = payload.focusSessions.reduce(0) { $0 + $1.durationSeconds }
        let cardWidth: CGFloat = 116
        let gap: CGFloat = 11
        drawMetricCard(x: margin, value: "\(payload.completedTasks.count)", label: "COMPLETED", color: lime)
        drawMetricCard(x: margin + cardWidth + gap, value: duration(actual), label: "ACTUAL FOCUS", color: cyan)
        drawMetricCard(x: margin + (cardWidth + gap) * 2, value: "\(payload.streak) DAYS", label: "CURRENT STREAK", color: orange)
        drawMetricCard(x: margin + (cardWidth + gap) * 3, value: duration(estimated), label: "ESTIMATED", color: violet)

        drawSectionTitle("ACTIVITY HEATMAP // 12 WEEKS", y: 247)
        drawHeatmap(y: 278)

        drawSectionTitle("DIRECTION BREAKDOWN", y: 386)
        drawDirectionRows(y: 418)

        drawSectionTitle("COMPLETED TASKS", y: 554)
        if payload.completedTasks.count > firstPageCount {
            let hiddenCount = payload.completedTasks.count - firstPageCount
            drawText(
                "LATEST \(firstPageCount) · \(hiddenCount) MORE IN TASKDECK",
                in: CGRect(x: 290, y: 554, width: 259, height: 17),
                font: mono(size: 6.5, weight: .semibold),
                color: muted,
                alignment: .right
            )
        }
        if tasks.isEmpty {
            drawText("此周期暂无完成记录。", in: CGRect(x: margin, y: 592, width: 500, height: 30), font: .systemFont(ofSize: 10), color: muted)
        } else {
            for (index, task) in tasks.enumerated() {
                drawTaskRow(task, y: 584 + CGFloat(index) * 39)
            }
        }
    }

    private func drawBrandHeader() {
        NSColor(red: 0.02, green: 0.06, blue: 0.08, alpha: 1).setFill()
        NSBezierPath(roundedRect: CGRect(x: margin, y: 38, width: 28, height: 28), xRadius: 7, yRadius: 7).fill()
        drawText(">_", in: CGRect(x: margin + 6, y: 44, width: 20, height: 16), font: mono(size: 10, weight: .bold), color: cyan)
        drawText("TASKDECK // ACTIVITY REPORT", in: CGRect(x: margin + 40, y: 43, width: 300, height: 18), font: mono(size: 10, weight: .bold), color: ink)
        drawText("LOCAL FIRST · PERSONAL OPS", in: CGRect(x: 398, y: 44, width: 150, height: 16), font: mono(size: 7, weight: .semibold), color: muted, alignment: .right)
    }

    private func drawMetricCard(x: CGFloat, value: String, label: String, color: NSColor) {
        let rect = CGRect(x: x, y: 151, width: 116, height: 70)
        NSColor(red: 0.965, green: 0.975, blue: 0.98, alpha: 1).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 9, yRadius: 9).fill()
        color.withAlphaComponent(0.22).setStroke()
        let outline = NSBezierPath(roundedRect: rect, xRadius: 9, yRadius: 9)
        outline.lineWidth = 1
        outline.stroke()
        drawText(value, in: CGRect(x: x + 12, y: 165, width: 92, height: 25), font: .systemFont(ofSize: 18, weight: .bold), color: color)
        drawText(label, in: CGRect(x: x + 12, y: 196, width: 92, height: 14), font: mono(size: 7, weight: .bold), color: muted)
    }

    private func drawHeatmap(y: CGFloat) {
        let weeks = 12
        let cell: CGFloat = 9
        let gap: CGFloat = 4
        let startOfCurrentWeek = calendar.dateInterval(of: .weekOfYear, for: payload.generatedAt)?.start ?? calendar.startOfDay(for: payload.generatedAt)
        let start = calendar.date(byAdding: .weekOfYear, value: -(weeks - 1), to: startOfCurrentWeek) ?? startOfCurrentWeek

        for week in 0..<weeks {
            for day in 0..<7 {
                let date = calendar.date(byAdding: .day, value: week * 7 + day, to: start) ?? start
                let level = activityLevel(on: date)
                let color: NSColor
                if date > payload.generatedAt {
                    color = rule.withAlphaComponent(0.45)
                } else {
                    switch level {
                    case 0: color = rule
                    case 1: color = cyan.withAlphaComponent(0.28)
                    case 2: color = cyan.withAlphaComponent(0.50)
                    case 3: color = cyan.withAlphaComponent(0.72)
                    default: color = cyan
                    }
                }
                color.setFill()
                let x = margin + CGFloat(week) * (cell + gap)
                let cellY = y + CGFloat(day) * (cell + gap)
                NSBezierPath(roundedRect: CGRect(x: x, y: cellY, width: cell, height: cell), xRadius: 2, yRadius: 2).fill()
            }
        }

        drawText("完成任务与每 25 分钟专注都会提高活跃度", in: CGRect(x: 230, y: y + 31, width: 310, height: 30), font: .systemFont(ofSize: 8), color: muted, alignment: .right)
    }

    private func drawDirectionRows(y: CGFloat) {
        let rows = directionRows
        if rows.isEmpty {
            drawText("暂无方向数据", in: CGRect(x: margin, y: y, width: 300, height: 20), font: .systemFont(ofSize: 9), color: muted)
            return
        }

        let maxCount = max(1, rows.map(\.count).max() ?? 1)
        for (index, row) in rows.prefix(4).enumerated() {
            let rowY = y + CGFloat(index) * 31
            drawText(row.direction, in: CGRect(x: margin, y: rowY, width: 155, height: 16), font: .systemFont(ofSize: 9, weight: .semibold), color: ink)
            drawText("\(row.count) TASKS · \(duration(row.seconds))", in: CGRect(x: 405, y: rowY, width: 140, height: 16), font: mono(size: 7, weight: .bold), color: muted, alignment: .right)
            rule.setFill()
            NSBezierPath(roundedRect: CGRect(x: margin, y: rowY + 19, width: 499, height: 4), xRadius: 2, yRadius: 2).fill()
            cyan.setFill()
            NSBezierPath(roundedRect: CGRect(x: margin, y: rowY + 19, width: 499 * CGFloat(row.count) / CGFloat(maxCount), height: 4), xRadius: 2, yRadius: 2).fill()
        }
    }

    private func drawTaskRow(_ task: TaskItem, y: CGFloat, compact: Bool = false) {
        let height: CGFloat = compact ? 30 : 34
        NSColor(red: 0.975, green: 0.98, blue: 0.985, alpha: 1).setFill()
        NSBezierPath(roundedRect: CGRect(x: margin, y: y, width: 503, height: height), xRadius: 6, yRadius: 6).fill()
        lime.setFill()
        NSBezierPath(ovalIn: CGRect(x: margin + 10, y: y + (height - 7) / 2, width: 7, height: 7)).fill()
        drawText(task.title, in: CGRect(x: margin + 27, y: y + 6, width: 300, height: 16), font: .systemFont(ofSize: compact ? 8.5 : 9, weight: .semibold), color: ink)
        let actualSeconds = payload.focusSessions.filter { $0.taskID == task.id }.reduce(0) { $0 + $1.durationSeconds }
        let metadata = "\(task.normalizedDirection) · EST \(task.estimatedMinutes)M · ACT \(actualSeconds / 60)M"
        drawText(metadata, in: CGRect(x: 355, y: y + 7, width: 184, height: 14), font: mono(size: 6.5, weight: .semibold), color: muted, alignment: .right)
    }

    private func drawSectionTitle(_ title: String, y: CGFloat) {
        drawText(title, in: CGRect(x: margin, y: y, width: 360, height: 17), font: mono(size: 9, weight: .bold), color: ink)
        drawLine(y: y + 22)
    }

    private func drawLine(y: CGFloat) {
        rule.setStroke()
        let path = NSBezierPath()
        path.move(to: CGPoint(x: margin, y: y))
        path.line(to: CGPoint(x: pageSize.width - margin, y: y))
        path.lineWidth = 1
        path.stroke()
    }

    private func drawFooter(page: Int, total: Int) {
        drawLine(y: 806)
        let generated = payload.generatedAt.formatted(.dateTime.year().month(.twoDigits).day(.twoDigits).hour().minute())
        drawText("Generated locally by TaskDeck · \(generated)", in: CGRect(x: margin, y: 816, width: 360, height: 14), font: mono(size: 6.5, weight: .medium), color: muted)
        drawText("PAGE \(page) / \(total)", in: CGRect(x: 450, y: 816, width: 99, height: 14), font: mono(size: 6.5, weight: .bold), color: muted, alignment: .right)
    }

    private func drawText(
        _ text: String,
        in rect: CGRect,
        font: NSFont,
        color: NSColor,
        alignment: NSTextAlignment = .left
    ) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byTruncatingTail
        (text as NSString).draw(
            in: rect,
            withAttributes: [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: paragraph
            ]
        )
    }

    private func mono(size: CGFloat, weight: NSFont.Weight) -> NSFont {
        NSFont.monospacedSystemFont(ofSize: size, weight: weight)
    }

    private func duration(_ seconds: Int) -> String {
        let minutes = seconds / 60
        if minutes >= 60 {
            let hours = Double(minutes) / 60
            return hours.formatted(.number.precision(.fractionLength(hours.rounded() == hours ? 0 : 1))) + "H"
        }
        return "\(minutes)M"
    }

    private var intervalText: String {
        let start = payload.interval.start.formatted(.dateTime.year().month(.twoDigits).day(.twoDigits))
        let end = payload.interval.end.addingTimeInterval(-1).formatted(.dateTime.year().month(.twoDigits).day(.twoDigits))
        return "\(start) - \(end)"
    }

    private func activityLevel(on date: Date) -> Int {
        let completed = payload.completedTasks.filter {
            guard let completedAt = $0.completedAt else { return false }
            return calendar.isDate(completedAt, inSameDayAs: date)
        }.count
        let seconds = payload.focusSessions.filter { calendar.isDate($0.endedAt, inSameDayAs: date) }.reduce(0) { $0 + $1.durationSeconds }
        return min(4, completed + seconds / 1_500)
    }

    private var directionRows: [(direction: String, count: Int, seconds: Int)] {
        let taskGroups = Dictionary(grouping: payload.completedTasks, by: \.normalizedDirection)
        let focusGroups = Dictionary(grouping: payload.focusSessions, by: \.direction)
        let directions = Set(taskGroups.keys).union(focusGroups.keys)
        return directions.map { direction in
            (
                direction: direction,
                count: taskGroups[direction]?.count ?? 0,
                seconds: focusGroups[direction]?.reduce(0) { $0 + $1.durationSeconds } ?? 0
            )
        }.sorted {
            if $0.count != $1.count { return $0.count > $1.count }
            return $0.seconds > $1.seconds
        }
    }
}

private final class PDFCanvasView: NSView {
    var drawContent: (() -> Void)?

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawContent?()
    }
}
