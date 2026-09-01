import Foundation
import SQLite3

struct TaskDatabaseError: LocalizedError {
    let operation: String
    let message: String

    var errorDescription: String? { "\(operation): \(message)" }
}

struct DatabaseBackupInfo: Identifiable, Equatable, Sendable {
    let url: URL
    let createdAt: Date
    let size: Int64
    let taskCount: Int?
    let focusSessionCount: Int?
    let validationError: String?

    var id: URL { url }
    var isValid: Bool { validationError == nil }
}

final class TaskDatabase {
    let url: URL
    let backupDirectory: URL
    let wasCreated: Bool

    private let fileManager: FileManager
    private let isReadOnly: Bool
    private let backupLimit = 30
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(
        url: URL,
        backupDirectory: URL? = nil,
        readOnly: Bool = false,
        fileManager: FileManager = .default
    ) throws {
        self.url = url
        self.backupDirectory = backupDirectory
            ?? url.deletingLastPathComponent().appendingPathComponent("Backups/Database", isDirectory: true)
        self.fileManager = fileManager
        isReadOnly = readOnly
        wasCreated = !fileManager.fileExists(atPath: url.path)

        if readOnly {
            guard !wasCreated else {
                throw TaskDatabaseError(operation: "Open SQLite", message: "Read-only database does not exist")
            }
            try withConnection { database in
                try configure(database)
            }
            return
        }

        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try withConnection { database in
            try configure(database)
            try createSchema(database)
            try migrateSchema(database)
        }
    }

    func loadTasks() throws -> [TaskItem] {
        try withConnection { database in
            try configure(database)
            return try readTasks(database)
        }
    }

    func taskCount() throws -> Int {
        try withConnection { database in
            try configure(database)
            return try scalarInt(database, sql: "SELECT COUNT(*) FROM tasks")
        }
    }

    func focusSessionCount() throws -> Int {
        try withConnection { database in
            try configure(database)
            return try scalarInt(database, sql: "SELECT COUNT(*) FROM focus_sessions")
        }
    }

