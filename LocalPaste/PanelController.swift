import Foundation
import AppKit
import SwiftUI
import Combine

@MainActor
final class HistoryViewModel: ObservableObject {
    @Published var query = "" { didSet { refreshEntries() } }
    @Published var selectedCategoryID: String? { didSet { refreshEntries() } }
    @Published var selectedID: UUID?
    @Published var focusedCardID: UUID?
    @Published var previewEntryID: UUID?
    @Published var statusMessage: String?
    @Published private(set) var scrollToStartRequest = 0
    @Published private(set) var searchFocusRequest = 0
    @Published private(set) var visibleEntries: [ClipboardEntry] = []
    private var storeObservation: AnyCancellable?
    private var lastDismissedAt: Date?
    static let browsingRetentionInterval: TimeInterval = 5 * 60

    let store: ClipboardStore

    init(store: ClipboardStore) {
        self.store = store
        storeObservation = store.$revision.sink { [weak self] _ in self?.refreshEntries() }
    }

    private func refreshEntries() {
        if let id = selectedCategoryID, id != "favorites", !store.categories.contains(where: { $0.id.uuidString == id }) {
            selectedCategoryID = nil
            return
        }
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        visibleEntries = store.entries.filter { entry in
            let matchesCategory: Bool
            if let selectedCategoryID {
                if selectedCategoryID == "favorites" {
                    matchesCategory = entry.isFavorite
                } else {
                    matchesCategory = entry.categoryIDs.contains(selectedCategoryID)
                }
            } else {
                matchesCategory = true
            }
            guard matchesCategory else { return false }
            guard !normalizedQuery.isEmpty else { return true }
            return store.searchText(for: entry).contains(normalizedQuery)
        }
        ensureSelection()
    }

    var selectedEntry: ClipboardEntry? {
        guard let selectedID else { return visibleEntries.first }
        return visibleEntries.first(where: { $0.id == selectedID }) ?? visibleEntries.first
    }

    func ensureSelection() {
        if let id = previewEntryID, !store.entries.contains(where: { $0.id == id }) { previewEntryID = nil }
        if let selectedID, visibleEntries.contains(where: { $0.id == selectedID }) { return }
        selectedID = visibleEntries.first?.id
    }

    func select(_ entry: ClipboardEntry) {
        selectedID = entry.id
    }

    func recordDismissal(at date: Date = Date()) {
        lastDismissedAt = date
    }

    func prepareForPresentation(at date: Date = Date()) {
        defer { lastDismissedAt = nil }
        guard let lastDismissedAt,
              date.timeIntervalSince(lastDismissedAt) >= Self.browsingRetentionInterval else {
            ensureSelection()
            return
        }
        selectedID = visibleEntries.first?.id
        focusedCardID = nil
        previewEntryID = nil
        // Mouse scrolling does not change selection. Request a scroll even when
        // the first card was already selected before the panel was dismissed.
        scrollToStartRequest += 1
    }

    func moveSelection(by offset: Int) {
        let items = visibleEntries
        guard !items.isEmpty else { return }
        guard let currentID = selectedEntry?.id,
              let currentIndex = items.firstIndex(where: { $0.id == currentID }) else {
            selectedID = items.first?.id
            return
        }
        let newIndex = max(0, min(currentIndex + offset, items.count - 1))
        selectedID = items[newIndex].id
    }

    func selectBoundary(first: Bool) {
        selectedID = first ? visibleEntries.first?.id : visibleEntries.last?.id
        if first { scrollToStartRequest += 1 }
    }

    func returnToLatest() {
        query = ""
        selectedCategoryID = nil
        focusedCardID = nil
        previewEntryID = nil
        selectBoundary(first: true)
    }

    func focusSearch() { searchFocusRequest += 1 }

    func undoDeletion() {
        guard let entry = store.undoDeletion() else { return }
        if visibleEntries.contains(where: { $0.id == entry.id }) { select(entry) }
        statusMessage = "已恢复"
    }

    func showPreviewForSelection() {
        previewEntryID = selectedEntry?.id
    }

