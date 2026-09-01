import Foundation

@main
struct PDFReportCheck {
    static func main() throws {
        guard (2...3).contains(CommandLine.arguments.count) else {
            fputs("Usage: pdf_report_check OUTPUT.pdf [en]\n", stderr)
            exit(2)
        }

        let language: AppLanguage = CommandLine.arguments.count == 3 && CommandLine.arguments[2] == "en"
            ? .english
            : .simplifiedChinese

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Australia/Sydney")!

        func date(_ day: Int, hour: Int = 18) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: 8, day: day, hour: hour))!
        }

        let directions = ["产品迭代", "深度学习", "力量训练", "内容创作"]
        var tasks: [TaskItem] = []
        var sessions: [FocusSession] = []

        for index in 0..<24 {
            let task = TaskItem(
                direction: directions[index % directions.count],
                title: "完成第 \(index + 1) 个关键行动并记录复盘结论",
                notes: index.isMultiple(of: 3) ? "这是一个用于验证 PDF 中文排版的任务备注" : "",
                estimatedMinutes: 20 + (index % 4) * 15,
                priority: index.isMultiple(of: 5) ? .urgent : .normal,
                dueAt: date(index + 1, hour: 10),
                reminderEnabled: false,
                completedAt: date(index + 1)
            )
            tasks.append(task)

            let duration = 900 + (index % 4) * 600
            sessions.append(FocusSession(
                taskID: task.id,
                taskTitle: task.title,
                direction: task.normalizedDirection,
                startedAt: date(index + 1, hour: 16),
                endedAt: date(index + 1, hour: 17),
                durationSeconds: duration
            ))
        }

        let interval = DateInterval(start: date(1, hour: 0), end: calendar.date(from: DateComponents(year: 2026, month: 9, day: 1))!)
        let payload = PDFReportPayload(
            periodTitle: ReportPeriod.month.reportTitle(in: language),
            interval: interval,
            completedTasks: tasks.reversed(),
            focusSessions: sessions,
            streak: 7,
            generatedAt: date(31, hour: 20),
            language: language
        )

        try PDFReportExporter.write(payload, to: URL(fileURLWithPath: CommandLine.arguments[1]))
        print(CommandLine.arguments[1])
    }
}
