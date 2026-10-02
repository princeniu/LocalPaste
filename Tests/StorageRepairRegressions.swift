import AppKit
import Foundation
import SwiftData

@MainActor func testStorageRepairs() throws {
    let store = try makeStore()
    let board = namedBoard()
    defer { board.releaseGlobally() }
    let monitor = ClipboardMonitor(store: store, pasteboard: board,
        frontmostApplication: { NSRunningApplication.current })
    let paths = (0..<100).map { "/tmp/" + String(repeating: "a", count: 90) + "-\($0).txt" }
    let items = paths.map { path -> NSPasteboardItem in
        let item = NSPasteboardItem()
        item.setString(URL(fileURLWithPath: path).absoluteString, forType: .fileURL)
        return item
    }
    board.clearContents(); board.writeObjects(items); monitor.poll()
    let files = store.entries[0]
    try check(files.title.count < 120 && files.payload?.filePaths == paths,
        "large file selections retain every path with a bounded display title")
    try check(try ClipboardBackup.decode(store.backupSnapshot().preparingForExport().encoded()).entries.count == 1,
        "captured large file selections can be exported and decoded")

    let storedBytes = store.entries.reduce(0) { $0 + $1.payloadData.count }
    try check(store.storedPayloadBytes == storedBytes, "storage usage counts encoded payload bytes")
    var oversizedRejected = false
    do { try ClipboardStoragePolicy.validateCapture(bytes: ClipboardStoragePolicy.maximumEntryBytes + 1) }
    catch ClipboardStorageError.entryTooLarge { oversizedRejected = true }
    var fullRejected = false
    do { try ClipboardStoragePolicy.validateTotal(existingBytes: 1_024, addingBytes: 1_024 * 1_024, limitMB: 1) }
    catch ClipboardStorageError.capacityReached { fullRejected = true }
    try check(oversizedRejected && fullRejected, "single-entry and aggregate capacity reject overflow")
    try ClipboardStoragePolicy.validateTotal(existingBytes: 1_024, addingBytes: 1_024 * 1_024 - 1_024, limitMB: 1)
    try check(true, "content exactly at the capacity limit is accepted")
    store.storageLimitMB = 1
    try check(store.storageLimitMB == ClipboardStoragePolicy.limitRangeMB.lowerBound && store.entries.count == 1,
        "lowering capacity clamps preferences without deleting existing records")
    let hugePayload = StoredPasteboardPayload(items: [.init(representations: [
        .init(uti: "public.png", data: Data(count: ClipboardStoragePolicy.maximumEntryBytes), stringValue: nil, filePath: nil)
    ])], plainText: "", displayText: "image", contentType: "image", filePaths: [])
    let denied = store.addEntry(payload: hugePayload, sourceBundleIdentifier: "fixture", sourceName: "Fixture", title: "large")
    try check(denied == nil && store.entries.count == 1 && store.storedPayloadBytes == storedBytes,
        "oversized capture leaves the saved history and usage unchanged")
    store.delete(files)
    try check(store.storedPayloadBytes == 0, "deleting a record releases its content budget")
    let actual = add(store, "cached fixture")
    actual.payloadData = try JSONEncoder().encode(textPayload("original payload is authoritative"))
    try check(store.plainText(for: actual) == "original payload is authoritative",
        "plain-text paste reads the original payload rather than a stale derived summary")

    let root = FileManager.default.temporaryDirectory.appendingPathComponent("ClipmoriSummaryRepair-\(UUID())")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: root) }
    let databaseURL = root.appendingPathComponent("fixture.store")
    let cacheURL = databaseURL.appendingPathExtension("summary-v1.json")
    let suite = "ClipmoriSummaryRepair.\(UUID())"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    var id: UUID!
    try autoreleasepool {
        let container = try ModelContainer(for: ClipboardEntry.self, ClipCategory.self,
            configurations: ModelConfiguration(url: databaseURL))
        let original = ClipboardStore(modelContainer: container, defaults: defaults)
        let entry = add(original, "durable summary fixture")
        id = entry.id
        original.flushSummaryCache()
        let permissions = try FileManager.default.attributesOfItem(atPath: cacheURL.path)[.posixPermissions] as? NSNumber
        try check(permissions?.intValue == 0o600, "durable summaries are written with owner-only permissions")
    }
    try autoreleasepool {
        let container = try ModelContainer(for: ClipboardEntry.self, ClipCategory.self,
            configurations: ModelConfiguration(url: databaseURL))
        let reopened = ClipboardStore(modelContainer: container, defaults: defaults)
        try check(reopened.summaryCacheHits == 1 && reopened.plainText(for: reopened.entries[0]) == "durable summary fixture",
            "reopening a store reuses its durable summary without decoding the payload")
        try check(reopened.entries[0].id == id && reopened.storedPayloadBytes == reopened.entries[0].payloadData.count,
            "cached summaries preserve record identity and capacity accounting")
        reopened.delete(reopened.entries[0]); reopened.flushSummaryCache()
        try check(!FileManager.default.fileExists(atPath: cacheURL.path), "deleting all history also removes its durable summary file")
        _ = add(reopened, "cache recovery fixture"); reopened.flushSummaryCache()
    }
    var envelope = try JSONSerialization.jsonObject(with: Data(contentsOf: cacheURL)) as! [String: Any]
    envelope["sha256"] = "incorrect digest"
    try JSONSerialization.data(withJSONObject: envelope).write(to: cacheURL)
    try autoreleasepool {
        let container = try ModelContainer(for: ClipboardEntry.self, ClipCategory.self,
            configurations: ModelConfiguration(url: databaseURL))
        let recovered = ClipboardStore(modelContainer: container, defaults: defaults)
        try check(recovered.summaryCacheHits == 0 && recovered.plainText(for: recovered.entries[0]) == "cache recovery fixture",
            "a valid JSON index with a damaged checksum rebuilds from the original database")
        recovered.flushSummaryCache()
        recovered.clearHistory(preservingFavorites: false); recovered.flushSummaryCache()
    }
    try Data("damaged cache with synthetic private text".utf8).write(to: cacheURL)
    let cache = ClipboardSummaryCache(url: cacheURL)
    cache.save(entries: [], summaries: [:]); cache.waitForPendingWrites()
    try check(!FileManager.default.fileExists(atPath: cacheURL.path), "an empty store also removes an unreadable stale summary file")
}
