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

        let content = UNMutableNotificationContent()
        content.title = "TASKDECK // \(task.normalizedDirection.uppercased())"
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

    private func refreshStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            let rawStatus = settings.authorizationStatus.rawValue
            Task { @MainActor in
                self?.authorizationStatus = UNAuthorizationStatus(rawValue: rawStatus) ?? .notDetermined
            }
        }
    }
}
