import Foundation
import AppKit
import ApplicationServices

@MainActor
final class PasteCoordinator: ObservableObject {
    @Published private(set) var feedbackMessage: String?

    private let store: ClipboardStore
    private weak var monitor: ClipboardMonitor?

    init(store: ClipboardStore, monitor: ClipboardMonitor? = nil) {
        self.store = store
        self.monitor = monitor
    }

    func attach(monitor: ClipboardMonitor) {
        self.monitor = monitor
    }

    func paste(
        entry: ClipboardEntry,
        plainTextOnly: Bool,
        targetApplication: NSRunningApplication?,
        completion: @escaping (String) -> Void
    ) {
        let pasteboard = NSPasteboard.general
        let items: [NSPasteboardItem]
        if plainTextOnly {
            let item = NSPasteboardItem()
            item.setString(store.plainText(for: entry), forType: .string)
            items = [item]
        } else if let payload = store.payload(for: entry) {
            items = payload.items.map(makePasteboardItem)
        } else {
            completion("无法读取该条目，剪贴板未更改。")
            return
        }
        guard !items.isEmpty, items.allSatisfy({ !$0.types.isEmpty }) else {
            completion("没有可恢复的内容，剪贴板未更改。")
            return
        }
        // Memory-only snapshot for rollback; never log or persist the prior clipboard.
        let previousItems = (pasteboard.pasteboardItems ?? []).map { original in
            let copy = NSPasteboardItem()
            for type in original.types {
                if let data = original.data(forType: type) { copy.setData(data, forType: type) }
            }
            return copy
        }
        pasteboard.clearContents()
        guard pasteboard.writeObjects(items) else {
            pasteboard.clearContents()
            let restored = previousItems.isEmpty || pasteboard.writeObjects(previousItems)
            monitor?.suppressChangeCount(upTo: pasteboard.changeCount)
            completion(restored ? "复制失败，已恢复原剪贴板。" : "复制失败，原剪贴板恢复也失败；未发送粘贴。")
            return
        }
        monitor?.suppressChangeCount(upTo: pasteboard.changeCount)

        guard AXIsProcessTrusted() else {
            // Only reached after the user explicitly chooses a clip to paste.
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
            let message = "已复制，按 Command-V 粘贴（需要辅助功能权限才能自动粘贴）。"
            feedbackMessage = message
            completion(message)
            return
        }
        guard let targetApplication, !targetApplication.isTerminated else {
            let message = "已复制，按 Command-V 粘贴（没有可确认的原目标应用）。"
            feedbackMessage = message
            completion(message)
            return
        }

        let processIdentifier = targetApplication.processIdentifier
        targetApplication.activate(options: [])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            guard let self else { return }
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == processIdentifier else {
                let message = "已复制，按 Command-V 粘贴（原目标应用未回到前台）。"
                self.feedbackMessage = message
                completion(message)
                return
            }
            guard self.sendCommandV() else {
                let message = "已复制，按 Command-V 粘贴（系统未允许发送按键）。"
                self.feedbackMessage = message
                completion(message)
                return
            }
            let message = "已发送粘贴快捷键"
            self.feedbackMessage = message
            completion(message)
        }
    }

    private func makePasteboardItem(_ storedItem: StoredPasteboardItem) -> NSPasteboardItem {
        let item = NSPasteboardItem()
        for representation in storedItem.representations {
            let type = NSPasteboard.PasteboardType(representation.uti)
            if let data = representation.data {
                item.setData(data, forType: type)
            } else if let stringValue = representation.stringValue {
                item.setString(stringValue, forType: type)
            } else if representation.uti == "public.file-url", let filePath = representation.filePath {
                item.setString(URL(fileURLWithPath: filePath).absoluteString, forType: type)
            }
        }
        return item
    }

    private func sendCommandV() -> Bool {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return false }
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else {
            return false
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        return true
    }
}
