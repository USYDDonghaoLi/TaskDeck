import Foundation

enum TaskDeckShared {
    static let developmentAppGroupIdentifier = "group.local.taskdeck.shared"
    static var appGroupIdentifier: String {
        guard
            let configured = Bundle.main.object(forInfoDictionaryKey: "TaskDeckAppGroupIdentifier") as? String,
            !configured.isEmpty,
            !configured.contains("$(")
        else { return developmentAppGroupIdentifier }
        return configured
    }
    static let widgetKind = "local.taskdeck.macos.widget.today"
    static let changeNotification = Notification.Name("local.taskdeck.tasks.changed")
    static let relativeDatabasePath = "TaskDeck/taskdeck.sqlite3"
    static let legacyRelativeTaskPath = "TaskDeck/tasks.json"
    private static let taskMigrationKey = "legacy_tasks_to_sqlite_v1"
    private static let focusMigrationKey = "legacy_focus_to_sqlite_v1"
    private static let sharedDatabaseMigrationKey = "previous_app_group_sqlite_v1"
    private static let legacyAppGroupIdentifiers = [developmentAppGroupIdentifier]

    static func groupRoot(fileManager: FileManager = .default) -> URL {
        if let container = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) {
            return container
        }

        // Ad-hoc personal builds don't have a provisioning profile. The main
        // application can still use this conventional path; a system Widget
        // requires a provisioned App Group and Apple Development signature.
        return fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Group Containers", isDirectory: true)
            .appendingPathComponent(appGroupIdentifier, isDirectory: true)
    }

    static func groupRoot(
        for identifier: String,
        fileManager: FileManager = .default
    ) -> URL {
        if identifier == appGroupIdentifier,
           let container = fileManager.containerURL(
               forSecurityApplicationGroupIdentifier: identifier
           ) {
            return container
        }
        return fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Group Containers", isDirectory: true)
            .appendingPathComponent(identifier, isDirectory: true)
    }

    static func databaseURL(groupRoot: URL? = nil) -> URL {
        (groupRoot ?? self.groupRoot()).appendingPathComponent(relativeDatabasePath)
    }

    static func legacyTaskFileURL(groupRoot: URL? = nil) -> URL {
        (groupRoot ?? self.groupRoot()).appendingPathComponent(legacyRelativeTaskPath)
    }

    static func legacyApplicationSupportDirectory(fileManager: FileManager = .default) -> URL {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("TaskDeck", isDirectory: true)
    }

    static func taskDatabase(
        at databaseURL: URL? = nil,
        legacyTaskURL: URL? = nil,
        legacyDatabaseURL: URL? = nil,
        fileManager: FileManager = .default
    ) throws -> TaskDatabase {
        let database = try TaskDatabase(url: databaseURL ?? self.databaseURL(), fileManager: fileManager)
        if databaseURL == nil || legacyTaskURL != nil || legacyDatabaseURL != nil {
            try migratePreviousSharedDatabaseIfNeeded(
                into: database,
                explicitLegacyURL: legacyDatabaseURL,
                fileManager: fileManager
            )
            try migrateLegacyTasksIfNeeded(
                into: database,
                explicitLegacyURL: legacyTaskURL,
                fileManager: fileManager
            )
        }
        return database
    }

    static func loadTasks(from databaseURL: URL? = nil) throws -> [TaskItem] {
        try TaskDatabase(url: databaseURL ?? self.databaseURL()).loadTasks()
    }

    static func saveTasks(_ tasks: [TaskItem], to databaseURL: URL? = nil) throws {
        try TaskDatabase(url: databaseURL ?? self.databaseURL())
            .replaceTasks(tasks, reason: "shared-task-save")
    }

    @discardableResult
    static func toggleTask(
        id: UUID,
        at databaseURL: URL? = nil,
        now: Date = Date(),
        calendar: Calendar = .current
    ) throws -> Bool {
        let database = try TaskDatabase(url: databaseURL ?? self.databaseURL())
        let changed = try database.mutateTasks(reason: "widget-toggle") { tasks in
            guard let index = tasks.firstIndex(where: { $0.id == id && !$0.isDeleted }) else { return false }

            if tasks[index].completedAt == nil {
                tasks[index].completedAt = now
                let completed = tasks[index]
                if completed.recurrence != .none,
                   completed.generatedNextTaskID == nil,
                   let nextDueAt = nextOccurrence(
                       after: completed.dueAt,
                       recurrence: completed.recurrence,
                       calendar: calendar
                   ) {
                    let nextTask = TaskItem(
                        direction: completed.direction,
                        title: completed.title,
                        notes: completed.notes,
                        estimatedMinutes: completed.estimatedMinutes,
                        priority: completed.priority,
                        dueAt: nextDueAt,
                        reminderEnabled: completed.reminderEnabled,
                        recurrence: completed.recurrence,
                        subtasks: completed.subtasks.enumerated().map { position, subtask in
                            Subtask(title: subtask.title, position: position)
                        }
                    )
                    tasks[index].generatedNextTaskID = nextTask.id
                    tasks.append(nextTask)
                }
            } else {
                tasks[index].completedAt = nil
            }
            return true
        }

        if changed {
            DistributedNotificationCenter.default().postNotificationName(
                changeNotification,
                object: nil
            )
        }
        return changed
    }

    static func migrateLegacyFocusIfNeeded(
        into database: TaskDatabase,
        legacyDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) throws {
        guard !(try database.hasMigrationMarker(focusMigrationKey)) else { return }
        if try database.hasFocusData() {
            try database.markMigration(focusMigrationKey)
            return
        }
        let directory = legacyDirectory ?? legacyApplicationSupportDirectory(fileManager: fileManager)
        let sessionsURL = directory.appendingPathComponent("focus-sessions.json")
        let runtimeURL = directory.appendingPathComponent("focus-runtime.json")
        guard fileManager.fileExists(atPath: sessionsURL.path)
            || fileManager.fileExists(atPath: runtimeURL.path) else {
            try database.markMigration(focusMigrationKey)
            return
        }

        let sessions: [FocusSession]
        if fileManager.fileExists(atPath: sessionsURL.path) {
            sessions = try TaskDeckArchiveCodec.decodeLegacySessions(Data(contentsOf: sessionsURL))
            try preserveLegacyFile(sessionsURL, as: "focus-sessions-before-sqlite.json", database: database)
        } else {
            sessions = []
        }

        let active: ActiveFocus?
        if fileManager.fileExists(atPath: runtimeURL.path) {
            active = try TaskDeckArchiveCodec.decodeLegacyRuntime(Data(contentsOf: runtimeURL))
            try preserveLegacyFile(runtimeURL, as: "focus-runtime-before-sqlite.json", database: database)
        } else {
            active = nil
        }
        try database.replaceFocus(sessions: sessions, active: active, reason: "focus-json-migration")
        try database.markMigration(focusMigrationKey)
    }

    static func storedLanguage() -> AppLanguage {
        let current = UserDefaults(suiteName: appGroupIdentifier)?
            .string(forKey: LanguageStore.defaultsKey)
        let legacy = legacyAppGroupIdentifiers
            .filter { $0 != appGroupIdentifier }
            .lazy
            .compactMap {
                UserDefaults(suiteName: $0)?.string(forKey: LanguageStore.defaultsKey)
            }
            .first
        let raw = current ?? legacy
        return raw.flatMap(AppLanguage.init(rawValue:)) ?? .simplifiedChinese
    }

    static func storeLanguage(_ language: AppLanguage) {
        UserDefaults(suiteName: appGroupIdentifier)?
            .set(language.rawValue, forKey: LanguageStore.defaultsKey)
    }

    private static func migrateLegacyTasksIfNeeded(
        into database: TaskDatabase,
        explicitLegacyURL: URL?,
        fileManager: FileManager
    ) throws {
        guard !(try database.hasMigrationMarker(taskMigrationKey)) else { return }
        if try database.taskCount() > 0 {
            try database.markMigration(taskMigrationKey)
            return
        }

        let candidates: [URL]
        if let explicitLegacyURL {
            candidates = [explicitLegacyURL]
        } else {
            candidates = [legacyTaskFileURL()]
                + legacyAppGroupIdentifiers
                    .filter { $0 != appGroupIdentifier }
                    .map {
                        groupRoot(for: $0, fileManager: fileManager)
                            .appendingPathComponent(legacyRelativeTaskPath)
                    }
                + [legacyApplicationSupportDirectory(fileManager: fileManager)
                    .appendingPathComponent("tasks.json")]
        }

        guard let source = candidates.first(where: { fileManager.fileExists(atPath: $0.path) }) else {
            try database.markMigration(taskMigrationKey)
            return
        }
        let data = try Data(contentsOf: source)
        let tasks = try TaskDeckArchiveCodec.decodeLegacyTasks(data)
        try preserveLegacyFile(source, as: "tasks-before-sqlite.json", database: database)
        try database.replaceTasks(tasks, reason: "task-json-migration")
        try database.markMigration(taskMigrationKey)
    }

    private static func migratePreviousSharedDatabaseIfNeeded(
        into database: TaskDatabase,
        explicitLegacyURL: URL?,
        fileManager: FileManager
    ) throws {
        guard !(try database.hasMigrationMarker(sharedDatabaseMigrationKey)) else { return }
        let taskCount = try database.taskCount()
        let hasFocusData = try database.hasFocusData()
        if taskCount > 0 || hasFocusData {
            try database.markMigration(sharedDatabaseMigrationKey)
            return
        }

        let candidates: [URL]
        if let explicitLegacyURL {
            candidates = [explicitLegacyURL]
        } else {
            candidates = legacyAppGroupIdentifiers
                .filter { $0 != appGroupIdentifier }
                .map {
                    groupRoot(for: $0, fileManager: fileManager)
                        .appendingPathComponent(relativeDatabasePath)
                }
        }
        let target = database.url.standardizedFileURL
        guard let source = candidates.first(where: {
            $0.standardizedFileURL != target && fileManager.fileExists(atPath: $0.path)
        }) else {
            try database.markMigration(sharedDatabaseMigrationKey)
            return
        }

        try preserveLegacyFile(
            source,
            as: "taskdeck-before-app-group-migration.sqlite3",
            database: database,
            fileManager: fileManager
        )
        let legacyDatabase = try TaskDatabase(
            url: source,
            readOnly: true,
            fileManager: fileManager
        )
        try database.replaceAll(
            tasks: legacyDatabase.loadTasks(),
            sessions: legacyDatabase.loadFocusSessions(),
            active: legacyDatabase.loadActiveFocus(),
            reason: "app-group-database-migration"
        )
        try database.markMigration(sharedDatabaseMigrationKey)
        try database.markMigration(taskMigrationKey)
        try database.markMigration(focusMigrationKey)
    }

    private static func preserveLegacyFile(
        _ source: URL,
        as name: String,
        database: TaskDatabase,
        fileManager: FileManager = .default
    ) throws {
        let directory = database.url.deletingLastPathComponent()
            .appendingPathComponent("Backups/Legacy", isDirectory: true)
        let destination = directory.appendingPathComponent(name)
        guard !fileManager.fileExists(atPath: destination.path) else { return }
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try fileManager.copyItem(at: source, to: destination)
    }

    private static func nextOccurrence(
        after date: Date?,
        recurrence: TaskRecurrence,
        calendar: Calendar
    ) -> Date? {
        guard let date else { return nil }
        switch recurrence {
        case .none:
            return nil
        case .daily:
            return calendar.date(byAdding: .day, value: 1, to: date)
        case .weekdays:
            var candidate = calendar.date(byAdding: .day, value: 1, to: date)
            while let value = candidate {
                let weekday = calendar.component(.weekday, from: value)
                if weekday != 1 && weekday != 7 { return value }
                candidate = calendar.date(byAdding: .day, value: 1, to: value)
            }
            return nil
        case .weekly:
            return calendar.date(byAdding: .weekOfYear, value: 1, to: date)
        case .monthly:
            return calendar.date(byAdding: .month, value: 1, to: date)
        }
    }
}
