import Foundation
import AppKit
import SwiftUI

@MainActor
final class HistoryViewModel: ObservableObject {
    @Published var query = ""
    @Published var selectedCategoryID: String?
    @Published var selectedID: UUID?
    @Published var previewEntryID: UUID?
    @Published var statusMessage: String?

    let store: ClipboardStore

    init(store: ClipboardStore) {
        self.store = store
    }

    var visibleEntries: [ClipboardEntry] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return store.entries.filter { entry in
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
            let haystack = [entry.title, entry.sourceName, entry.payload?.displayText ?? ""]
                .joined(separator: " ")
                .lowercased()
            return haystack.contains(normalizedQuery)
        }
    }

    var selectedEntry: ClipboardEntry? {
        guard let selectedID else { return visibleEntries.first }
        return visibleEntries.first(where: { $0.id == selectedID }) ?? visibleEntries.first
    }

    func ensureSelection() {
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
        let panelSize = NSSize(width: min(920, max(720, visibleFrame.width - 48)), height: 318)
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
            switch event.keyCode {
            case 123:
                self.viewModel.moveSelection(by: -1)
                return nil
            case 124:
                self.viewModel.moveSelection(by: 1)
                return nil
            case 36, 76:
                if let entry = self.viewModel.selectedEntry {
                    self.paste(entry: entry, plainTextOnly: false)
                }
                return nil
            case 49:
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
