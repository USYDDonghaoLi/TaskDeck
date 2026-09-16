import Combine
import CoreGraphics
import Foundation
import UserNotifications

@MainActor
final class NotificationManager: ObservableObject {
    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    init() {
        refreshStatus()
    }

    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] _, error in
            if let error {
                NSLog("TaskDeck notification permission failed: %@", error.localizedDescription)
            }
            Task { @MainActor in self?.refreshStatus() }
        }
    }

    func schedule(for task: TaskItem) {
        guard task.reminderEnabled, let date = task.dueAt, date > Date() else { return }

        let language = UserDefaults.standard.string(forKey: LanguageStore.defaultsKey)
            .flatMap(AppLanguage.init(rawValue:)) ?? .simplifiedChinese

        let content = UNMutableNotificationContent()
        content.title = "TASKDECK // \(task.displayDirection(in: language).uppercased())"
        content.body = task.title
        content.sound = .default

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: date
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(
            identifier: task.id.uuidString,
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                NSLog("TaskDeck could not schedule reminder: %@", error.localizedDescription)
            }
        }
    }

    func cancel(for task: TaskItem) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [task.id.uuidString])
    }

    func sendFocusRoundCompleted(taskTitle: String, breakMinutes: Int, language: AppLanguage) {
        let body = language == .simplifiedChinese
            ? "“\(taskTitle)”已完成一轮专注。\(breakMinutes > 0 ? "可以休息 \(breakMinutes) 分钟。" : "")"
            : "A focus round for “\(taskTitle)” is complete.\(breakMinutes > 0 ? " Take a \(breakMinutes)-minute break." : "")"
        sendImmediate(
            identifier: "taskdeck.pomodoro.focus.\(UUID().uuidString)",
            title: language == .simplifiedChinese ? "TASKDECK // 专注完成" : "TASKDECK // FOCUS COMPLETE",
            body: body
        )
    }

    func sendBreakCompleted(taskTitle: String, language: AppLanguage) {
        sendImmediate(
            identifier: "taskdeck.pomodoro.break.\(UUID().uuidString)",
            title: language == .simplifiedChinese ? "TASKDECK // 休息结束" : "TASKDECK // BREAK COMPLETE",
            body: language == .simplifiedChinese
                ? "准备好后继续“\(taskTitle)”。"
                : "Resume “\(taskTitle)” when you are ready."
        )
    }

    private func sendImmediate(identifier: String, title: String, body: String) {
        guard authorizationStatus == .authorized
            || authorizationStatus == .provisional else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        ) { error in
            if let error {
                NSLog("TaskDeck could not send focus notification: %@", error.localizedDescription)
            }
        }
    }

    private func refreshStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            let rawStatus = settings.authorizationStatus.rawValue
            Task { @MainActor in
                self?.authorizationStatus = UNAuthorizationStatus(rawValue: rawStatus) ?? .notDetermined
            }
        }
    }
}

struct PomodoroBreak: Identifiable, Equatable, Sendable {
    let id: UUID
    let taskID: UUID
    let taskTitle: String
    let startedAt: Date
    let endsAt: Date

    init(
        id: UUID = UUID(),
        taskID: UUID,
        taskTitle: String,
        startedAt: Date,
        endsAt: Date
    ) {
        self.id = id
        self.taskID = taskID
        self.taskTitle = taskTitle
        self.startedAt = startedAt
        self.endsAt = max(startedAt, endsAt)
    }

    func remainingSeconds(at date: Date) -> Int {
        max(0, Int(endsAt.timeIntervalSince(date).rounded(.up)))
    }
}

@MainActor
final class FocusExperienceController: ObservableObject {
    private enum DefaultsKey {
        static let pomodoroEnabled = "TaskDeck.focus.pomodoroEnabled"
        static let focusMinutes = "TaskDeck.focus.focusMinutes"
        static let breakMinutes = "TaskDeck.focus.breakMinutes"
        static let autoStartBreak = "TaskDeck.focus.autoStartBreak"
        static let idleDetectionEnabled = "TaskDeck.focus.idleDetectionEnabled"
        static let idleThresholdMinutes = "TaskDeck.focus.idleThresholdMinutes"
        static let recentTaskIDs = "TaskDeck.focus.recentTaskIDs"
    }

    @Published var pomodoroEnabled: Bool {
        didSet {
            defaults.set(pomodoroEnabled, forKey: DefaultsKey.pomodoroEnabled)
            if pomodoroEnabled, notifications.authorizationStatus == .notDetermined {
                notifications.requestAuthorization()
            }
            if !pomodoroEnabled { pomodoroBreak = nil }
            resetPomodoroBaseline()
        }
    }

