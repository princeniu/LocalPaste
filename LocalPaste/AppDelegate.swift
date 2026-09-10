import Foundation
import AppKit
import SwiftData
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let modelContainer: ModelContainer
    let store: ClipboardStore
    let shortcutManager: GlobalShortcutManager

    private var monitor: ClipboardMonitor!
    private var pasteCoordinator: PasteCoordinator!
    private var panelController: PanelController!
    private var statusItem: NSStatusItem!
    private var pauseMenuItem: NSMenuItem!
    private var settingsWindowController: NSWindowController?

    override init() {
        do {
            self.modelContainer = try ModelContainer(for: ClipboardEntry.self, ClipCategory.self)
        } catch {
            fatalError("无法初始化 LocalPaste 本地数据库：\(error)")
        }
        self.store = ClipboardStore(modelContainer: modelContainer)
        self.shortcutManager = GlobalShortcutManager()
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()

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

    @objc private func togglePanelFromMenu() {
        panelController.toggle()
    }

    @objc private func togglePauseFromMenu() {
        store.isPaused.toggle()
        updatePauseMenuItem()
    }

    @objc private func openSettingsFromMenu() {
        openSettings()
    }

    func openSettings() {
        let controller: NSWindowController
        if let existing = settingsWindowController {
            controller = existing
        } else {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 520, height: 620),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = "LocalPaste 设置"
            window.isReleasedWhenClosed = false
            window.contentViewController = NSHostingController(
                rootView: SettingsView(store: store, shortcutManager: shortcutManager)
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
        statusItem.button?.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "LocalPaste")
        statusItem.button?.toolTip = "LocalPaste"

        let menu = NSMenu()
        let openItem = NSMenuItem(title: "打开历史", action: #selector(togglePanelFromMenu), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)

        pauseMenuItem = NSMenuItem(title: "暂停采集", action: #selector(togglePauseFromMenu), keyEquivalent: "")
        pauseMenuItem.target = self
        menu.addItem(pauseMenuItem)
        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "设置…", action: #selector(openSettingsFromMenu), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let quitItem = NSMenuItem(title: "退出 LocalPaste", action: #selector(quitFromMenu), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        statusItem.menu = menu
        updatePauseMenuItem()
    }

    private func updatePauseMenuItem() {
        pauseMenuItem?.title = store.isPaused ? "恢复采集" : "暂停采集"
    }
}
