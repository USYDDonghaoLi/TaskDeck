import Foundation

@main
struct LogicCheck {
    @MainActor
    static func main() throws {
        try checkLegacyTaskMigration()
        try checkLegacyFocusMigration()
        try checkSharedStorageMigration()
        try checkCorruptDatabaseProtection()
        try checkTaskLifecycleAndBackups()
        try checkSharedWriteCoordination()
        try checkFocusLifecycle()
        try checkArchiveRoundTrip()
        try checkCompletionStreak()
        checkLanguagePreference()
        print("TaskDeck SQLite, migration, backup, editing, and JSON checks passed")
    }

    @MainActor
    private static func checkLegacyTaskMigration() throws {
        let root = temporaryRoot("TaskDeckLegacyTaskMigration")
        let legacyURL = root.appendingPathComponent("Legacy/tasks.json")
        let databaseURL = root.appendingPathComponent("Shared/TaskDeck/taskdeck.sqlite3")
        defer { try? FileManager.default.removeItem(at: root) }

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
        try FileManager.default.createDirectory(
            at: legacyURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try legacyData.write(to: legacyURL, options: .atomic)

        let store = TaskStore(databaseURL: databaseURL, legacyTaskURL: legacyURL)
        precondition(store.persistenceError == nil)
        precondition(store.tasks.count == 1)
        precondition(store.tasks.first?.id == legacyID)
        precondition(store.tasks.first?.priority == .normal)
        precondition(store.tasks.first?.recurrence == TaskRecurrence.none)
        precondition(store.tasks.first?.notes.isEmpty == true)

        // Migration copies data into SQLite and a legacy backup. It never moves,
        // edits, or deletes the user's original JSON file.
        let preservedLegacyData = try Data(contentsOf: legacyURL)
        precondition(preservedLegacyData == legacyData)
        let legacyBackup = databaseURL.deletingLastPathComponent()
            .appendingPathComponent("Backups/Legacy/tasks-before-sqlite.json")
        let legacyBackupData = try Data(contentsOf: legacyBackup)
        precondition(legacyBackupData == legacyData)
    }

    @MainActor
    private static func checkLegacyFocusMigration() throws {
        let root = temporaryRoot("TaskDeckLegacyFocusMigration")
        let legacyDirectory = root.appendingPathComponent("Legacy")
        let databaseURL = root.appendingPathComponent("Shared/TaskDeck/taskdeck.sqlite3")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: legacyDirectory, withIntermediateDirectories: true)

        let taskID = UUID()
        let base = Date(timeIntervalSince1970: 1_788_200_000)
        let session = FocusSession(
            taskID: taskID,
            taskTitle: "保留专注历史",
            direction: "数据升级",
            startedAt: base,
            endedAt: base.addingTimeInterval(600),
            durationSeconds: 600
        )
        let runtime = FocusRuntimeState(active: ActiveFocus(
            taskID: taskID,
            taskTitle: "保留运行中计时",
            direction: "数据升级",
            initiatedAt: base,
            estimatedMinutes: 25,
            runningSince: nil,
            accumulatedSeconds: 120
        ))
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let sessionsData = try encoder.encode([session])
        let runtimeData = try encoder.encode(runtime)
        let sessionsURL = legacyDirectory.appendingPathComponent("focus-sessions.json")
        let runtimeURL = legacyDirectory.appendingPathComponent("focus-runtime.json")
        try sessionsData.write(to: sessionsURL, options: .atomic)
        try runtimeData.write(to: runtimeURL, options: .atomic)

        let focus = FocusStore(databaseURL: databaseURL, legacyDirectory: legacyDirectory)
        precondition(focus.sessions == [session])
        precondition(focus.active == runtime.active)
        let preservedSessionsData = try Data(contentsOf: sessionsURL)
        let preservedRuntimeData = try Data(contentsOf: runtimeURL)
        precondition(preservedSessionsData == sessionsData)
        precondition(preservedRuntimeData == runtimeData)

        let backupRoot = databaseURL.deletingLastPathComponent().appendingPathComponent("Backups/Legacy")
        let backedUpSessionsData = try Data(contentsOf: backupRoot.appendingPathComponent("focus-sessions-before-sqlite.json"))
        let backedUpRuntimeData = try Data(contentsOf: backupRoot.appendingPathComponent("focus-runtime-before-sqlite.json"))
        precondition(backedUpSessionsData == sessionsData)
        precondition(backedUpRuntimeData == runtimeData)
    }

