import Foundation

enum TaskDeckShared {
    static let appGroupIdentifier = "group.local.taskdeck.shared"
    static let widgetKind = "local.taskdeck.macos.widget.today"
    static let changeNotification = Notification.Name("local.taskdeck.tasks.changed")
    static let relativeTaskPath = "TaskDeck/tasks.json"

    static func groupRoot(fileManager: FileManager = .default) -> URL {
        if let container = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) {
            return container
        }

        // Ad-hoc personal builds don't have a provisioning profile. Keeping the
        // conventional Group Containers path makes the self-signed app and its
        // unsandboxed extension share the same data while the App Store build
        // automatically uses the provisioned container above.
        return fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Group Containers", isDirectory: true)
            .appendingPathComponent(appGroupIdentifier, isDirectory: true)
    }

    static func taskFileURL(groupRoot: URL? = nil) -> URL {
        (groupRoot ?? self.groupRoot()).appendingPathComponent(relativeTaskPath)
    }

    static func prepareTaskFile(
        legacyURL: URL,
        groupRoot: URL? = nil,
        fileManager: FileManager = .default
    ) -> URL {
        let sharedURL = taskFileURL(groupRoot: groupRoot)
        do {
            try fileManager.createDirectory(
                at: sharedURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if !fileManager.fileExists(atPath: sharedURL.path),
               fileManager.fileExists(atPath: legacyURL.path) {
                try fileManager.copyItem(at: legacyURL, to: sharedURL)
            }
        } catch {
            NSLog("TaskDeck could not prepare shared task storage: %@", error.localizedDescription)
            return legacyURL
        }
        return sharedURL
    }

    static func loadTasks(from url: URL? = nil) throws -> [TaskItem] {
        let data = try Data(contentsOf: url ?? taskFileURL())
        return try decoder.decode([TaskItem].self, from: data)
    }

    static func saveTasks(_ tasks: [TaskItem], to url: URL? = nil) throws {
        let destination = url ?? taskFileURL()
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try encoder.encode(tasks).write(to: destination, options: .atomic)
    }

    @discardableResult
    static func toggleTask(
        id: UUID,
        at url: URL? = nil,
        now: Date = Date(),
        calendar: Calendar = .current
    ) throws -> Bool {
        let destination = url ?? taskFileURL()
        var tasks = try loadTasks(from: destination)
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return false }

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
                    recurrence: completed.recurrence
                )
                tasks[index].generatedNextTaskID = nextTask.id
                tasks.append(nextTask)
            }
        } else {
            tasks[index].completedAt = nil
        }

        try saveTasks(tasks, to: destination)
        DistributedNotificationCenter.default().postNotificationName(
            changeNotification,
            object: nil
        )
        return true
    }

    static func storedLanguage() -> AppLanguage {
        let raw = UserDefaults(suiteName: appGroupIdentifier)?
            .string(forKey: LanguageStore.defaultsKey)
        return raw.flatMap(AppLanguage.init(rawValue:)) ?? .simplifiedChinese
    }

    static func storeLanguage(_ language: AppLanguage) {
        UserDefaults(suiteName: appGroupIdentifier)?
            .set(language.rawValue, forKey: LanguageStore.defaultsKey)
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

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
