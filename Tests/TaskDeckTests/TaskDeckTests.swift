import XCTest

final class TaskDeckTests: XCTestCase {
    @MainActor
    func testTaskLifecyclePersistsWithoutTouchingUserData() throws {
        try withTemporaryDatabase { databaseURL in
            let store = TaskStore(databaseURL: databaseURL)
            let task = store.add(
                direction: "Release",
                title: "Ship a precise build",
                estimatedMinutes: 30,
                priority: .urgent,
                dueAt: nil,
                reminderEnabled: false
            )
            XCTAssertEqual(store.activeTasks.count, 1)
            XCTAssertEqual(store.toggle(task), nil)
            XCTAssertTrue(store.tasks.first?.isCompleted == true)

            let reopened = TaskStore(databaseURL: databaseURL)
            XCTAssertEqual(reopened.tasks.first?.id, task.id)
            XCTAssertTrue(reopened.tasks.first?.isCompleted == true)
        }
    }

    @MainActor
    func testSubtasksSearchAndCompoundFilters() throws {
        try withTemporaryDatabase { databaseURL in
            let store = TaskStore(databaseURL: databaseURL)
            let task = store.add(
                direction: "Quality",
                title: "Verify version 1.9",
                notes: "Accessibility pass",
                estimatedMinutes: 45,
                priority: .urgent,
                dueAt: Date().addingTimeInterval(-600),
                reminderEnabled: false,
                subtasks: [Subtask(title: "Run VoiceOver audit")]
            )

            XCTAssertEqual(store.tasks(for: .today, searchText: "VoiceOver").map(\.id), [task.id])
            XCTAssertEqual(
                store.tasks(for: .inbox, priorityFilter: .urgent, dateFilter: .overdue).map(\.id),
                [task.id]
            )

            let subtaskID = try XCTUnwrap(task.subtasks.first?.id)
            store.toggleSubtask(taskID: task.id, subtaskID: subtaskID)
            let persisted = TaskStore(databaseURL: databaseURL).tasks.first
            XCTAssertTrue(persisted?.subtasks.first?.isCompleted == true)
        }
    }

    @MainActor
    func testTrashUndoAndSafeBackupRestore() throws {
        try withTemporaryDatabase { databaseURL in
            let store = TaskStore(databaseURL: databaseURL)
            let focus = FocusStore(databaseURL: databaseURL)
            let first = store.add(
                direction: "Safety",
                title: "Keep this task",
                estimatedMinutes: 20,
                dueAt: nil,
                reminderEnabled: false
            )
            store.delete(first)
            XCTAssertTrue(store.activeTasks.isEmpty)
            XCTAssertEqual(store.trashedTasks.first?.id, first.id)
            XCTAssertEqual(store.undoLastDelete()?.id, first.id)

            _ = store.add(
                direction: "Safety",
                title: "Second task",
                estimatedMinutes: 20,
                dueAt: nil,
                reminderEnabled: false
            )
            let database = try TaskDatabase(url: databaseURL)
            let backup = try XCTUnwrap(database.listBackups().first { $0.isValid && $0.taskCount == 1 })
            try store.restoreBackup(backup, focusStore: focus)
            XCTAssertEqual(store.activeTasks.map(\.id), [first.id])
            XCTAssertTrue(try database.listBackups().contains { $0.url.lastPathComponent.contains("before-restore") })
        }
    }

    func testLegacyTaskJSONRemainsImportCompatible() throws {
        let json = """
        [{
          "direction": "Legacy",
          "title": "Preserve old JSON",
          "estimatedMinutes": 25,
          "reminderEnabled": false,
          "createdAt": "2026-01-01T00:00:00Z"
        }]
        """
        guard case let .legacyTasks(tasks) = try TaskDeckArchiveCodec.decode(Data(json.utf8)) else {
            return XCTFail("Expected a legacy task array")
        }
        XCTAssertEqual(tasks.count, 1)
        XCTAssertTrue(tasks[0].subtasks.isEmpty)
        XCTAssertNil(tasks[0].deletedAt)
    }

    @MainActor
    func testLanguageSelectionPersistsAndUpdatesCopy() throws {
        let suiteName = "TaskDeckLanguageXCTest-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let language = LanguageStore(defaults: defaults, syncsSharedDefaults: false)
        XCTAssertEqual(language.current, .simplifiedChinese)
        XCTAssertEqual(language.text("设置", "Settings"), "设置")

        language.current = .english
        XCTAssertEqual(language.text("设置", "Settings"), "Settings")
        XCTAssertEqual(
            defaults.string(forKey: LanguageStore.defaultsKey),
            AppLanguage.english.rawValue
        )

        let reopened = LanguageStore(defaults: defaults, syncsSharedDefaults: false)
        XCTAssertEqual(reopened.current, .english)
    }

