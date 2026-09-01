import Foundation

@main
struct LogicCheck {
    @MainActor
    static func main() throws {
        try checkLegacyMigration()
        try checkCorruptDataProtection()
        try checkTaskLifecycle()
        try checkFocusLifecycle()
        try checkCompletionStreak()
        checkLanguagePreference()
        print("TaskDeck logic checks passed")
    }

    @MainActor
    private static func checkCorruptDataProtection() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TaskDeckCorruptDataCheck-\(UUID().uuidString)")
        let fileURL = directory.appendingPathComponent("tasks.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let corruptData = Data("{ damaged data".utf8)
        try corruptData.write(to: fileURL, options: .atomic)

        let store = TaskStore(fileURL: fileURL)
        precondition(store.persistenceError != nil)
        _ = store.add(
            direction: "安全检查",
            title: "这条记录只能留在内存",
            estimatedMinutes: 10,
            dueAt: nil,
            reminderEnabled: false
        )
        let dataAfterAttemptedSave = try Data(contentsOf: fileURL)
        precondition(dataAfterAttemptedSave == corruptData)
    }

    @MainActor
    private static func checkLegacyMigration() throws {
        let migrationDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TaskDeckMigrationCheck-\(UUID().uuidString)")
        let fileURL = migrationDirectory.appendingPathComponent("tasks.json")
        defer { try? FileManager.default.removeItem(at: migrationDirectory) }

        try FileManager.default.createDirectory(at: migrationDirectory, withIntermediateDirectories: true)
        let legacyID = UUID()
        let legacyJSON = """
        [
          {
            "id" : "\(legacyID.uuidString)",
            "direction" : "旧版任务",
            "title" : "升级后仍需保留",
            "estimatedMinutes" : 30,
            "reminderEnabled" : false,
            "createdAt" : "2026-08-31T12:00:00Z"
          }
        ]
        """
        let legacyData = Data(legacyJSON.utf8)
        try legacyData.write(to: fileURL, options: .atomic)

        let migratedStore = TaskStore(fileURL: fileURL)
        precondition(migratedStore.tasks(for: .inbox).count == 1)
        precondition(migratedStore.tasks(for: .inbox).first?.id == legacyID)
        precondition(migratedStore.tasks(for: .inbox).first?.priority == .normal)
        precondition(migratedStore.tasks(for: .inbox).first?.recurrence == TaskRecurrence.none)
        precondition(migratedStore.tasks(for: .inbox).first?.notes.isEmpty == true)

        let backupURL = migrationDirectory
            .appendingPathComponent("Backups")
            .appendingPathComponent("tasks-before-v1.1.json")
        precondition(FileManager.default.fileExists(atPath: backupURL.path))
        let backupData = try Data(contentsOf: backupURL)
        precondition(backupData == legacyData)
    }

    @MainActor
    private static func checkTaskLifecycle() throws {
        let testDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TaskDeckLogicCheck-\(UUID().uuidString)")
        let fileURL = testDirectory.appendingPathComponent("tasks.json")
        defer { try? FileManager.default.removeItem(at: testDirectory) }

        let store = TaskStore(fileURL: fileURL)
        let task = store.add(
            direction: "产品发布",
            title: "输出三条改版结论",
            estimatedMinutes: 45,
            dueAt: Date().addingTimeInterval(3_600),
            reminderEnabled: true
        )

        precondition(store.pendingTasks.count == 1)
        precondition(task.estimatedMinutes == 45)
        precondition(task.reminderEnabled)

        var editableTask = store.add(
            direction: "学习",
            title: "回顾 Swift 并记五条笔记",
            estimatedMinutes: 25,
            dueAt: nil,
            reminderEnabled: false
        )
        precondition(store.tasks(for: .today).count == 2)

        editableTask.priority = .urgent
        editableTask.notes = "从并发模型开始"
        editableTask.title = "回顾 Swift 并记录五条笔记"
        let updatedTask = store.update(editableTask)
        precondition(updatedTask?.priority == .urgent)
        precondition(updatedTask?.notes == "从并发模型开始")

        let delayedDate = Date().addingTimeInterval(7_200)
        let delayedTask = store.reschedule(editableTask, to: delayedDate)
        precondition(delayedTask?.dueAt == delayedDate)

        store.toggle(task)
        precondition(store.report(for: .day).completedCount == 1)
        precondition(store.report(for: .day).estimatedMinutes == 45)

        let reloaded = TaskStore(fileURL: fileURL)
        precondition(reloaded.tasks(for: .completed).first?.title == "输出三条改版结论")

        let normalized = TaskItem(
            direction: "  ",
            title: "  明确下一步  ",
            estimatedMinutes: 1,
            reminderEnabled: true
        )
        precondition(normalized.normalizedDirection == "未分类")
        precondition(normalized.title == "明确下一步")
        precondition(normalized.estimatedMinutes == 5)
        precondition(!normalized.reminderEnabled)

        let recurring = store.add(
            direction: "健康",
            title: "完成训练",
            estimatedMinutes: 35,
            dueAt: Date().addingTimeInterval(10_800),
            reminderEnabled: true,
            recurrence: .daily
        )
        let generated = store.toggle(recurring)
        precondition(generated?.recurrence == .daily)
        precondition((generated?.dueAt ?? .distantPast) > (recurring.dueAt ?? .distantFuture))

        _ = store.toggle(recurring)
        let duplicate = store.toggle(recurring)
        precondition(duplicate == nil)

        let backupURL = testDirectory
            .appendingPathComponent("Backups")
            .appendingPathComponent("tasks-last-known-good.json")
        precondition(FileManager.default.fileExists(atPath: backupURL.path))
    }

    @MainActor
    private static func checkFocusLifecycle() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TaskDeckFocusCheck-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        let task = TaskItem(direction: "写作", title: "完成专注测试", estimatedMinutes: 25)
        let base = Date(timeIntervalSince1970: 1_788_200_000)
        let focus = FocusStore(baseDirectory: directory)
        precondition(focus.beginOrToggle(task, now: base))
        focus.pause(now: base.addingTimeInterval(600))
        precondition(Int(focus.elapsed(at: base.addingTimeInterval(800))) == 600)
        focus.resume(now: base.addingTimeInterval(900))
        let session = focus.finish(now: base.addingTimeInterval(1_500))
        precondition(session?.durationSeconds == 1_200)

        let interval = DateInterval(start: base, end: base.addingTimeInterval(2_000))
        precondition(focus.totalSeconds(in: interval) == 1_200)
        precondition(focus.seconds(for: task.id) == 1_200)

        let reloaded = FocusStore(baseDirectory: directory)
        precondition(reloaded.sessions.count == 1)
        precondition(reloaded.active == nil)
        precondition(reloaded.totalSeconds(in: interval) == 1_200)
    }

