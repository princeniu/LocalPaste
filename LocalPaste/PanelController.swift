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
    @Published private(set) var visibleEntries: [ClipboardEntry] = []
    private var storeObservation: AnyCancellable?

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

    func moveSelection(by offset: Int) {
        let items = visibleEntries
        guard !items.isEmpty else { return }
        guard let currentID = selectedEntry?.id,
              let currentIndex = items.firstIndex(where: { $0.id == currentID }) else {
            selectedID = items.first?.id
            return
        }
        let newIndex = (currentIndex + offset + items.count) % items.count
        selectedID = items[newIndex].id
    }

    func showPreviewForSelection() {
        previewEntryID = selectedEntry?.id
    }

    var emptyTitle: String {
        if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "没有匹配条目" }
        if selectedCategoryID == "favorites" { return "还没有收藏条目" }
        if selectedCategoryID != nil { return "这个分类还没有条目" }
        return store.isPaused ? "剪贴板采集已暂停" : "还没有新的剪贴板历史"
    }

    var emptyHint: String {
        if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "尝试其他关键词，或清除搜索条件。" }
        if selectedCategoryID == "favorites" { return "右键点击历史卡片，选择“收藏”。" }
        if selectedCategoryID != nil { return "右键点击历史卡片，将条目加入此分类。" }
        return store.isPaused ? "在设置或菜单中恢复采集后，新复制的内容才会记录。" : "复制文字、图片或 Finder 文件后，新内容会显示在这里。"
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
    private var targetApplication: NSRunningApplication?

    init(store: ClipboardStore, pasteCoordinator: PasteCoordinator, onSettings: @escaping () -> Void) {
        self.store = store
        self.pasteCoordinator = pasteCoordinator
        self.onSettings = onSettings
        self.viewModel = HistoryViewModel(store: store)
        super.init()
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
           frontmost.bundleIdentifier != Bundle.main.bundleIdentifier {
            targetApplication = frontmost
        }
        viewModel.statusMessage = nil
        viewModel.ensureSelection()

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
        installLocalEventMonitor()
    }

    func close() {
        panel?.orderOut(nil)
        removeLocalEventMonitor()
        viewModel.previewEntryID = nil
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

    private func installLocalEventMonitor() {
        removeLocalEventMonitor()
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let panel = self.panel, event.window === panel else { return event }
            guard panel.attachedSheet == nil else { return event }
            if let editor = panel.firstResponder as? NSTextView {
                if event.keyCode == 53 && !editor.hasMarkedText() {
                    panel.makeFirstResponder(panel.contentView)
                    return nil
                }
                return event
            }
            // Controls retain their native Enter/Space behavior. Only the navigation
            // container and explicitly focused cards participate in history navigation.
            let navigationFocused = panel.firstResponder === panel.contentView
            switch event.keyCode {
            case 123:
                guard navigationFocused || self.viewModel.focusedCardID != nil else { return event }
                self.viewModel.moveSelection(by: -1)
                return nil
            case 124:
                guard navigationFocused || self.viewModel.focusedCardID != nil else { return event }
                self.viewModel.moveSelection(by: 1)
                return nil
            case 36, 76:
                guard navigationFocused else { return event }
                if let entry = self.viewModel.selectedEntry {
                    self.paste(entry: entry, plainTextOnly: false)
                }
                return nil
            case 49:
                guard navigationFocused else { return event }
                self.viewModel.showPreviewForSelection()
                return nil
            case 53:
                self.close()
                return nil
            default:
                return event
            }
        }
    }

    private func removeLocalEventMonitor() {
        if let localEventMonitor {
            NSEvent.removeMonitor(localEventMonitor)
            self.localEventMonitor = nil
        }
    }
}
