import SwiftUI

@main
struct LocalPasteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView(store: appDelegate.store, shortcutManager: appDelegate.shortcutManager)
        }
    }
}