    func testFocusWritesPreserveHistoryAndRejectStaleWindows() throws {
        try withTemporaryDatabase { databaseURL in
            let database = try TaskDatabase(url: databaseURL)
            let taskID = UUID()
            let laterTaskID = UUID()
            let start = Date(timeIntervalSince1970: 1_800_000_000)
            let previous = FocusSession(
                taskID: taskID,
                taskTitle: "Previous focus",
                direction: "Quality",
                startedAt: start.addingTimeInterval(-600),
                endedAt: start.addingTimeInterval(-300),
                durationSeconds: 300
            )
            let active = ActiveFocus(
                taskID: taskID,
                taskTitle: "Current focus",
                direction: "Quality",
                initiatedAt: start,
                estimatedMinutes: 25,
                runningSince: start,
                accumulatedSeconds: 0
            )
            try database.replaceFocus(sessions: [previous], active: active, reason: "test-seed")

            let finished = FocusSession(
                taskID: taskID,
                taskTitle: active.taskTitle,
                direction: active.direction,
                startedAt: start,
                endedAt: start.addingTimeInterval(120),
                durationSeconds: 120
            )
            XCTAssertTrue(try database.finishFocus(finished, matching: active))
            XCTAssertEqual(Set(try database.loadFocusSessions().map(\.id)), [previous.id, finished.id])

            let newer = ActiveFocus(
                taskID: laterTaskID,
                taskTitle: "Newer focus",
                direction: "Release",
                initiatedAt: start.addingTimeInterval(180),
                estimatedMinutes: 45,
                runningSince: start.addingTimeInterval(180),
                accumulatedSeconds: 0
            )
            XCTAssertTrue(try database.saveActiveFocus(newer, matching: nil, reason: "test-newer-start"))

            let staleFinish = FocusSession(
                taskID: taskID,
                taskTitle: active.taskTitle,
                direction: active.direction,
                startedAt: start,
                endedAt: start.addingTimeInterval(240),
                durationSeconds: 240
            )
            XCTAssertFalse(try database.finishFocus(staleFinish, matching: active))
            XCTAssertEqual(Set(try database.loadFocusSessions().map(\.id)), [previous.id, finished.id])
            XCTAssertEqual(try database.loadActiveFocus()?.taskID, laterTaskID)
        }
    }

    func testCrossMidnightFocusIsAllocatedToEachDay() throws {
        let midnight = Date(timeIntervalSince1970: 1_800_057_600)
        let session = FocusSession(
            taskID: UUID(),
            taskTitle: "Cross midnight",
            direction: "Quality",
            startedAt: midnight.addingTimeInterval(-600),
            endedAt: midnight.addingTimeInterval(600),
            durationSeconds: 1_200
        )
        let previousDay = DateInterval(
            start: midnight.addingTimeInterval(-86_400),
            end: midnight
        )
        let nextDay = DateInterval(
            start: midnight,
            end: midnight.addingTimeInterval(86_400)
        )

        XCTAssertEqual(session.seconds(in: previousDay), 600)
        XCTAssertEqual(session.seconds(in: nextDay), 600)
        XCTAssertEqual(session.seconds(in: previousDay) + session.seconds(in: nextDay), session.durationSeconds)
        XCTAssertEqual(session.clipped(to: previousDay)?.endedAt, midnight)
        XCTAssertEqual(session.clipped(to: nextDay)?.startedAt, midnight)
    }

