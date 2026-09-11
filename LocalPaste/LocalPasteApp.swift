import SwiftUI

@main
struct LocalPasteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            if let store = appDelegate.store {
                SettingsView(
                    store: store,
                    shortcutManager: appDelegate.shortcutManager,
                    loginItemManager: appDelegate.loginItemManager
                )
            }
        }
    }
}
