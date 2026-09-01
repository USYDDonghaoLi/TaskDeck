import Foundation

struct FocusSession: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let taskID: UUID
    let taskTitle: String
    let direction: String
    let startedAt: Date
    let endedAt: Date
    let durationSeconds: Int

    init(
        id: UUID = UUID(),
        taskID: UUID,
        taskTitle: String,
        direction: String,
        startedAt: Date,
        endedAt: Date,
        durationSeconds: Int
    ) {
        self.id = id
        self.taskID = taskID
        self.taskTitle = taskTitle
        self.direction = direction
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.durationSeconds = max(1, durationSeconds)
    }
}

struct ActiveFocus: Codable, Equatable, Sendable {
    let taskID: UUID
    let taskTitle: String
    let direction: String
    let initiatedAt: Date
    let estimatedMinutes: Int
    var runningSince: Date?
    var accumulatedSeconds: TimeInterval

    var isPaused: Bool { runningSince == nil }
}

private struct FocusRuntimeState: Codable {
    var active: ActiveFocus?
}

@MainActor
final class FocusStore: ObservableObject {
    @Published private(set) var sessions: [FocusSession] = []
    @Published private(set) var active: ActiveFocus?

    private let sessionsURL: URL
    private let runtimeURL: URL
    private let calendar: Calendar
    private var sessionsLoadFailed = false

    init(baseDirectory: URL? = nil, calendar: Calendar = .current) {
        let directory = baseDirectory ?? Self.defaultDirectory()
        self.sessionsURL = directory.appendingPathComponent("focus-sessions.json")
        self.runtimeURL = directory.appendingPathComponent("focus-runtime.json")
        self.calendar = calendar
        load()
    }

    @discardableResult
    func beginOrToggle(_ task: TaskItem, now: Date = Date()) -> Bool {
        if var active {
            guard active.taskID == task.id else { return false }
            if let runningSince = active.runningSince {
                active.accumulatedSeconds += max(0, now.timeIntervalSince(runningSince))
                active.runningSince = nil
            } else {
                active.runningSince = now
            }
            self.active = active
            saveRuntime()
            return true
        }

        active = ActiveFocus(
            taskID: task.id,
            taskTitle: task.title,
            direction: task.normalizedDirection,
            initiatedAt: now,
            estimatedMinutes: task.estimatedMinutes,
            runningSince: now,
            accumulatedSeconds: 0
        )
        saveRuntime()
        return true
    }

    func pause(now: Date = Date()) {
        guard var active, let runningSince = active.runningSince else { return }
        active.accumulatedSeconds += max(0, now.timeIntervalSince(runningSince))
        active.runningSince = nil
        self.active = active
        saveRuntime()
    }

    func resume(now: Date = Date()) {
        guard var active, active.runningSince == nil else { return }
        active.runningSince = now
        self.active = active
        saveRuntime()
    }

    @discardableResult
    func finish(now: Date = Date()) -> FocusSession? {
        guard let active else { return nil }
        let seconds = Int(elapsed(for: active, at: now).rounded())
        let session = FocusSession(
            taskID: active.taskID,
            taskTitle: active.taskTitle,
            direction: active.direction,
            startedAt: active.initiatedAt,
            endedAt: now,
            durationSeconds: seconds
        )
        sessions.append(session)
        sessions.sort { $0.endedAt > $1.endedAt }
        self.active = nil
        saveSessions()
        saveRuntime()
        return session
    }

    func discardActive() {
        active = nil
        saveRuntime()
    }

    func elapsed(at date: Date = Date()) -> TimeInterval {
        guard let active else { return 0 }
        return elapsed(for: active, at: date)
    }

    func sessions(in interval: DateInterval) -> [FocusSession] {
        sessions.filter { interval.contains($0.endedAt) }.sorted { $0.endedAt > $1.endedAt }
    }

    func totalSeconds(in interval: DateInterval) -> Int {
        sessions(in: interval).reduce(0) { $0 + $1.durationSeconds }
    }

    func seconds(for taskID: UUID, in interval: DateInterval? = nil) -> Int {
        sessions.reduce(0) { result, session in
            guard session.taskID == taskID else { return result }
            if let interval, !interval.contains(session.endedAt) { return result }
            return result + session.durationSeconds
        }
    }

    func seconds(on date: Date) -> Int {
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        return totalSeconds(in: DateInterval(start: start, end: end))
    }

    private func elapsed(for active: ActiveFocus, at date: Date) -> TimeInterval {
        let runningSeconds = active.runningSince.map { max(0, date.timeIntervalSince($0)) } ?? 0
        return active.accumulatedSeconds + runningSeconds
    }

    private func load() {
        if FileManager.default.fileExists(atPath: sessionsURL.path) {
            do {
                sessions = try JSONDecoder.focus.decode([FocusSession].self, from: Data(contentsOf: sessionsURL))
                    .sorted { $0.endedAt > $1.endedAt }
            } catch {
                sessionsLoadFailed = true
                NSLog("TaskDeck could not load focus sessions: %@", error.localizedDescription)
            }
        }

        if FileManager.default.fileExists(atPath: runtimeURL.path) {
            do {
                active = try JSONDecoder.focus.decode(FocusRuntimeState.self, from: Data(contentsOf: runtimeURL)).active
            } catch {
                NSLog("TaskDeck could not restore active focus: %@", error.localizedDescription)
            }
        }
    }

    private func saveSessions() {
        guard !sessionsLoadFailed else { return }
        do {
            try prepareDirectory()
            let data = try JSONEncoder.focus.encode(sessions)
            try data.write(to: sessionsURL, options: .atomic)
        } catch {
            NSLog("TaskDeck could not save focus sessions: %@", error.localizedDescription)
        }
    }

    private func saveRuntime() {
        do {
            try prepareDirectory()
            let data = try JSONEncoder.focus.encode(FocusRuntimeState(active: active))
            try data.write(to: runtimeURL, options: .atomic)
        } catch {
            NSLog("TaskDeck could not save focus runtime: %@", error.localizedDescription)
        }
    }

    private func prepareDirectory() throws {
        try FileManager.default.createDirectory(at: sessionsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    }

    private static func defaultDirectory() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("TaskDeck", isDirectory: true)
    }
}

private extension JSONEncoder {
    static var focus: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var focus: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