    @MainActor
    private static func checkSharedStorageMigration() throws {
        let root = temporaryRoot("TaskDeckSharedStorage")
        let legacyURL = root.appendingPathComponent("Legacy/tasks.json")
        let groupRoot = root.appendingPathComponent("GroupContainer")
        let databaseURL = TaskDeckShared.databaseURL(groupRoot: groupRoot)
        defer { try? FileManager.default.removeItem(at: root) }

        let recurring = TaskItem(
            direction: "升级安全",
            title: "保留原任务并共享给 Widget",
            estimatedMinutes: 20,
            dueAt: Date(timeIntervalSince1970: 1_788_200_000),
            recurrence: .daily
        )
        let originalData = try encodeLegacyTasks([recurring])
        try FileManager.default.createDirectory(
            at: legacyURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try originalData.write(to: legacyURL, options: .atomic)

        let store = TaskStore(databaseURL: databaseURL, legacyTaskURL: legacyURL)
        precondition(store.tasks.count == 1)
        let completedAt = Date(timeIntervalSince1970: 1_788_200_500)
        let didToggle = try TaskDeckShared.toggleTask(id: recurring.id, at: databaseURL, now: completedAt)
        precondition(didToggle)

        let sharedTasks = try TaskDeckShared.loadTasks(from: databaseURL)
        precondition(sharedTasks.first(where: { $0.id == recurring.id })?.completedAt == completedAt)
        precondition(sharedTasks.count == 2)
        let preservedLegacyData = try Data(contentsOf: legacyURL)
        precondition(preservedLegacyData == originalData)

        // Re-opening the same database is idempotent and does not re-import JSON.
        let reopened = TaskStore(databaseURL: databaseURL, legacyTaskURL: legacyURL)
        precondition(reopened.tasks.count == 2)

        // Once migration is marked complete, intentionally deleting every task
        // must not resurrect the preserved legacy JSON on a later launch.
        try TaskDatabase(url: databaseURL).replaceTasks([], reason: "delete-all-check")
        let reopenedAfterDeleteAll = TaskStore(databaseURL: databaseURL, legacyTaskURL: legacyURL)
        precondition(reopenedAfterDeleteAll.tasks.isEmpty)
    }

    @MainActor
    private static func checkCorruptDatabaseProtection() throws {
        let root = temporaryRoot("TaskDeckCorruptDatabase")
        let databaseURL = root.appendingPathComponent("taskdeck.sqlite3")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let corruptData = Data("{ this is not sqlite".utf8)
        try corruptData.write(to: databaseURL, options: .atomic)

        let store = TaskStore(databaseURL: databaseURL)
        precondition(store.persistenceError != nil)
        _ = store.add(
            direction: "安全检查",
            title: "这条记录只能留在内存",
            estimatedMinutes: 10,
            dueAt: nil,
            reminderEnabled: false
        )
        let databaseDataAfterAttemptedSave = try Data(contentsOf: databaseURL)
        precondition(databaseDataAfterAttemptedSave == corruptData)
    }

    @MainActor
    private static func checkTaskLifecycleAndBackups() throws {
        let root = temporaryRoot("TaskDeckTaskLifecycle")
        let databaseURL = root.appendingPathComponent("TaskDeck/taskdeck.sqlite3")
        defer { try? FileManager.default.removeItem(at: root) }

        let store = TaskStore(databaseURL: databaseURL)
        let task = store.add(
            direction: "产品发布",
            title: "输出三条改版结论",
            estimatedMinutes: 45,
            dueAt: Date().addingTimeInterval(3_600),
            reminderEnabled: true
        )
        var editable = store.add(
            direction: "学习",
            title: "回顾 Swift 并记五条笔记",
            estimatedMinutes: 25,
            dueAt: nil,
            reminderEnabled: false
        )

        editable.title = "回顾 Swift 并记录五条笔记"
        editable.estimatedMinutes = 50
        editable.priority = .urgent
        editable.notes = "从并发模型开始"
        let updated = store.update(editable)
        precondition(updated?.title == "回顾 Swift 并记录五条笔记")
        precondition(updated?.estimatedMinutes == 50)
        precondition(updated?.priority == .urgent)
        precondition(updated?.id == editable.id)

        let delayedDate = Date().addingTimeInterval(7_200)
        precondition(store.reschedule(editable, to: delayedDate)?.dueAt == delayedDate)
        store.toggle(task)
        precondition(store.report(for: .day).completedCount == 1)
        precondition(store.report(for: .day).estimatedMinutes == 45)

        let reloaded = TaskStore(databaseURL: databaseURL)
        precondition(reloaded.tasks.first(where: { $0.id == editable.id })?.estimatedMinutes == 50)
        precondition(reloaded.tasks(for: .completed).first?.title == "输出三条改版结论")

        let recurring = store.add(
            direction: "健康",
            title: "完成训练",
            estimatedMinutes: 35,
            dueAt: Date().addingTimeInterval(10_800),
            reminderEnabled: true,
            recurrence: .daily
        )
        precondition(store.toggle(recurring)?.recurrence == .daily)
        _ = store.toggle(recurring)
        precondition(store.toggle(recurring) == nil)

        // Generate more than the retention limit and verify the newest 30 remain.
        for index in 0..<32 {
            var repeatedlyEdited = editable
            repeatedlyEdited.estimatedMinutes = 50 + index
            _ = store.update(repeatedlyEdited)
        }
        let backupDirectory = databaseURL.deletingLastPathComponent()
            .appendingPathComponent("Backups/Database")
        let backups = try FileManager.default.contentsOfDirectory(
            at: backupDirectory,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "sqlite3" }
        precondition(backups.count == 30)
    }

    @MainActor
    private static func checkFocusLifecycle() throws {
        let root = temporaryRoot("TaskDeckFocusLifecycle")
        let databaseURL = root.appendingPathComponent("TaskDeck/taskdeck.sqlite3")
        defer { try? FileManager.default.removeItem(at: root) }

        let task = TaskItem(direction: "写作", title: "完成专注测试", estimatedMinutes: 25)
        let base = Date(timeIntervalSince1970: 1_788_200_000)
        let focus = FocusStore(databaseURL: databaseURL)
        precondition(focus.beginOrToggle(task, now: base))
        focus.pause(now: base.addingTimeInterval(600))
        precondition(Int(focus.elapsed(at: base.addingTimeInterval(800))) == 600)
        focus.resume(now: base.addingTimeInterval(900))
        precondition(focus.finish(now: base.addingTimeInterval(1_500))?.durationSeconds == 1_200)

        let interval = DateInterval(start: base, end: base.addingTimeInterval(2_000))
        precondition(focus.totalSeconds(in: interval) == 1_200)
        let reloaded = FocusStore(databaseURL: databaseURL)
        precondition(reloaded.sessions.count == 1)
        precondition(reloaded.active == nil)
        precondition(reloaded.totalSeconds(in: interval) == 1_200)
    }

    @MainActor
    private static func checkSharedWriteCoordination() throws {
        let root = temporaryRoot("TaskDeckSharedWriteCoordination")
        let databaseURL = root.appendingPathComponent("TaskDeck/taskdeck.sqlite3")
        defer { try? FileManager.default.removeItem(at: root) }

        let firstWindow = TaskStore(databaseURL: databaseURL)
        let staleWindow = TaskStore(databaseURL: databaseURL)
        let firstTask = firstWindow.add(
            direction: "并发安全",
            title: "Widget 先完成这件事",
            estimatedMinutes: 20,
            dueAt: nil,
            reminderEnabled: false
        )
        _ = staleWindow.add(
            direction: "并发安全",
            title: "旧视图再添加一件事",
            estimatedMinutes: 15,
            dueAt: nil,
            reminderEnabled: false
        )
        let tasksAfterBothAdds = try TaskDeckShared.loadTasks(from: databaseURL)
        precondition(tasksAfterBothAdds.count == 2)

        let completedAt = Date(timeIntervalSince1970: 1_788_400_000)
        _ = try TaskDeckShared.toggleTask(id: firstTask.id, at: databaseURL, now: completedAt)
        guard var taskFromStaleWindow = staleWindow.tasks.first(where: { $0.id != firstTask.id }) else {
            preconditionFailure("Expected the task added from the stale view")
        }
        taskFromStaleWindow.priority = .urgent
        _ = staleWindow.update(taskFromStaleWindow)

        let coordinatedTasks = try TaskDeckShared.loadTasks(from: databaseURL)
        precondition(coordinatedTasks.count == 2)
        precondition(coordinatedTasks.first(where: { $0.id == firstTask.id })?.completedAt == completedAt)
        precondition(coordinatedTasks.first(where: { $0.id == taskFromStaleWindow.id })?.priority == .urgent)
    }

    @MainActor
    private static func checkArchiveRoundTrip() throws {
        let root = temporaryRoot("TaskDeckArchiveRoundTrip")
        let sourceURL = root.appendingPathComponent("Source/taskdeck.sqlite3")
        let targetURL = root.appendingPathComponent("Target/taskdeck.sqlite3")
        defer { try? FileManager.default.removeItem(at: root) }

        let sourceTasks = TaskStore(databaseURL: sourceURL)
        let sourceFocus = FocusStore(databaseURL: sourceURL)
        let task = sourceTasks.add(
            direction: "导入导出",
            title: "验证完整 JSON 归档",
            estimatedMinutes: 40,
            priority: .important,
            dueAt: nil,
            reminderEnabled: false
        )
        let base = Date(timeIntervalSince1970: 1_788_300_000)
        precondition(sourceFocus.beginOrToggle(task, now: base))
        _ = sourceFocus.finish(now: base.addingTimeInterval(300))
        let archiveData = try sourceTasks.exportArchive(focusStore: sourceFocus)

        guard case let .archive(decoded) = try TaskDeckArchiveCodec.decode(archiveData) else {
            preconditionFailure("Expected a complete TaskDeck archive")
        }
        precondition(decoded.schemaVersion == 2)
        precondition(decoded.tasks.count == 1)
        precondition(decoded.focusSessions.count == 1)

        let targetTasks = TaskStore(databaseURL: targetURL)
        let targetFocus = FocusStore(databaseURL: targetURL)
        try targetTasks.importArchive(archiveData, focusStore: targetFocus)
        precondition(targetTasks.tasks == decoded.tasks)
        precondition(targetFocus.sessions == decoded.focusSessions)

        let targetBackupDirectory = targetURL.deletingLastPathComponent()
            .appendingPathComponent("Backups/Database")
        let importBackups = try FileManager.default.contentsOfDirectory(
            at: targetBackupDirectory,
            includingPropertiesForKeys: nil
        )
        precondition(importBackups.contains(where: { $0.pathExtension == "sqlite3" }))

        // Legacy arrays remain import-compatible and replace tasks only.
        let legacyTask = TaskItem(direction: "兼容", title: "导入旧版 JSON", estimatedMinutes: 15)
        try targetTasks.importArchive(encodeLegacyTasks([legacyTask]), focusStore: targetFocus)
        precondition(targetTasks.tasks.count == 1)
        precondition(targetTasks.tasks.first?.id == legacyTask.id)
        precondition(targetTasks.tasks.first?.title == legacyTask.title)
        precondition(targetFocus.sessions.count == 1)
    }

    @MainActor
    private static func checkCompletionStreak() throws {
        let root = temporaryRoot("TaskDeckStreak")
        let databaseURL = root.appendingPathComponent("TaskDeck/taskdeck.sqlite3")
        defer { try? FileManager.default.removeItem(at: root) }

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
        try TaskDatabase(url: databaseURL).replaceTasks(tasks, reason: "streak-check")
        precondition(TaskStore(databaseURL: databaseURL).completionStreak() == 3)
    }

    @MainActor
    private static func checkLanguagePreference() {
        let suiteName = "TaskDeckLanguageCheck-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            preconditionFailure("Could not create isolated user defaults")
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let language = LanguageStore(defaults: defaults, syncsSharedDefaults: false)
        precondition(language.current == .simplifiedChinese)
        language.current = .english
        precondition(defaults.string(forKey: LanguageStore.defaultsKey) == AppLanguage.english.rawValue)
        precondition(TaskFilter.today.title(in: language.current) == "Today")
        precondition(TaskPriority.urgent.title(in: language.current) == "Urgent")
        precondition(TaskRecurrence.weekdays.title(in: language.current) == "Weekdays")
        precondition(ReportPeriod.month.reportTitle(in: language.current) == "Monthly Action Report")
    }

    private static func temporaryRoot(_ name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name)-\(UUID().uuidString)")
    }

    private static func encodeLegacyTasks(_ tasks: [TaskItem]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(tasks)
    }
}
