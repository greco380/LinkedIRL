import SwiftUI

@main
struct LinkupApp: App {
    @UIApplicationDelegateAdaptor(AppNotificationDelegate.self) private var notificationDelegate
    @StateObject private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environment(\.linkupTheme, store.theme)
                .preferredColorScheme(store.settings.theme == .dark ? .dark : .light)
        }
    }
}
