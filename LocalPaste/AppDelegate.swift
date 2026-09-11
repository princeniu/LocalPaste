import Foundation
import AppKit
import SwiftData
import SwiftUI
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let modelContainer: ModelContainer?
    let store: ClipboardStore?
    let shortcutManager: GlobalShortcutManager
    let loginItemManager: LoginItemManager

    private var monitor: ClipboardMonitor!
    private var pasteCoordinator: PasteCoordinator!
    private var panelController: PanelController!
    private var statusItem: NSStatusItem!
    private var pauseMenuItem: NSMenuItem!
    private var settingsWindowController: NSWindowController?
    private var pauseObservation: AnyCancellable?
    private let startupError: String?

    override init() {
        do {
            let identifier = Bundle.main.bundleIdentifier ?? ClipboardPersistence.productionBundleID
            guard !NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
                .contains(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) else {
                throw NSError(domain: "LocalPaste", code: 1, userInfo: [NSLocalizedDescriptionKey: "另一个版本仍在运行。请先退出它，再打开\(AppBrand.name)，以保留完整历史。"])
            }
            let container = try ClipboardPersistence.open()
            self.modelContainer = container
            self.store = ClipboardStore(modelContainer: container)
            self.startupError = nil
        } catch {
            self.modelContainer = nil
            self.store = nil
            self.startupError = error.localizedDescription
        }
        self.shortcutManager = GlobalShortcutManager()
        self.loginItemManager = LoginItemManager()
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        guard let store else {
            let alert = NSAlert()
            alert.alertStyle = .critical
            alert.messageText = "无法打开本地历史"
            alert.informativeText = (startupError ?? "数据库不可用。") + "\n原历史没有被清空。"
            alert.addButton(withTitle: "退出")
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
            NSApp.terminate(nil)
            return
        }
        loginItemManager.refreshStatus()
        setupStatusItem()
        pauseObservation = store.$isPaused.removeDuplicates().sink { [weak self] paused in
            self?.pauseMenuItem?.title = paused ? "继续记录" : "暂停记录"
        }

        monitor = ClipboardMonitor(store: store)
        pasteCoordinator = PasteCoordinator(store: store, monitor: monitor)
        panelController = PanelController(store: store, pasteCoordinator: pasteCoordinator, onSettings: { [weak self] in
            self?.openSettings()
        })
        shortcutManager.onTrigger = { [weak self] in
            Task { @MainActor in
                self?.panelController.toggle()
            }
        }
        _ = shortcutManager.registerInitialShortcut()
        monitor.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor?.stop()
        shortcutManager.unregisterHotKey()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        loginItemManager.refreshStatus()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showHistory() }
        return true
    }

    func showHistory() {
        panelController?.show()
    }

    @objc private func togglePanelFromMenu() {
        panelController.toggle()
    }

    @objc private func togglePauseFromMenu() {
        guard let store else { return }
        store.isPaused.toggle()
        updatePauseMenuItem()
    }

    @objc private func openSettingsFromMenu() {
        openSettings()
    }

    func openSettings() {
        guard let store else { return }
        let controller: NSWindowController
        if let existing = settingsWindowController {
            controller = existing
        } else {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 540, height: 480),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = "\(AppBrand.name)设置"
            window.isReleasedWhenClosed = false
            window.contentViewController = NSHostingController(
                rootView: SettingsView(
                    store: store,
                    shortcutManager: shortcutManager,
                    loginItemManager: loginItemManager
                )
            )
            window.center()
            let created = NSWindowController(window: window)
            created.shouldCascadeWindows = false
            settingsWindowController = created
            controller = created
        }
        NSApp.activate(ignoringOtherApps: true)
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
    }

    @objc private func quitFromMenu() {
        NSApp.terminate(nil)
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: AppBrand.displayName)
        statusItem.button?.toolTip = AppBrand.displayName

        let menu = NSMenu()
        let openItem = NSMenuItem(title: "打开历史", action: #selector(togglePanelFromMenu), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)

        pauseMenuItem = NSMenuItem(title: "暂停记录", action: #selector(togglePauseFromMenu), keyEquivalent: "")
        pauseMenuItem.target = self
        menu.addItem(pauseMenuItem)
        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "设置…", action: #selector(openSettingsFromMenu), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let quitItem = NSMenuItem(title: "退出\(AppBrand.name)", action: #selector(quitFromMenu), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        statusItem.menu = menu
        updatePauseMenuItem()
    }

    private func updatePauseMenuItem() {
        pauseMenuItem?.title = store?.isPaused == true ? "继续记录" : "暂停记录"
    }
}