    @MainActor
    func testPausedFocusCanSwitchTasksAndKeepSeparateSegments() throws {
        try withTemporaryDatabase { databaseURL in
            let tasks = TaskStore(databaseURL: databaseURL)
            let focus = FocusStore(databaseURL: databaseURL)
            let first = tasks.add(
                direction: "Build",
                title: "First task",
                estimatedMinutes: 25,
                dueAt: nil,
                reminderEnabled: false
            )
            let second = tasks.add(
                direction: "Review",
                title: "Second task",
                estimatedMinutes: 45,
                dueAt: nil,
                reminderEnabled: false
            )
            let start = Date(timeIntervalSince1970: 1_800_000_000)

            XCTAssertTrue(focus.beginOrToggle(first, now: start))
            focus.pause(now: start.addingTimeInterval(600))
            XCTAssertTrue(focus.active?.isPaused == true)
            XCTAssertEqual(focus.seconds(for: first.id), 600)

            XCTAssertTrue(focus.beginOrToggle(second, now: start.addingTimeInterval(900)))
            XCTAssertEqual(focus.active?.taskID, second.id)
            XCTAssertFalse(focus.active?.isPaused == true)
            focus.pause(now: start.addingTimeInterval(1_200))
            XCTAssertEqual(focus.seconds(for: second.id), 300)

            var edited = second
            edited.title = "Updated while focused"
            edited.estimatedMinutes = 120
            let saved = try XCTUnwrap(tasks.update(edited))
            focus.updateActiveTaskDetails(from: saved)
            XCTAssertEqual(focus.active?.taskTitle, edited.title)
            XCTAssertEqual(focus.active?.estimatedMinutes, 120)

            _ = focus.finish(now: start.addingTimeInterval(1_300))
            XCTAssertNil(focus.active)
            let reopened = FocusStore(databaseURL: databaseURL)
            XCTAssertEqual(reopened.seconds(for: first.id), 600)
            XCTAssertEqual(reopened.seconds(for: second.id), 300)

            XCTAssertTrue(reopened.beginOrToggle(first, now: start.addingTimeInterval(2_000)))
            reopened.pause(now: start.addingTimeInterval(2_060))
            XCTAssertEqual(reopened.seconds(for: first.id), 660)
            reopened.discardActive()
            XCTAssertNil(reopened.active)
            XCTAssertEqual(reopened.seconds(for: first.id), 600)
        }
    }

    @MainActor
    func testRestoringCompletedTaskPreservesTaskAndFocusHistory() throws {
        try withTemporaryDatabase { databaseURL in
            let store = TaskStore(databaseURL: databaseURL)
            let task = store.add(
                direction: "Recovery",
                title: "Keep every field",
                notes: "Important context",
                estimatedMinutes: 90,
                priority: .urgent,
                dueAt: Date(timeIntervalSince1970: 1_900_000_000),
                reminderEnabled: true,
                subtasks: [Subtask(title: "Preserve this step")]
            )
            let database = try TaskDatabase(url: databaseURL)
            let session = FocusSession(
                taskID: task.id,
                taskTitle: task.title,
                direction: task.direction,
                startedAt: Date(timeIntervalSince1970: 1_800_000_000),
                endedAt: Date(timeIntervalSince1970: 1_800_000_300),
                durationSeconds: 300
            )
            try database.replaceFocus(sessions: [session], active: nil, reason: "test-seed")

            _ = store.toggle(task)
            let completed = try XCTUnwrap(store.tasks.first)
            XCTAssertTrue(completed.isCompleted)
            _ = store.toggle(completed)

            let restored = try XCTUnwrap(TaskStore(databaseURL: databaseURL).tasks.first)
            XCTAssertFalse(restored.isCompleted)
            XCTAssertEqual(restored.id, task.id)
            XCTAssertEqual(restored.direction, task.direction)
            XCTAssertEqual(restored.title, task.title)
            XCTAssertEqual(restored.notes, task.notes)
            XCTAssertEqual(restored.estimatedMinutes, task.estimatedMinutes)
            XCTAssertEqual(restored.priority, task.priority)
            XCTAssertEqual(restored.dueAt, task.dueAt)
            XCTAssertEqual(restored.subtasks.map(\.id), task.subtasks.map(\.id))
            XCTAssertEqual(restored.subtasks.map(\.title), task.subtasks.map(\.title))
            XCTAssertEqual(restored.subtasks.map(\.completedAt), task.subtasks.map(\.completedAt))
            XCTAssertEqual(try database.loadFocusSessions(), [session])
        }
    }

    func testEstimatedDurationIsClampedToSixtyHours() {
        let tooLong = TaskItem(direction: "", title: "Long", estimatedMinutes: 4_000)
        let tooShort = TaskItem(direction: "", title: "Short", estimatedMinutes: 0)
        XCTAssertEqual(tooLong.estimatedMinutes, 3_600)
        XCTAssertEqual(tooShort.estimatedMinutes, 1)
    }

    private func withTemporaryDatabase(
        _ body: (URL) throws -> Void
    ) throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("TaskDeckXCTest-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try body(root.appendingPathComponent("taskdeck.sqlite3"))
    }
}