    var emptyTitle: String {
        if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "没有匹配条目" }
        if selectedCategoryID == "favorites" { return "还没有收藏" }
        if selectedCategoryID != nil { return "分类里还没有内容" }
        return store.isPaused ? "已暂停记录" : "复制的内容，会留在这里"
    }

    var emptyHint: String {
        if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "试试更短的关键词。" }
        if selectedCategoryID == "favorites" { return "右键收藏，留住常用内容。" }
        if selectedCategoryID != nil { return "右键点击历史卡片，加入这个分类。" }
        return store.isPaused ? "继续记录后，新复制的内容才会保存。" : "文字、图片和文件，随时找回。"
    }
}

private final class LocalPastePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class PanelContentView: NSView {
    init(rootView: HistoryView) {
        let hostingView = NSHostingView(rootView: rootView)
        super.init(frame: .zero)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }
}

@MainActor
final class PanelController: NSObject {
    private let store: ClipboardStore
    private let pasteCoordinator: PasteCoordinator
    private let onSettings: () -> Void
    private let viewModel: HistoryViewModel
    private var panel: NSPanel?
    private var localEventMonitor: Any?
    private var globalMouseMonitor: Any?
    private var menuTrackingObservations: [AnyCancellable] = []
    private var menuTrackingDepth = 0
    private var targetApplication: NSRunningApplication?
    private var applicationObservation: AnyCancellable?

