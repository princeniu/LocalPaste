import AppKit
import ImageIO

/// Entry payloads are immutable. Cache only small derived previews, never their source data.
@MainActor
final class CardPreviewCache {
    struct Preview {
        let thumbnail: NSImage?
        let fileNames: [String]
        let fileCount: Int
        let isReadable: Bool
    }

    static let shared = CardPreviewCache()
    static let thumbnailPixelLimit = 448

    private struct Item {
        let preview: Preview
        let cost: Int
    }
    private let entryLimit: Int
    private let byteLimit: Int
    private var items: [UUID: Item] = [:]
    private var accessOrder: [UUID] = []
    private(set) var cachedByteCount = 0
    var cachedCount: Int { items.count }

    init(entryLimit: Int = 96, byteLimit: Int = 16 * 1_048_576) {
        self.entryLimit = max(1, entryLimit)
        self.byteLimit = max(1, byteLimit)
    }

    func preview(for entry: ClipboardEntry) -> Preview {
        if let item = items[entry.id] {
            touch(entry.id)
            return item.preview
        }
        let payload = entry.payload
        let thumbnail = entry.contentType == .image || entry.contentType == .mixed ? payload.flatMap(Self.thumbnail) : nil
        let names = payload?.filePaths.prefix(2).map { URL(fileURLWithPath: $0).lastPathComponent } ?? []
        let preview = Preview(thumbnail: thumbnail.map { NSImage(cgImage: $0, size: .zero) },
                              fileNames: names, fileCount: payload?.filePaths.count ?? 0,
                              isReadable: payload != nil)
        let cost = (thumbnail.map { $0.bytesPerRow * $0.height } ?? 0) + names.reduce(0) { $0 + $1.utf8.count } + 128
        if cost <= byteLimit {
            while !accessOrder.isEmpty && (items.count >= entryLimit || cachedByteCount + cost > byteLimit) {
                remove(accessOrder[0])
            }
            items[entry.id] = Item(preview: preview, cost: cost)
            cachedByteCount += cost
            accessOrder.append(entry.id)
        }
        return preview
    }

    func retainEntries(withIDs ids: Set<UUID>) {
        for id in accessOrder where !ids.contains(id) { remove(id) }
    }

    private func touch(_ id: UUID) {
        accessOrder.removeAll { $0 == id }
        accessOrder.append(id)
    }

    private func remove(_ id: UUID) {
        if let item = items.removeValue(forKey: id) { cachedByteCount -= item.cost }
        accessOrder.removeAll { $0 == id }
    }

    private static func thumbnail(from payload: StoredPasteboardPayload) -> CGImage? {
        for item in payload.items {
            for representation in item.representations where representation.uti == "public.png" || representation.uti == "public.tiff" {
                guard let data = representation.data,
                      let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
                      let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceCreateThumbnailWithTransform: true,
                        kCGImageSourceThumbnailMaxPixelSize: thumbnailPixelLimit,
                        kCGImageSourceShouldCacheImmediately: true
                      ] as CFDictionary) else { continue }
                return image
            }
        }
        return nil
    }
}