    @Published var focusMinutes: Int {
        didSet {
            let normalized = min(180, max(1, focusMinutes))
            if normalized != focusMinutes {
                focusMinutes = normalized
                return
            }
            defaults.set(focusMinutes, forKey: DefaultsKey.focusMinutes)
            resetPomodoroBaseline()
        }
    }

    @Published var breakMinutes: Int {
        didSet {
            let normalized = min(60, max(1, breakMinutes))
            if normalized != breakMinutes {
                breakMinutes = normalized
                return
            }
            defaults.set(breakMinutes, forKey: DefaultsKey.breakMinutes)
        }
    }

    @Published var autoStartBreak: Bool {
        didSet { defaults.set(autoStartBreak, forKey: DefaultsKey.autoStartBreak) }
    }

    @Published var idleDetectionEnabled: Bool {
        didSet {
            defaults.set(idleDetectionEnabled, forKey: DefaultsKey.idleDetectionEnabled)
            if !idleDetectionEnabled { observedIdleStart = nil }
        }
    }

    @Published var idleThresholdMinutes: Int {
        didSet {
            let normalized = min(120, max(1, idleThresholdMinutes))
            if normalized != idleThresholdMinutes {
                idleThresholdMinutes = normalized
                return
            }
            defaults.set(idleThresholdMinutes, forKey: DefaultsKey.idleThresholdMinutes)
        }
    }

    @Published private(set) var recentTaskIDs: [UUID]
    @Published private(set) var pendingIdleReview: IdleFocusReview?
    @Published private(set) var pomodoroBreak: PomodoroBreak?
    @Published private(set) var roundMessage: String?

    private let focus: FocusStore
    private let notifications: NotificationManager
    private let language: LanguageStore
    private let defaults: UserDefaults
    private var cancellables: Set<AnyCancellable> = []
    private var observedIdleStart: Date?
    private var activeIdentity: String?
    private var lastNotifiedRound = 0
    private var roundMessageUntil: Date?
    private var breakCompletionNotified = false

    init(
        focus: FocusStore,
        notifications: NotificationManager,
        language: LanguageStore,
        defaults: UserDefaults = .standard,
        startsTimer: Bool = true
    ) {
        self.focus = focus
        self.notifications = notifications
        self.language = language
        self.defaults = defaults

        pomodoroEnabled = defaults.object(forKey: DefaultsKey.pomodoroEnabled) as? Bool ?? false
        focusMinutes = Self.savedInteger(defaults, key: DefaultsKey.focusMinutes, fallback: 25, range: 1...180)
        breakMinutes = Self.savedInteger(defaults, key: DefaultsKey.breakMinutes, fallback: 5, range: 1...60)
        autoStartBreak = defaults.object(forKey: DefaultsKey.autoStartBreak) as? Bool ?? false
        idleDetectionEnabled = defaults.object(forKey: DefaultsKey.idleDetectionEnabled) as? Bool ?? true
        idleThresholdMinutes = Self.savedInteger(defaults, key: DefaultsKey.idleThresholdMinutes, fallback: 5, range: 1...120)
        recentTaskIDs = (defaults.stringArray(forKey: DefaultsKey.recentTaskIDs) ?? [])
            .compactMap(UUID.init(uuidString:))

        synchronizeActiveFocus(focus.active)
        focus.$active
            .receive(on: RunLoop.main)
            .sink { [weak self] active in
                self?.synchronizeActiveFocus(active)
            }
            .store(in: &cancellables)

        if startsTimer {
            Timer.publish(every: 1, on: .main, in: .common)
                .autoconnect()
                .sink { [weak self] now in
                    guard let self else { return }
                    self.evaluate(now: now, idleSeconds: Self.systemIdleSeconds())
                }
                .store(in: &cancellables)
        }
    }

    func recordRecentTask(_ taskID: UUID) {
        recentTaskIDs.removeAll { $0 == taskID }
        recentTaskIDs.insert(taskID, at: 0)
        recentTaskIDs = Array(recentTaskIDs.prefix(8))
        defaults.set(recentTaskIDs.map(\.uuidString), forKey: DefaultsKey.recentTaskIDs)
    }

    func resolveIdleReview(include: Bool, now: Date = Date()) {
        guard let review = pendingIdleReview else { return }
        if include { _ = focus.includeIdleReview(review) }
        pendingIdleReview = nil
        observedIdleStart = nil
        focus.resume(now: now)
    }

