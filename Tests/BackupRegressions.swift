import AppKit
import Foundation
import SwiftData

@MainActor func testBackupAndRestore() throws {
    let source = try makeStore(limit: 50)
    let category = source.addCategory(named: "Work")!
    let favorite = add(source, "favorite fixture")
    source.toggleFavorite(favorite)
    source.assign(favorite, to: category)
    let binary = Data((0...255).map(UInt8.init))
    let payload = StoredPasteboardPayload(items: [.init(representations: [
        .init(uti: "public.png", data: binary, stringValue: nil, filePath: nil)
    ])], plainText: "", displayText: "image fixture", contentType: "image", filePaths: [])
    let image = source.addEntry(payload: payload, sourceBundleIdentifier: "test.binary", sourceName: "Fixture", title: "binary fixture")!
    let paths = ["/tmp/clipmori-fixture-not-copied.txt"]
    let files = StoredPasteboardPayload(items: [.init(representations: [
        .init(uti: "public.file-url", data: nil, stringValue: "file:///tmp/clipmori-fixture-not-copied.txt", filePath: paths[0])
    ])], plainText: "", displayText: "file fixture", contentType: "fileReference", filePaths: paths)
    _ = source.addEntry(payload: files, sourceBundleIdentifier: "test.files", sourceName: "Fixture", title: "file fixture")
    let encoded = try source.backupSnapshot().preparingForExport().encoded()
    let archive = try ClipboardBackup.decode(encoded)
    try check(archive.entries.count == 3 && archive.categories.count == 1
              && archive.entries.first(where: { $0.id == image.id })?.payloadData == image.payloadData,
              "backup round trip preserves binary payload bytes, records and categories")

    let target = try makeStore(limit: 50)
    let existingCategory = target.addCategory(named: "work")!
    for i in 0..<49 { add(target, "existing \(i)") }
    let existingIDs = Set(target.entries.map(\.id))
    let preview = try target.planImport(archive)
    try check(target.entries.count == 49 && preview.entries.count == 3 && preview.categories.isEmpty
              && preview.favoriteCount == 1 && preview.requiredLimit == 100,
              "import preview is read-only and plans a safe retention increase")
    _ = try target.importBackup(archive, preview: preview)
    let restoredFavorite = target.entries.first { $0.id == favorite.id }!
    try check(target.entries.count == 52 && existingIDs.isSubset(of: Set(target.entries.map(\.id)))
              && target.historyLimit == 100 && target.categories.count == 1,
              "merge preserves all existing records and raises retention before pruning")
    try check(restoredFavorite.isFavorite && restoredFavorite.categoryIDs == [existingCategory.id.uuidString]
              && abs(restoredFavorite.createdAt.timeIntervalSince(favorite.createdAt)) < 0.001
              && target.entries.first(where: { $0.id == image.id })?.payloadData == image.payloadData,
              "restore retains favorite, timestamp and original bytes while merging category names")
    try check(target.entries.first(where: { $0.contentType == .fileReference })?.payload?.filePaths == paths,
              "file backup restores references without reading or copying the original files")
    source.clearHistory(preservingFavorites: false)
    try check(archive.entries.count == 3, "export snapshot survives later source changes")
    target.toggleFavorite(restoredFavorite)
    let repeated = try target.planImport(archive)
    _ = try target.importBackup(archive, preview: repeated)
    try check(repeated.entries.isEmpty && repeated.skippedCount == 3 && target.entries.count == 52
              && !restoredFavorite.isFavorite, "repeated import is idempotent and retains local edits")
    add(target, "copy after import")
    try check(Set(archive.entries.map(\.id)).isSubset(of: Set(target.entries.map(\.id))),
              "a subsequent capture does not immediately discard restored history")
    let stale = try target.planImport(archive)
    add(target, "copy during preview")
    var staleRejected = false
    do { _ = try target.importBackup(archive, preview: stale) }
    catch BackupError.historyChanged { staleRejected = true }
    try check(staleRejected && target.entries.count == 54, "stale import preview is rejected without changing history")

    func changedJSON(_ mutate: (inout [String: Any]) -> Void) throws -> Data {
        var json = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        mutate(&json)
        return try JSONSerialization.data(withJSONObject: json)
    }
    func rejected(_ data: Data) -> Bool {
        do { _ = try ClipboardBackup.decode(data); return false }
        catch { return true }
    }
    let corrupt = try changedJSON { json in
        var entries = json["entries"] as! [[String: Any]]
        entries[0]["payloadSHA256"] = "invalid"
        json["entries"] = entries
    }
    let duplicate = try changedJSON { json in
        var entries = json["entries"] as! [[String: Any]]
        entries.append(entries[0]); json["entries"] = entries
    }
    let dangling = try changedJSON { json in
        var entries = json["entries"] as! [[String: Any]]
        entries[0]["categoryIDs"] = [UUID().uuidString]; json["entries"] = entries
    }
    let future = try changedJSON { $0["version"] = 99 }
    try check(rejected(corrupt) && rejected(duplicate) && rejected(dangling) && rejected(future)
              && rejected(Data("not a backup".utf8)),
              "corrupt, duplicate, dangling-reference and incompatible backups are rejected")
    try check(rejected(Data(count: ClipboardBackup.maximumBytes + 1)), "oversized backup is rejected before decoding")

    let base = archive.entries.first { !$0.isFavorite }!
    let many = ClipboardBackup(categories: [], entries: (0..<5_001).map { _ in
        .init(id: UUID(), createdAt: base.createdAt, sourceBundleIdentifier: base.sourceBundleIdentifier,
              sourceName: base.sourceName, title: base.title, contentTypeRaw: base.contentTypeRaw,
              isFavorite: false, payloadData: base.payloadData, payloadSHA256: base.payloadSHA256, categoryIDs: [])
    })
    let tooMany = try ClipboardBackup.decode(many.encoded())
    var limitRejected = false
    do { _ = try target.planImport(tooMany) }
    catch BackupError.tooManyEntries { limitRejected = true }
    try check(limitRejected && target.entries.count == 54, "oversized merge cannot evict existing history")

    let root = FileManager.default.temporaryDirectory.appendingPathComponent("ClipmoriBackup-\(UUID())")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let url = root.appendingPathComponent("fixture.clipmori")
    try archive.write(to: url)
    let fromDisk = try ClipboardBackup.read(from: url)
    let permissions = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
    try check(fromDisk.entries.count == 3 && permissions?.intValue == 0o600, "backup file round trip uses private file permissions")

    let restoredURL = root.appendingPathComponent("restored.store")
    let restoreSuite = "ClipmoriBackupRestored.\(UUID())"
    let restoreDefaults = UserDefaults(suiteName: restoreSuite)!
    defer { restoreDefaults.removePersistentDomain(forName: restoreSuite) }
    try autoreleasepool {
        let container = try ModelContainer(for: ClipboardEntry.self, ClipCategory.self,
                                           configurations: ModelConfiguration(url: restoredURL))
        let persisted = ClipboardStore(modelContainer: container, defaults: restoreDefaults)
        _ = try persisted.importBackup(fromDisk, preview: persisted.planImport(fromDisk))
    }
    try autoreleasepool {
        let reopened = try ModelContainer(for: ClipboardEntry.self, ClipCategory.self,
                                          configurations: ModelConfiguration(url: restoredURL))
        let restored = ClipboardStore(modelContainer: reopened, defaults: restoreDefaults)
        try check(Set(restored.entries.map(\.id)) == Set(archive.entries.map(\.id))
                  && restored.entries.first(where: { $0.id == favorite.id })?.isFavorite == true
                  && restored.entries.first(where: { $0.id == favorite.id })?.categoryIDs == [category.id.uuidString]
                  && restored.entries.first(where: { $0.id == image.id })?.payloadData == image.payloadData,
                  "restored history, favorites, categories and original bytes survive database reopen")
    }

    let storeURL = root.appendingPathComponent("read-only.store")
    try autoreleasepool {
        _ = try ModelContainer(for: ClipboardEntry.self, ClipCategory.self, configurations: ModelConfiguration(url: storeURL))
    }
    let readOnly = try ModelContainer(for: ClipboardEntry.self, ClipCategory.self,
                                     configurations: ModelConfiguration(url: storeURL, allowsSave: false))
    let denied = ClipboardStore(modelContainer: readOnly, defaults: UserDefaults(suiteName: "ClipmoriBackupDenied.\(UUID())")!)
    let deniedPreview = try denied.planImport(archive)
    var saveRejected = false
    do { _ = try denied.importBackup(archive, preview: deniedPreview) }
    catch { saveRejected = true }
    try check(saveRejected && denied.entries.isEmpty && denied.categories.isEmpty
              && denied.historyLimit == deniedPreview.previousLimit,
              "failed restore rolls back entries and categories and preserves retention settings")

    let guideSuite = "ClipmoriWelcome.\(UUID())"
    let defaults = UserDefaults(suiteName: guideSuite)!
    defer { defaults.removePersistentDomain(forName: guideSuite) }
    try check(WelcomeExperience.shouldPresent(defaults: defaults, hasExistingData: false)
              && !WelcomeExperience.shouldPresent(defaults: defaults, hasExistingData: true),
              "welcome is offered on a fresh install without interrupting users with existing history")
    defaults.set(true, forKey: ClipboardStore.pausedKey)
    try check(!WelcomeExperience.shouldPresent(defaults: defaults, hasExistingData: false),
              "existing preferences suppress automatic onboarding even with empty history")
    defaults.removeObject(forKey: ClipboardStore.pausedKey)
    defaults.set(true, forKey: WelcomeExperience.completedKey)
    try check(!WelcomeExperience.shouldPresent(defaults: defaults, hasExistingData: false),
              "completed onboarding does not reappear on launch")
}