    @MainActor
    private static func checkCompletionStreak() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TaskDeckStreakCheck-\(UUID().uuidString)")
        let fileURL = directory.appendingPathComponent("tasks.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let tasks = (0..<3).map { offset in
            TaskItem(
                direction: "连续行动",
                title: "第 \(offset + 1) 天",
                estimatedMinutes: 15,
                completedAt: calendar.date(byAdding: .day, value: -offset, to: today)
            )
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(tasks).write(to: fileURL, options: .atomic)

        let store = TaskStore(fileURL: fileURL)
        precondition(store.completionStreak() == 3)
    }

    @MainActor
    private static func checkLanguagePreference() {
        let suiteName = "TaskDeckLanguageCheck-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            preconditionFailure("Could not create isolated user defaults")
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let language = LanguageStore(defaults: defaults)
        precondition(language.current == .simplifiedChinese)
        precondition(TaskFilter.today.title(in: language.current) == "今日任务")

        language.current = .english
        precondition(defaults.string(forKey: LanguageStore.defaultsKey) == AppLanguage.english.rawValue)
        precondition(TaskFilter.today.title(in: language.current) == "Today")
        precondition(TaskPriority.urgent.title(in: language.current) == "Urgent")
        precondition(TaskRecurrence.weekdays.title(in: language.current) == "Weekdays")
        precondition(ReportPeriod.month.reportTitle(in: language.current) == "Monthly Action Report")
    }
}
