import SwiftUI

@main
struct TaskDeckApp: App {
    @StateObject private var store = TaskStore()
    @StateObject private var notifications = NotificationManager()
    @StateObject private var focus = FocusStore()

    var body: some Scene {
        WindowGroup("TaskDeck") {
            DashboardView()
                .environmentObject(store)
                .environmentObject(notifications)
                .environmentObject(focus)
                .frame(minWidth: 1_020, minHeight: 680)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1_260, height: 800)

        WindowGroup("桌面任务板", id: "desktop") {
            DesktopWidgetView()
                .environmentObject(store)
                .environmentObject(notifications)
                .environmentObject(focus)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 370, height: 520)
    }
}
