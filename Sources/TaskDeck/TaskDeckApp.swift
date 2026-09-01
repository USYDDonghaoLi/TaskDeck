import SwiftUI

@main
struct TaskDeckApp: App {
    @StateObject private var store = TaskStore()
    @StateObject private var notifications = NotificationManager()
    @StateObject private var focus = FocusStore()
    @StateObject private var language = LanguageStore()

    var body: some Scene {
        WindowGroup("TaskDeck") {
            DashboardView()
                .environmentObject(store)
                .environmentObject(notifications)
                .environmentObject(focus)
                .environmentObject(language)
                .environment(\.locale, language.current.locale)
                .frame(minWidth: 1_020, minHeight: 680)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1_260, height: 800)

        WindowGroup("TaskDeck Desktop", id: "desktop") {
            DesktopWidgetView()
                .environmentObject(store)
                .environmentObject(notifications)
                .environmentObject(focus)
                .environmentObject(language)
                .environment(\.locale, language.current.locale)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 370, height: 520)
    }
}
