import Foundation
import AppKit
import ApplicationServices

@MainActor
final class PasteCoordinator: ObservableObject {
    @Published private(set) var feedbackMessage: String?
    @Published private(set) var isPasting = false

    struct Environment {
        var pasteboard: NSPasteboard = .general
        var isTrusted: () -> Bool = { AXIsProcessTrusted() }
        var requestPermission: () -> Void = {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        }
        var activate: (NSRunningApplication) -> Void = { $0.activate(options: []) }
        var frontmostPID: () -> pid_t? = { NSWorkspace.shared.frontmostApplication?.processIdentifier }
        var sendCommandV: () -> Bool = { PasteCoordinator.sendCommandV() }
        var schedule: (@escaping () -> Void) -> Void = { work in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { work() }
        }
    }

    private let store: ClipboardStore
    private weak var monitor: ClipboardMonitor?
    private let environment: Environment

    init(store: ClipboardStore, monitor: ClipboardMonitor? = nil, environment: Environment = Environment()) {
        self.store = store
        self.monitor = monitor
        self.environment = environment
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
        guard !isPasting else {
            completion("正在粘贴，请稍候。")
            return
        }
        isPasting = true
        let finish: (String) -> Void = { [weak self] message in
            self?.isPasting = false
            self?.feedbackMessage = message
            completion(message)
        }
        let pasteboard = environment.pasteboard
        let items: [NSPasteboardItem]
        if plainTextOnly {
            guard let text = store.plainText(for: entry) else {
                finish("此条目没有可提取的文字，剪贴板未更改。")
                return
            }
            let item = NSPasteboardItem()
            item.setString(text, forType: .string)
            items = [item]
        } else if let payload = store.payload(for: entry) {
            items = payload.items.map(makePasteboardItem)
        } else {
            finish("无法读取该条目，剪贴板未更改。")
            return
        }
        guard !items.isEmpty, items.allSatisfy({ !$0.types.isEmpty }) else {
            finish("没有可恢复的内容，剪贴板未更改。")
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
            finish(restored ? "复制失败，已恢复原剪贴板。" : "复制失败，原剪贴板恢复也失败；未发送粘贴。")
            return
        }
        monitor?.suppressChangeCount(upTo: pasteboard.changeCount)
        let writtenChangeCount = pasteboard.changeCount

        guard environment.isTrusted() else {
            // Only reached after the user explicitly chooses a clip to paste.
            environment.requestPermission()
            let message = "已复制，按 ⌘V 粘贴。自动粘贴需要辅助功能权限。"
            finish(message)
            return
        }
        guard let targetApplication, !targetApplication.isTerminated else {
            let message = "已复制，切换到目标应用后按 ⌘V 粘贴。"
            finish(message)
            return
        }

        let processIdentifier = targetApplication.processIdentifier
        environment.activate(targetApplication)
        environment.schedule { [weak self] in
            guard let self else { return }
            guard pasteboard.changeCount == writtenChangeCount else {
                finish("你复制了新内容，本次粘贴已取消。")
                return
            }
            guard self.environment.frontmostPID() == processIdentifier else {
                let message = "已复制，切换到目标应用后按 ⌘V 粘贴。"
                finish(message)
                return
            }
            guard self.environment.sendCommandV() else {
                let message = "无法自动粘贴，请按 ⌘V 完成。"
                finish(message)
                return
            }
            let message = "已发送粘贴快捷键"
            finish(message)
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

    nonisolated private static func sendCommandV() -> Bool {
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