    init(store: ClipboardStore, pasteCoordinator: PasteCoordinator, onSettings: @escaping () -> Void) {
        self.store = store
        self.pasteCoordinator = pasteCoordinator
        self.onSettings = onSettings
        self.viewModel = HistoryViewModel(store: store)
        super.init()
        applicationObservation = NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.didActivateApplicationNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self,
                          let application = NSWorkspace.shared.frontmostApplication,
                          application.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
                    if self.isVisible, self.targetApplication?.processIdentifier != application.processIdentifier {
                        self.close()
                    }
                    // Keep the last external app for returns from our own settings or menus.
                    self.targetApplication = application
                }
            }
    }

    var isVisible: Bool { panel?.isVisible == true }

    func toggle() {
        if isVisible {
            close()
        } else {
            show()
        }
    }

    func show() {
        if let frontmost = NSWorkspace.shared.frontmostApplication,
           frontmost.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            targetApplication = frontmost
        }
        viewModel.statusMessage = nil
        if isVisible {
            viewModel.ensureSelection()
        } else {
            viewModel.prepareForPresentation()
        }

        let panel = makePanelIfNeeded()
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let panelSize = NSSize(width: min(920, max(720, visibleFrame.width - 48)), height: 344)
        let origin = NSPoint(
            x: visibleFrame.midX - panelSize.width / 2,
            y: visibleFrame.minY + 24
        )
        panel.setFrame(NSRect(origin: origin, size: panelSize), display: true)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(panel.contentView)
        installEventMonitors()
    }

    func close() {
        guard isVisible else { return }
        panel?.orderOut(nil)
        removeEventMonitors()
        viewModel.previewEntryID = nil
        viewModel.recordDismissal()
    }

    private func makePanelIfNeeded() -> NSPanel {
        if let panel { return panel }
        let panel = LocalPastePanel(
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 318),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.hasShadow = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.contentView = PanelContentView(
            rootView: HistoryView(
                viewModel: viewModel,
                store: store,
                onPaste: { [weak self] entry, plainText in
                    self?.paste(entry: entry, plainTextOnly: plainText)
                },
                onClose: { [weak self] in self?.close() },
                onSettings: { [weak self] in
                    self?.close()
                    self?.onSettings()
                }
            )
        )
        self.panel = panel
        return panel
    }

    private func paste(entry: ClipboardEntry, plainTextOnly: Bool) {
        // Ignore a click queued before an application switch closed the panel.
        guard isVisible else { return }
        pasteCoordinator.paste(
            entry: entry,
            plainTextOnly: plainTextOnly,
            targetApplication: targetApplication
        ) { [weak self] message in
            guard let self else { return }
            self.viewModel.statusMessage = message
            if message == "已发送粘贴快捷键" {
                self.close()
            }
        }
    }

    static func shouldDismissForMouseDown(in window: NSWindow?, panel: NSWindow, menuIsTracking: Bool) -> Bool {
        // AppKit menus and SwiftUI sheets use their own windows.
        guard !menuIsTracking else { return false }
        var window = window
        while let current = window {
            if current === panel { return false }
            window = current.parent ?? current.sheetParent
        }
        return true
    }

    enum KeyboardAction: Equatable {
        case native, close, focusSearch, undo, preview
        case paste(plainText: Bool), move(Int), boundary(first: Bool)
    }

    static func keyboardAction(keyCode: UInt16, modifiers: NSEvent.ModifierFlags,
                               editingText: Bool, hasMarkedText: Bool,
                               navigationFocused: Bool, cardFocused: Bool, canUndo: Bool) -> KeyboardAction {
        guard !hasMarkedText else { return .native }
        let modifiers = modifiers.intersection([.command, .control, .option, .shift])
        if modifiers == .command && keyCode == 3 { return .focusSearch }
        if modifiers == .command && keyCode == 6 && !editingText && canUndo { return .undo }
        if keyCode == 53 { return .close }
        if [36, 76].contains(keyCode), modifiers.isSubset(of: .shift), editingText || navigationFocused {
            return .paste(plainText: modifiers.contains(.shift))
        }
        guard !editingText, modifiers.isEmpty else { return .native }
        switch keyCode {
        case 123 where navigationFocused || cardFocused: return .move(-1)
        case 124 where navigationFocused || cardFocused: return .move(1)
        case 115 where navigationFocused || cardFocused: return .boundary(first: true)
        case 119 where navigationFocused || cardFocused: return .boundary(first: false)
        case 49 where navigationFocused: return .preview
        default: return .native
        }
    }

    private func installEventMonitors() {
        removeEventMonitors()
        let center = NotificationCenter.default
        menuTrackingObservations = [
            center.publisher(for: NSMenu.didBeginTrackingNotification).sink { [weak self] _ in
                self?.menuTrackingDepth += 1
            },
            center.publisher(for: NSMenu.didEndTrackingNotification).sink { [weak self] _ in
                guard let self else { return }
                self.menuTrackingDepth = max(0, self.menuTrackingDepth - 1)
            }
        ]
        let mouseDown: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        // Global monitors observe other apps without consuming their clicks.
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: mouseDown) { [weak self] _ in
            self?.close()
        }
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: mouseDown.union(.keyDown)) { [weak self] event in
            guard let self, let panel = self.panel else { return event }
            if event.type != .keyDown {
                if Self.shouldDismissForMouseDown(in: event.window, panel: panel, menuIsTracking: self.menuTrackingDepth > 0) {
                    self.close()
                }
                return event
            }
            guard event.window === panel else { return event }
            guard panel.attachedSheet == nil else { return event }
            let editor = panel.firstResponder as? NSTextView
            let action = Self.keyboardAction(keyCode: event.keyCode, modifiers: event.modifierFlags,
                editingText: editor != nil, hasMarkedText: editor?.hasMarkedText() == true,
                navigationFocused: panel.firstResponder === panel.contentView,
                cardFocused: self.viewModel.focusedCardID != nil, canUndo: self.store.canUndoDeletion())
            switch action {
            case .native: return event
            case .close: self.close()
            case .focusSearch: self.viewModel.focusSearch()
            case .undo: self.viewModel.undoDeletion()
            case .move(let offset): self.viewModel.moveSelection(by: offset)
            case .boundary(let first): self.viewModel.selectBoundary(first: first)
            case .preview: self.viewModel.showPreviewForSelection()
            case .paste(let plainText):
                if let entry = self.viewModel.selectedEntry {
                    self.paste(entry: entry, plainTextOnly: plainText)
                }
            }
            return nil
        }
    }

    private func removeEventMonitors() {
        if let localEventMonitor {
            NSEvent.removeMonitor(localEventMonitor)
            self.localEventMonitor = nil
        }
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
            self.globalMouseMonitor = nil
        }
        menuTrackingObservations.removeAll()
        menuTrackingDepth = 0
    }
}
