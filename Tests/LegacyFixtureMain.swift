import Foundation
import SwiftData
import CryptoKit
@main struct LegacyFixtureMain {
    @MainActor static func main() throws {
        let directory = URL(fileURLWithPath: CommandLine.arguments[1])
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let container = try ModelContainer(for: ClipboardEntry.self, ClipCategory.self, configurations: ModelConfiguration(url: directory.appendingPathComponent("default.store")))
        let context = ModelContext(container)
        let category = ClipCategory(name: "legacy category")
        let payload = StoredPasteboardPayload(items: [.init(representations: [.init(uti: "public.png", data: Data(repeating: 0xa5, count: 2_097_152), stringValue: nil, filePath: nil)])], plainText: "", displayText: "图片", contentType: "image", filePaths: [])
        let encoded = try JSONEncoder().encode(payload)
        let large = ClipboardEntry(sourceBundleIdentifier: "synthetic.test", sourceName: "Fixture", title: "legacy large", contentTypeRaw: "image", isFavorite: true, payloadData: encoded, categoryIDsData: try JSONEncoder().encode([category.id.uuidString]))
        let text = StoredPasteboardPayload(items: [.init(representations: [.init(uti: "public.utf8-plain-text", data: Data("legacy text".utf8), stringValue: "legacy text", filePath: nil)])], plainText: "legacy text", displayText: "legacy text", contentType: "text", filePaths: [])
        context.insert(category); context.insert(large)
        context.insert(ClipboardEntry(title: "legacy text", contentTypeRaw: "text", payloadData: try JSONEncoder().encode(text)))
        try context.save()
        let manifest = ["largeID": large.id.uuidString, "payloadHash": SHA256.hash(data: encoded).map{ String(format:"%02x",$0) }.joined()]
        try JSONSerialization.data(withJSONObject: manifest).write(to: directory.appendingPathComponent("manifest.json"))
        // Exit without releasing the container, preserving a realistic WAL for the copy test.
        withExtendedLifetime(container) { exit(0) }
    }
}
