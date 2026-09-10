import Foundation
import AppKit

@MainActor
final class ClipboardMonitor: ObservableObject {
    private let store: ClipboardStore
    private var timer: Timer?
    private var lastChangeCount: Int?
    private var ignoredChangeCountUpperBound: Int?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var sourcePID: pid_t?

    private static let concealedType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
    private static let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")
    private static let supportedUTIs = [
        "public.utf8-plain-text",
        "public.plain-text",
        "public.text",
        "public.html",
        "public.rtf",
        "com.apple.flat-rtfd",
        "public.png",
        "public.tiff",
        "public.file-url",
        "public.url"
    ]

    init(store: ClipboardStore) {
        self.store = store
    }

    func start() {
        guard timer == nil else { return }
        lastChangeCount = NSPasteboard.general.changeCount
        sourcePID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.didDeactivateApplicationNotification] {
            let observer = NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    // Changes spanning an app transition have ambiguous provenance: discard them.
                    self?.lastChangeCount = NSPasteboard.general.changeCount
                    self?.sourcePID = NSWorkspace.shared.frontmostApplication?.processIdentifier
                }
            }
            workspaceObservers.append(observer)
        }
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.poll()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        for observer in workspaceObservers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        workspaceObservers.removeAll()
    }

    func suppressChangeCount(upTo changeCount: Int) {
        if let current = ignoredChangeCountUpperBound {
            ignoredChangeCountUpperBound = max(current, changeCount)
        } else {
            ignoredChangeCountUpperBound = changeCount
        }
    }

    private func poll() {
        let pasteboard = NSPasteboard.general
        let changeCount = pasteboard.changeCount
        guard changeCount != lastChangeCount else { return }
        lastChangeCount = changeCount

        if let ignoredChangeCountUpperBound {
            if changeCount <= ignoredChangeCountUpperBound {
                if changeCount == ignoredChangeCountUpperBound {
                    self.ignoredChangeCountUpperBound = nil
                }
                return
            }
            self.ignoredChangeCountUpperBound = nil
        }
        guard !store.isPaused else { return }
        let source = NSWorkspace.shared.frontmostApplication
        guard source?.processIdentifier == sourcePID else {
            sourcePID = source?.processIdentifier
            return
        }
        let bundleIdentifier = source?.bundleIdentifier ?? ""
        guard !store.isExcluded(bundleIdentifier: source?.bundleIdentifier) else { return }
        guard let payload = makePayload(from: pasteboard) else { return }
        guard pasteboard.changeCount == changeCount,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == source?.processIdentifier else { return }

        let sourceName = source?.localizedName ?? "未知应用"
        let title = makeTitle(payload: payload)
        store.addEntry(
            payload: payload,
            sourceBundleIdentifier: bundleIdentifier,
            sourceName: sourceName,
            title: title
        )
    }

    private func makePayload(from pasteboard: NSPasteboard) -> StoredPasteboardPayload? {
        let allTypes = Set(pasteboard.types ?? [])
        guard !allTypes.contains(Self.concealedType), !allTypes.contains(Self.transientType) else {
            return nil
        }
        guard let pasteboardItems = pasteboard.pasteboardItems, !pasteboardItems.isEmpty else {
            return nil
        }

        var storedItems: [StoredPasteboardItem] = []
        var plainTextParts: [String] = []
        var filePaths: [String] = []
        var hasImage = false
        var hasHTML = false
        var hasRichText = false

        for item in pasteboardItems {
            var representations: [StoredPasteboardRepresentation] = []
            var itemPlainText: String?
            for uti in Self.supportedUTIs {
                let type = NSPasteboard.PasteboardType(uti)
                guard item.types.contains(type) else { continue }
                let stringValue = item.string(forType: type)
                var data = item.data(forType: type)
                if data == nil, let stringValue {
                    data = stringValue.data(using: .utf8)
                }
                let filePath = uti == "public.file-url" ? readFilePath(from: item, type: type) : nil
                guard data != nil || stringValue != nil || filePath != nil else { continue }
                representations.append(
                    StoredPasteboardRepresentation(
                        uti: uti,
                        data: data,
                        stringValue: stringValue,
                        filePath: filePath
                    )
                )
                if let stringValue, uti == "public.utf8-plain-text" || uti == "public.plain-text" || uti == "public.text" || uti == "public.url" {
                    itemPlainText = itemPlainText ?? stringValue
                }
                if let filePath { filePaths.append(filePath) }
                hasImage = hasImage || uti == "public.png" || uti == "public.tiff"
                hasHTML = hasHTML || uti == "public.html"
                hasRichText = hasRichText || uti == "public.rtf" || uti == "com.apple.flat-rtfd"
            }
            if !representations.isEmpty {
                storedItems.append(StoredPasteboardItem(representations: representations))
                if let itemPlainText {
                    plainTextParts.append(itemPlainText)
                }
            }
        }

        guard !storedItems.isEmpty else { return nil }
        let plainText = plainTextParts.joined(separator: "\n")
        let contentType: ClipboardContentType
        if !filePaths.isEmpty {
            contentType = .fileReference
        } else if hasImage && (hasHTML || hasRichText || !plainText.isEmpty) {
            contentType = .mixed
        } else if hasImage {
            contentType = .image
        } else if hasHTML {
            contentType = .html
        } else if hasRichText {
            contentType = .richText
        } else {
            contentType = .text
        }

        let displayText: String
        if !plainText.isEmpty {
            displayText = plainText
        } else if !filePaths.isEmpty {
            displayText = filePaths.map { URL(fileURLWithPath: $0).lastPathComponent }.joined(separator: "\n")
        } else if hasImage {
            displayText = "图片"
        } else {
            displayText = contentType.label
        }

        return StoredPasteboardPayload(
            items: storedItems,
            plainText: plainText,
            displayText: displayText,
            contentType: contentType.rawValue,
            filePaths: filePaths
        )
    }

    private func readFilePath(from item: NSPasteboardItem, type: NSPasteboard.PasteboardType) -> String? {
        if let value = item.propertyList(forType: type) as? String {
            return filePath(from: value)
        }
        if let values = item.propertyList(forType: type) as? [String], let first = values.first {
            return filePath(from: first)
        }
        if let value = item.string(forType: type) {
            return filePath(from: value)
        }
        if let data = item.data(forType: type), let value = String(data: data, encoding: .utf8) {
            return filePath(from: value)
        }
        return nil
    }

    private func filePath(from value: String) -> String? {
        if let url = URL(string: value), url.isFileURL {
            return url.path
        }
        if value.hasPrefix("/") { return value }
        return nil
    }

    private func makeTitle(payload: StoredPasteboardPayload) -> String {
        if !payload.filePaths.isEmpty {
            return payload.filePaths.map { URL(fileURLWithPath: $0).lastPathComponent }.joined(separator: ", ")
        }
        let firstLine = payload.displayText
            .components(separatedBy: .newlines)
            .first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) ?? payload.contentType
        let cleaned = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.count <= 80 { return cleaned }
        return String(cleaned.prefix(80)) + "…"
    }
}