    func finishBreakAndResume(now: Date = Date()) {
        pomodoroBreak = nil
        breakCompletionNotified = false
        focus.resume(now: now)
    }

    func evaluate(now: Date = Date(), idleSeconds: TimeInterval? = nil) {
        if let deadline = roundMessageUntil, now >= deadline {
            roundMessage = nil
            roundMessageUntil = nil
        }
        guard let active = focus.active else { return }

        if let currentBreak = pomodoroBreak {
            if now >= currentBreak.endsAt, !breakCompletionNotified {
                breakCompletionNotified = true
                roundMessage = language.text("休息结束，准备继续", "Break complete — ready to resume")
                notifications.sendBreakCompleted(taskTitle: currentBreak.taskTitle, language: language.current)
            }
            return
        }

        guard !active.isPaused else { return }
        let idle = idleSeconds ?? Self.systemIdleSeconds()
        if evaluateIdle(now: now, idleSeconds: idle) { return }
        evaluatePomodoro(now: now, active: active)
    }

    private func evaluateIdle(now: Date, idleSeconds: TimeInterval) -> Bool {
        guard idleDetectionEnabled, pendingIdleReview == nil else {
            return pendingIdleReview != nil
        }
        let threshold = TimeInterval(idleThresholdMinutes * 60)
        if idleSeconds >= threshold {
            if observedIdleStart == nil {
                observedIdleStart = now.addingTimeInterval(-idleSeconds)
            }
            return true
        }
        guard let idleStart = observedIdleStart else { return false }
        observedIdleStart = nil
        guard now.timeIntervalSince(idleStart) >= threshold else { return false }
        pendingIdleReview = focus.pauseForIdleReview(idleStartedAt: idleStart, now: now)
        return pendingIdleReview != nil
    }

    private func evaluatePomodoro(now: Date, active: ActiveFocus) {
        guard pomodoroEnabled else { return }
        let roundSeconds = max(60, focusMinutes * 60)
        let completedRounds = Int(focus.elapsed(at: now)) / roundSeconds
        guard completedRounds > lastNotifiedRound else { return }
        lastNotifiedRound = completedRounds
        roundMessage = language.text("一轮专注已完成", "Focus round complete")
        roundMessageUntil = now.addingTimeInterval(8)
        notifications.sendFocusRoundCompleted(
            taskTitle: active.taskTitle,
            breakMinutes: autoStartBreak ? breakMinutes : 0,
            language: language.current
        )
        guard autoStartBreak else { return }
        focus.pause(now: now)
        let breakStart = now
        pomodoroBreak = PomodoroBreak(
            taskID: active.taskID,
            taskTitle: active.taskTitle,
            startedAt: breakStart,
            endsAt: breakStart.addingTimeInterval(TimeInterval(breakMinutes * 60))
        )
        breakCompletionNotified = false
    }

    private func synchronizeActiveFocus(_ active: ActiveFocus?) {
        guard let active else {
            activeIdentity = nil
            observedIdleStart = nil
            pendingIdleReview = nil
            pomodoroBreak = nil
            lastNotifiedRound = 0
            return
        }
        let identity = "\(active.taskID.uuidString)-\(active.initiatedAt.timeIntervalSince1970)"
        if identity != activeIdentity {
            activeIdentity = identity
            recordRecentTask(active.taskID)
            observedIdleStart = nil
            pendingIdleReview = nil
            pomodoroBreak = nil
            breakCompletionNotified = false
            resetPomodoroBaseline()
        } else if !active.isPaused {
            if pomodoroBreak != nil {
                pomodoroBreak = nil
                breakCompletionNotified = false
            }
            if pendingIdleReview != nil {
                pendingIdleReview = nil
            }
        }
    }

    private func resetPomodoroBaseline() {
        let seconds = max(60, focusMinutes * 60)
        lastNotifiedRound = Int(focus.elapsed()) / seconds
    }

    private static func savedInteger(
        _ defaults: UserDefaults,
        key: String,
        fallback: Int,
        range: ClosedRange<Int>
    ) -> Int {
        guard defaults.object(forKey: key) != nil else { return fallback }
        return min(range.upperBound, max(range.lowerBound, defaults.integer(forKey: key)))
    }

    private static func systemIdleSeconds() -> TimeInterval {
        let eventTypes: [CGEventType] = [
            .mouseMoved,
            .leftMouseDown,
            .rightMouseDown,
            .keyDown,
            .scrollWheel
        ]
        return eventTypes
            .map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }
            .min() ?? 0
    }
}
