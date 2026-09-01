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