    func listBackups() throws -> [DatabaseBackupInfo] {
        guard fileManager.fileExists(atPath: backupDirectory.path) else { return [] }
        let urls = try fileManager.contentsOfDirectory(
            at: backupDirectory,
            includingPropertiesForKeys: [.creationDateKey, .contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )
        return urls
            .filter { $0.pathExtension == "sqlite3" }
            .map { backupInfo(for: $0) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func restoreBackup(at backupURL: URL) throws {
        try requireWritable()
        let candidate = backupURL.standardizedFileURL
        let root = backupDirectory.standardizedFileURL
        guard candidate.deletingLastPathComponent() == root,
              candidate.pathExtension == "sqlite3",
              fileManager.fileExists(atPath: candidate.path) else {
            throw TaskDatabaseError(operation: "Restore backup", message: "The selected file is not a TaskDeck database backup")
        }
        try validateDatabase(at: candidate)

        try withConnection { database in
            try configure(database)
            try createBackup(from: database, reason: "before-restore")
        }

        let temporaryURL = url.deletingLastPathComponent()
            .appendingPathComponent("TaskDeck-restore-\(UUID().uuidString).sqlite3")
        defer { try? fileManager.removeItem(at: temporaryURL) }
        try copyDatabase(from: candidate, to: temporaryURL)

        _ = try TaskDatabase(
            url: temporaryURL,
            backupDirectory: backupDirectory,
            fileManager: fileManager
        )
        try validateDatabase(at: temporaryURL)

        _ = try fileManager.replaceItemAt(
            url,
            withItemAt: temporaryURL,
            backupItemName: nil,
            options: [.usingNewMetadataOnly]
        )
        try withConnection { database in
            try configure(database)
            try createSchema(database)
            try migrateSchema(database)
        }
    }

    func hasMigrationMarker(_ key: String) throws -> Bool {
        try withConnection { database in
            try configure(database)
            let statement = try prepare(database, sql: "SELECT COUNT(*) FROM metadata WHERE key = ?")
            defer { sqlite3_finalize(statement) }
            try bind(key, to: statement, at: 1, database: database)
            guard sqlite3_step(statement) == SQLITE_ROW else {
                throw TaskDatabaseError(operation: "Read SQLite", message: String(cString: sqlite3_errmsg(database)))
            }
            return sqlite3_column_int(statement, 0) > 0
        }
    }

    func markMigration(_ key: String) throws {
        try modify(reason: "migration-marker") { database in
            let statement = try prepare(database, sql: "INSERT OR REPLACE INTO metadata (key, value) VALUES (?, '1')")
            defer { sqlite3_finalize(statement) }
            try bind(key, to: statement, at: 1, database: database)
            try stepDone(database, statement: statement)
        }
    }

    func replaceTasks(_ tasks: [TaskItem], reason: String = "tasks") throws {
        try requireWritable()
        try modify(reason: reason) { database in
            try syncTasks(tasks, in: database, replacingAll: false)
        }
    }

    @discardableResult
    func mutateTasks(
        reason: String,
        _ mutation: (inout [TaskItem]) throws -> Bool
    ) throws -> Bool {
        try requireWritable()
        return try withConnection { database in
            try configure(database)
            try createBackup(from: database, reason: reason)
            try execute(database, sql: "BEGIN IMMEDIATE TRANSACTION")
            do {
                var tasks = try readTasks(database)
                let changed = try mutation(&tasks)
                if changed {
                    try syncTasks(tasks, in: database, replacingAll: false)
                }
                try execute(database, sql: "COMMIT")
                return changed
            } catch {
                try? execute(database, sql: "ROLLBACK")
                throw error
            }
        }
    }

    func loadFocusSessions() throws -> [FocusSession] {
        try withConnection { database in
            try configure(database)
            return try readFocusSessions(database)
        }
    }

    func loadActiveFocus() throws -> ActiveFocus? {
        try withConnection { database in
            try configure(database)
            return try readActiveFocus(database)
        }
    }

    func hasFocusData() throws -> Bool {
        try withConnection { database in
            try configure(database)
            let sessionCount = try scalarInt(database, sql: "SELECT COUNT(*) FROM focus_sessions")
            let runtimeCount = try scalarInt(database, sql: "SELECT COUNT(*) FROM focus_runtime")
            return sessionCount > 0 || runtimeCount > 0
        }
    }

    func replaceFocus(
        sessions: [FocusSession],
        active: ActiveFocus?,
        reason: String = "focus"
    ) throws {
        try requireWritable()
        try modify(reason: reason) { database in
            try writeFocus(sessions: sessions, active: active, in: database)
        }
    }

    @discardableResult
    func saveActiveFocus(
        _ active: ActiveFocus,
        matching expected: ActiveFocus?,
        reason: String
    ) throws -> Bool {
        try mutateFocus(reason: reason) { database in
            let persisted = try readActiveFocus(database)
            guard focusIdentityMatches(persisted, expected) else { return false }
            try writeActiveFocus(active, in: database)
            return true
        }
    }

    @discardableResult
    func finishFocus(
        _ session: FocusSession,
        matching expected: ActiveFocus,
        reason: String = "focus-finish"
    ) throws -> Bool {
        try mutateFocus(reason: reason) { database in
            guard focusIdentityMatches(try readActiveFocus(database), expected) else { return false }
            try insertFocusSession(session, in: database)
            try execute(database, sql: "DELETE FROM focus_runtime WHERE singleton_id = 1")
            return true
        }
    }

    @discardableResult
    func discardActiveFocus(
        matching expected: ActiveFocus,
        reason: String = "focus-discard"
    ) throws -> Bool {
        try mutateFocus(reason: reason) { database in
            guard focusIdentityMatches(try readActiveFocus(database), expected) else { return false }
            try execute(database, sql: "DELETE FROM focus_runtime WHERE singleton_id = 1")
            return true
        }
    }

    func replaceAll(
        tasks: [TaskItem],
        sessions: [FocusSession],
        active: ActiveFocus?,
        reason: String = "json-import"
    ) throws {
        try requireWritable()
        try modify(reason: reason) { database in
            try syncTasks(tasks, in: database, replacingAll: true)
            try writeFocus(sessions: sessions, active: active, in: database)
        }
    }

    private func modify(reason: String, changes: (OpaquePointer) throws -> Void) throws {
        try requireWritable()
        try withConnection { database in
            try configure(database)
            try createBackup(from: database, reason: reason)
            try execute(database, sql: "BEGIN IMMEDIATE TRANSACTION")
            do {
                try changes(database)
                try execute(database, sql: "COMMIT")
            } catch {
                try? execute(database, sql: "ROLLBACK")
                throw error
            }
        }
    }

    private func mutateFocus(
        reason: String,
        changes: (OpaquePointer) throws -> Bool
    ) throws -> Bool {
        try requireWritable()
        return try withConnection { database in
            try configure(database)
            try createBackup(from: database, reason: reason)
            try execute(database, sql: "BEGIN IMMEDIATE TRANSACTION")
            do {
                let changed = try changes(database)
                try execute(database, sql: "COMMIT")
                return changed
            } catch {
                try? execute(database, sql: "ROLLBACK")
                throw error
            }
        }
    }

    private func withConnection<T>(_ body: (OpaquePointer) throws -> T) throws -> T {
        var database: OpaquePointer?
        let flags = isReadOnly
            ? SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
            : SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(url.path, &database, flags, nil) == SQLITE_OK, let database else {
            let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "Could not open database"
            if let database { sqlite3_close(database) }
            throw TaskDatabaseError(operation: "Open SQLite", message: message)
        }
        defer { sqlite3_close(database) }
        sqlite3_busy_timeout(database, 5_000)
        return try body(database)
    }

    private func configure(_ database: OpaquePointer) throws {
        try execute(database, sql: "PRAGMA foreign_keys = ON")
        if !isReadOnly {
            try execute(database, sql: "PRAGMA journal_mode = DELETE")
            try execute(database, sql: "PRAGMA synchronous = FULL")
        }
    }

    private func requireWritable() throws {
        guard !isReadOnly else {
            throw TaskDatabaseError(operation: "Write SQLite", message: "Database was opened read-only")
        }
    }

    private func createSchema(_ database: OpaquePointer) throws {
        try execute(database, sql: """
        CREATE TABLE IF NOT EXISTS tasks (
            id TEXT PRIMARY KEY NOT NULL,
            direction TEXT NOT NULL,
            title TEXT NOT NULL,
            notes TEXT NOT NULL,
            estimated_minutes INTEGER NOT NULL,
            priority TEXT NOT NULL,
            due_at REAL,
            reminder_enabled INTEGER NOT NULL,
            recurrence TEXT NOT NULL,
            created_at REAL NOT NULL,
            completed_at REAL,
            generated_next_task_id TEXT,
            deleted_at REAL
        );
        CREATE INDEX IF NOT EXISTS tasks_due_at_idx ON tasks(due_at);
        CREATE INDEX IF NOT EXISTS tasks_completed_at_idx ON tasks(completed_at);
        CREATE INDEX IF NOT EXISTS tasks_direction_idx ON tasks(direction);

        CREATE TABLE IF NOT EXISTS metadata (
            key TEXT PRIMARY KEY NOT NULL,
            value TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS subtasks (
            id TEXT PRIMARY KEY NOT NULL,
            task_id TEXT NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
            title TEXT NOT NULL,
            position INTEGER NOT NULL DEFAULT 0,
            created_at REAL NOT NULL,
            completed_at REAL
        );
        CREATE INDEX IF NOT EXISTS subtasks_task_id_idx ON subtasks(task_id, position);

        CREATE TABLE IF NOT EXISTS focus_sessions (
            id TEXT PRIMARY KEY NOT NULL,
            task_id TEXT NOT NULL,
            task_title TEXT NOT NULL,
            direction TEXT NOT NULL,
            started_at REAL NOT NULL,
            ended_at REAL NOT NULL,
            duration_seconds INTEGER NOT NULL
        );
        CREATE INDEX IF NOT EXISTS focus_sessions_task_idx ON focus_sessions(task_id);
        CREATE INDEX IF NOT EXISTS focus_sessions_ended_idx ON focus_sessions(ended_at);

        CREATE TABLE IF NOT EXISTS focus_runtime (
            singleton_id INTEGER PRIMARY KEY CHECK(singleton_id = 1),
            task_id TEXT NOT NULL,
            task_title TEXT NOT NULL,
            direction TEXT NOT NULL,
            initiated_at REAL NOT NULL,
            estimated_minutes INTEGER NOT NULL,
            running_since REAL,
            accumulated_seconds REAL NOT NULL
        );
        """)
    }

    private func migrateSchema(_ database: OpaquePointer) throws {
        if !(try columnExists("deleted_at", in: "tasks", database: database)) {
            try execute(database, sql: "ALTER TABLE tasks ADD COLUMN deleted_at REAL")
        }
        try execute(database, sql: "CREATE INDEX IF NOT EXISTS tasks_deleted_at_idx ON tasks(deleted_at)")
        try execute(database, sql: "PRAGMA user_version = 2")
    }

    private func readTasks(_ database: OpaquePointer) throws -> [TaskItem] {
        let deletedColumn = (try columnExists("deleted_at", in: "tasks", database: database))
            ? "deleted_at"
            : "NULL AS deleted_at"
        let sql = """
        SELECT id, direction, title, notes, estimated_minutes, priority,
               due_at, reminder_enabled, recurrence, created_at,
               completed_at, generated_next_task_id, \(deletedColumn)
        FROM tasks
        ORDER BY created_at ASC
        """
        let statement = try prepare(database, sql: sql)
        defer { sqlite3_finalize(statement) }

        var tasks: [TaskItem] = []
        var result = sqlite3_step(statement)
        while result == SQLITE_ROW {
            guard let id = UUID(uuidString: text(statement, 0)) else {
                throw TaskDatabaseError(operation: "Read SQLite", message: "A task has an invalid ID")
            }
            let dueAt = date(statement, 6)
            let completedAt = date(statement, 10)
            let generatedID = nullableText(statement, 11).flatMap(UUID.init(uuidString:))
            let deletedAt = date(statement, 12)
            tasks.append(TaskItem(
                id: id,
                direction: text(statement, 1),
                title: text(statement, 2),
                notes: text(statement, 3),
                estimatedMinutes: Int(sqlite3_column_int(statement, 4)),
                priority: TaskPriority(rawValue: text(statement, 5)) ?? .normal,
                dueAt: dueAt,
                reminderEnabled: sqlite3_column_int(statement, 7) != 0,
                recurrence: TaskRecurrence(rawValue: text(statement, 8)) ?? .none,
                createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 9)),
                completedAt: completedAt,
                generatedNextTaskID: generatedID,
                deletedAt: deletedAt
            ))
            result = sqlite3_step(statement)
        }
        guard result == SQLITE_DONE else {
            throw TaskDatabaseError(operation: "Read SQLite", message: String(cString: sqlite3_errmsg(database)))
        }
        let subtasks = try readSubtasks(database)
        for index in tasks.indices {
            tasks[index].subtasks = subtasks[tasks[index].id] ?? []
        }
        return tasks
    }

    private func syncTasks(
        _ tasks: [TaskItem],
        in database: OpaquePointer,
        replacingAll: Bool
    ) throws {
        if replacingAll {
            try execute(database, sql: "DELETE FROM tasks")
        } else {
            let incomingIDs = Set(tasks.map { $0.id.uuidString })
            let existing = try existingTaskIDs(database)
            for id in existing where !incomingIDs.contains(id) {
                let delete = try prepare(database, sql: "DELETE FROM tasks WHERE id = ?")
                defer { sqlite3_finalize(delete) }
                try bind(id, to: delete, at: 1, database: database)
                try stepDone(database, statement: delete)
            }
        }

        let sql = """
        INSERT INTO tasks (
            id, direction, title, notes, estimated_minutes, priority,
            due_at, reminder_enabled, recurrence, created_at,
            completed_at, generated_next_task_id, deleted_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            direction = excluded.direction,
            title = excluded.title,
            notes = excluded.notes,
            estimated_minutes = excluded.estimated_minutes,
            priority = excluded.priority,
            due_at = excluded.due_at,
            reminder_enabled = excluded.reminder_enabled,
            recurrence = excluded.recurrence,
            created_at = excluded.created_at,
            completed_at = excluded.completed_at,
            generated_next_task_id = excluded.generated_next_task_id,
            deleted_at = excluded.deleted_at
        """
        for task in tasks {
            let statement = try prepare(database, sql: sql)
            defer { sqlite3_finalize(statement) }
            try bind(task.id.uuidString, to: statement, at: 1, database: database)
            try bind(task.direction, to: statement, at: 2, database: database)
            try bind(task.title, to: statement, at: 3, database: database)
            try bind(task.notes, to: statement, at: 4, database: database)
            sqlite3_bind_int(statement, 5, Int32(task.estimatedMinutes))
            try bind(task.priority.rawValue, to: statement, at: 6, database: database)
            bind(task.dueAt, to: statement, at: 7)
            sqlite3_bind_int(statement, 8, task.reminderEnabled ? 1 : 0)
            try bind(task.recurrence.rawValue, to: statement, at: 9, database: database)
            sqlite3_bind_double(statement, 10, task.createdAt.timeIntervalSince1970)
            bind(task.completedAt, to: statement, at: 11)
            try bind(task.generatedNextTaskID?.uuidString, to: statement, at: 12, database: database)
            bind(task.deletedAt, to: statement, at: 13)
            try stepDone(database, statement: statement)
        }
        try syncSubtasks(for: tasks, in: database)
    }

    private func readSubtasks(_ database: OpaquePointer) throws -> [UUID: [Subtask]] {
        let statement = try prepare(database, sql: """
        SELECT id, task_id, title, position, created_at, completed_at
        FROM subtasks ORDER BY task_id, position, created_at
        """)
        defer { sqlite3_finalize(statement) }
        var grouped: [UUID: [Subtask]] = [:]
        var result = sqlite3_step(statement)
        while result == SQLITE_ROW {
            guard
                let id = UUID(uuidString: text(statement, 0)),
                let taskID = UUID(uuidString: text(statement, 1))
            else {
                throw TaskDatabaseError(operation: "Read SQLite", message: "A subtask has an invalid ID")
            }
            grouped[taskID, default: []].append(Subtask(
                id: id,
                title: text(statement, 2),
                position: Int(sqlite3_column_int(statement, 3)),
                createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 4)),
                completedAt: date(statement, 5)
            ))
            result = sqlite3_step(statement)
        }
        guard result == SQLITE_DONE else {
            throw TaskDatabaseError(operation: "Read SQLite", message: String(cString: sqlite3_errmsg(database)))
        }
        return grouped
    }

    private func syncSubtasks(for tasks: [TaskItem], in database: OpaquePointer) throws {
        try execute(database, sql: "DELETE FROM subtasks")
        let sql = """
        INSERT INTO subtasks (id, task_id, title, position, created_at, completed_at)
        VALUES (?, ?, ?, ?, ?, ?)
        """
        for task in tasks {
            for (position, subtask) in task.subtasks.enumerated() {
                let statement = try prepare(database, sql: sql)
                defer { sqlite3_finalize(statement) }
                try bind(subtask.id.uuidString, to: statement, at: 1, database: database)
                try bind(task.id.uuidString, to: statement, at: 2, database: database)
                try bind(subtask.title, to: statement, at: 3, database: database)
                sqlite3_bind_int(statement, 4, Int32(position))
                sqlite3_bind_double(statement, 5, subtask.createdAt.timeIntervalSince1970)
                bind(subtask.completedAt, to: statement, at: 6)
                try stepDone(database, statement: statement)
            }
        }
    }

    private func columnExists(
        _ column: String,
        in table: String,
        database: OpaquePointer
    ) throws -> Bool {
        let statement = try prepare(database, sql: "PRAGMA table_info(\(table))")
        defer { sqlite3_finalize(statement) }
        var result = sqlite3_step(statement)
        while result == SQLITE_ROW {
            if text(statement, 1) == column { return true }
            result = sqlite3_step(statement)
        }
        guard result == SQLITE_DONE else {
            throw TaskDatabaseError(operation: "Read SQLite schema", message: String(cString: sqlite3_errmsg(database)))
        }
        return false
    }

    private func existingTaskIDs(_ database: OpaquePointer) throws -> Set<String> {
        let statement = try prepare(database, sql: "SELECT id FROM tasks")
        defer { sqlite3_finalize(statement) }
        var result = Set<String>()
        var stepResult = sqlite3_step(statement)
        while stepResult == SQLITE_ROW {
            result.insert(text(statement, 0))
            stepResult = sqlite3_step(statement)
        }
        guard stepResult == SQLITE_DONE else {
            throw TaskDatabaseError(operation: "Read SQLite", message: String(cString: sqlite3_errmsg(database)))
        }
        return result
    }

    private func readFocusSessions(_ database: OpaquePointer) throws -> [FocusSession] {
        let statement = try prepare(database, sql: """
        SELECT id, task_id, task_title, direction, started_at, ended_at, duration_seconds
        FROM focus_sessions ORDER BY ended_at DESC
        """)
        defer { sqlite3_finalize(statement) }
        var sessions: [FocusSession] = []
        var result = sqlite3_step(statement)
        while result == SQLITE_ROW {
            guard
                let id = UUID(uuidString: text(statement, 0)),
                let taskID = UUID(uuidString: text(statement, 1))
            else {
                throw TaskDatabaseError(operation: "Read SQLite", message: "A focus session has an invalid ID")
            }
            sessions.append(FocusSession(
                id: id,
                taskID: taskID,
                taskTitle: text(statement, 2),
                direction: text(statement, 3),
                startedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 4)),
                endedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 5)),
                durationSeconds: Int(sqlite3_column_int(statement, 6))
            ))
            result = sqlite3_step(statement)
        }
        guard result == SQLITE_DONE else {
            throw TaskDatabaseError(operation: "Read SQLite", message: String(cString: sqlite3_errmsg(database)))
        }
        return sessions
    }

    private func readActiveFocus(_ database: OpaquePointer) throws -> ActiveFocus? {
        let statement = try prepare(database, sql: """
        SELECT task_id, task_title, direction, initiated_at, estimated_minutes,
               running_since, accumulated_seconds
        FROM focus_runtime WHERE singleton_id = 1
        """)
        defer { sqlite3_finalize(statement) }
        let result = sqlite3_step(statement)
        if result == SQLITE_DONE { return nil }
        guard result == SQLITE_ROW else {
            throw TaskDatabaseError(operation: "Read SQLite", message: String(cString: sqlite3_errmsg(database)))
        }
        guard let taskID = UUID(uuidString: text(statement, 0)) else {
            throw TaskDatabaseError(operation: "Read SQLite", message: "Active focus has an invalid task ID")
        }
        return ActiveFocus(
            taskID: taskID,
            taskTitle: text(statement, 1),
            direction: text(statement, 2),
            initiatedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 3)),
            estimatedMinutes: Int(sqlite3_column_int(statement, 4)),
            runningSince: date(statement, 5),
            accumulatedSeconds: sqlite3_column_double(statement, 6)
        )
    }

    private func writeFocus(
        sessions: [FocusSession],
        active: ActiveFocus?,
        in database: OpaquePointer
    ) throws {
        try execute(database, sql: "DELETE FROM focus_sessions; DELETE FROM focus_runtime;")
        for session in sessions {
            try insertFocusSession(session, in: database)
        }
        if let active {
            try writeActiveFocus(active, in: database)
        }
    }

    private func insertFocusSession(_ session: FocusSession, in database: OpaquePointer) throws {
        let statement = try prepare(database, sql: """
        INSERT INTO focus_sessions (
            id, task_id, task_title, direction, started_at, ended_at, duration_seconds
        ) VALUES (?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            task_id = excluded.task_id,
            task_title = excluded.task_title,
            direction = excluded.direction,
            started_at = excluded.started_at,
            ended_at = excluded.ended_at,
            duration_seconds = excluded.duration_seconds
        """)
        defer { sqlite3_finalize(statement) }
        try bind(session.id.uuidString, to: statement, at: 1, database: database)
        try bind(session.taskID.uuidString, to: statement, at: 2, database: database)
        try bind(session.taskTitle, to: statement, at: 3, database: database)
        try bind(session.direction, to: statement, at: 4, database: database)
        sqlite3_bind_double(statement, 5, session.startedAt.timeIntervalSince1970)
        sqlite3_bind_double(statement, 6, session.endedAt.timeIntervalSince1970)
        sqlite3_bind_int(statement, 7, Int32(session.durationSeconds))
        try stepDone(database, statement: statement)
    }

    private func writeActiveFocus(_ active: ActiveFocus, in database: OpaquePointer) throws {
        let statement = try prepare(database, sql: """
        INSERT INTO focus_runtime (
            singleton_id, task_id, task_title, direction, initiated_at,
            estimated_minutes, running_since, accumulated_seconds
        ) VALUES (1, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(singleton_id) DO UPDATE SET
            task_id = excluded.task_id,
            task_title = excluded.task_title,
            direction = excluded.direction,
            initiated_at = excluded.initiated_at,
            estimated_minutes = excluded.estimated_minutes,
            running_since = excluded.running_since,
            accumulated_seconds = excluded.accumulated_seconds
        """)
        defer { sqlite3_finalize(statement) }
        try bind(active.taskID.uuidString, to: statement, at: 1, database: database)
        try bind(active.taskTitle, to: statement, at: 2, database: database)
        try bind(active.direction, to: statement, at: 3, database: database)
        sqlite3_bind_double(statement, 4, active.initiatedAt.timeIntervalSince1970)
        sqlite3_bind_int(statement, 5, Int32(active.estimatedMinutes))
        bind(active.runningSince, to: statement, at: 6)
        sqlite3_bind_double(statement, 7, active.accumulatedSeconds)
        try stepDone(database, statement: statement)
    }

    private func focusIdentityMatches(_ persisted: ActiveFocus?, _ expected: ActiveFocus?) -> Bool {
        switch (persisted, expected) {
        case (nil, nil):
            return true
        case let (persisted?, expected?):
            return persisted.taskID == expected.taskID
                && abs(persisted.initiatedAt.timeIntervalSince1970
                    - expected.initiatedAt.timeIntervalSince1970) < 0.000_001
        default:
            return false
        }
    }

    private func createBackup(from source: OpaquePointer, reason: String) throws {
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.createDirectory(at: backupDirectory, withIntermediateDirectories: true)

        let timestamp = Self.backupDateFormatter.string(from: Date())
        let safeReason = reason.replacingOccurrences(
            of: "[^A-Za-z0-9_-]",
            with: "-",
            options: .regularExpression
        )
        let name = "TaskDeck-\(timestamp)-\(safeReason)-\(UUID().uuidString.prefix(8)).sqlite3"
        let destinationURL = backupDirectory.appendingPathComponent(name)
        var destination: OpaquePointer?
        guard sqlite3_open_v2(
            destinationURL.path,
            &destination,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX,
            nil
        ) == SQLITE_OK, let destination else {
            if let destination { sqlite3_close(destination) }
            throw TaskDatabaseError(operation: "Create backup", message: "Could not open backup database")
        }
        defer { sqlite3_close(destination) }

        guard let backup = sqlite3_backup_init(destination, "main", source, "main") else {
            throw TaskDatabaseError(
                operation: "Create backup",
                message: String(cString: sqlite3_errmsg(destination))
            )
        }
        let stepResult = sqlite3_backup_step(backup, -1)
        let finishResult = sqlite3_backup_finish(backup)
        guard stepResult == SQLITE_DONE, finishResult == SQLITE_OK else {
            try? fileManager.removeItem(at: destinationURL)
            throw TaskDatabaseError(operation: "Create backup", message: "SQLite backup failed")
        }
        try pruneBackups()
    }

    private func backupInfo(for backupURL: URL) -> DatabaseBackupInfo {
        let values = try? backupURL.resourceValues(forKeys: [
            .creationDateKey,
            .contentModificationDateKey,
            .fileSizeKey
        ])
        let createdAt = values?.creationDate
            ?? values?.contentModificationDate
            ?? .distantPast
        let size = Int64(values?.fileSize ?? 0)
        do {
            try validateDatabase(at: backupURL)
            let backup = try TaskDatabase(
                url: backupURL,
                backupDirectory: backupDirectory,
                readOnly: true,
                fileManager: fileManager
            )
            return DatabaseBackupInfo(
                url: backupURL,
                createdAt: createdAt,
                size: size,
                taskCount: try backup.taskCount(),
                focusSessionCount: try backup.focusSessionCount(),
                validationError: nil
            )
        } catch {
            return DatabaseBackupInfo(
                url: backupURL,
                createdAt: createdAt,
                size: size,
                taskCount: nil,
                focusSessionCount: nil,
                validationError: error.localizedDescription
            )
        }
    }

    private func validateDatabase(at databaseURL: URL) throws {
        var database: OpaquePointer?
        guard sqlite3_open_v2(
            databaseURL.path,
            &database,
            SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX,
            nil
        ) == SQLITE_OK, let database else {
            if let database { sqlite3_close(database) }
            throw TaskDatabaseError(operation: "Validate backup", message: "Could not open the database")
        }
        defer { sqlite3_close(database) }
        sqlite3_busy_timeout(database, 5_000)
        let statement = try prepare(database, sql: "PRAGMA integrity_check")
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW, text(statement, 0).lowercased() == "ok" else {
            throw TaskDatabaseError(operation: "Validate backup", message: "SQLite integrity check failed")
        }
        _ = try scalarInt(database, sql: "SELECT COUNT(*) FROM tasks")
        _ = try scalarInt(database, sql: "SELECT COUNT(*) FROM focus_sessions")
    }

    private func copyDatabase(from sourceURL: URL, to destinationURL: URL) throws {
        var source: OpaquePointer?
        var destination: OpaquePointer?
        guard sqlite3_open_v2(
            sourceURL.path,
            &source,
            SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX,
            nil
        ) == SQLITE_OK, let source else {
            if let source { sqlite3_close(source) }
            throw TaskDatabaseError(operation: "Restore backup", message: "Could not open the selected backup")
        }
        defer { sqlite3_close(source) }

        guard sqlite3_open_v2(
            destinationURL.path,
            &destination,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX,
            nil
        ) == SQLITE_OK, let destination else {
            if let destination { sqlite3_close(destination) }
            throw TaskDatabaseError(operation: "Restore backup", message: "Could not create the restore database")
        }
        defer { sqlite3_close(destination) }

        guard let backup = sqlite3_backup_init(destination, "main", source, "main") else {
            throw TaskDatabaseError(
                operation: "Restore backup",
                message: String(cString: sqlite3_errmsg(destination))
            )
        }
        let stepResult = sqlite3_backup_step(backup, -1)
        let finishResult = sqlite3_backup_finish(backup)
        guard stepResult == SQLITE_DONE, finishResult == SQLITE_OK else {
            throw TaskDatabaseError(operation: "Restore backup", message: "SQLite restore copy failed")
        }
    }

    private func pruneBackups() throws {
        let urls = try fileManager.contentsOfDirectory(
            at: backupDirectory,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        )
        let backups = urls.filter { $0.pathExtension == "sqlite3" }.sorted { left, right in
            let leftDate = (try? left.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            let rightDate = (try? right.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            return leftDate > rightDate
        }
        for expired in backups.dropFirst(backupLimit) {
            try fileManager.removeItem(at: expired)
        }
    }

    private func execute(_ database: OpaquePointer, sql: String) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(database, sql, nil, nil, &errorMessage) == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) }
                ?? String(cString: sqlite3_errmsg(database))
            sqlite3_free(errorMessage)
            throw TaskDatabaseError(operation: "Execute SQLite", message: message)
        }
    }

    private func prepare(_ database: OpaquePointer, sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw TaskDatabaseError(
                operation: "Prepare SQLite",
                message: String(cString: sqlite3_errmsg(database))
            )
        }
        return statement
    }

    private func scalarInt(_ database: OpaquePointer, sql: String) throws -> Int {
        let statement = try prepare(database, sql: sql)
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw TaskDatabaseError(operation: "Read SQLite", message: String(cString: sqlite3_errmsg(database)))
        }
        return Int(sqlite3_column_int(statement, 0))
    }

    private func stepDone(_ database: OpaquePointer, statement: OpaquePointer) throws {
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw TaskDatabaseError(operation: "Write SQLite", message: String(cString: sqlite3_errmsg(database)))
        }
    }

    private func bind(
        _ value: String?,
        to statement: OpaquePointer,
        at index: Int32,
        database: OpaquePointer
    ) throws {
        let result: Int32
        if let value {
            result = value.withCString {
                sqlite3_bind_text(statement, index, $0, -1, transient)
            }
        } else {
            result = sqlite3_bind_null(statement, index)
        }
        guard result == SQLITE_OK else {
            throw TaskDatabaseError(operation: "Bind SQLite", message: String(cString: sqlite3_errmsg(database)))
        }
    }

    private func bind(_ value: Date?, to statement: OpaquePointer, at index: Int32) {
        if let value {
            sqlite3_bind_double(statement, index, value.timeIntervalSince1970)
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    private func text(_ statement: OpaquePointer, _ index: Int32) -> String {
        guard let pointer = sqlite3_column_text(statement, index) else { return "" }
        return String(cString: pointer)
    }

    private func nullableText(_ statement: OpaquePointer, _ index: Int32) -> String? {
        sqlite3_column_type(statement, index) == SQLITE_NULL ? nil : text(statement, index)
    }

    private func date(_ statement: OpaquePointer, _ index: Int32) -> Date? {
        sqlite3_column_type(statement, index) == SQLITE_NULL
            ? nil
            : Date(timeIntervalSince1970: sqlite3_column_double(statement, index))
    }

    private static let backupDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        return formatter
    }()
}
