import Foundation
import SwiftData

@MainActor func testDataRepairs() throws {
    let files = FileManager.default
    let root = files.temporaryDirectory.appendingPathComponent("LocalPasteDataRepairs-\(UUID())", isDirectory: true)
    try files.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? files.removeItem(at: root) }

    // Match the directory left by a first launch that failed before opening SQLite.
    let emptyDirectory = root.appendingPathComponent("test.empty", isDirectory: true)
    try files.createDirectory(at: emptyDirectory, withIntermediateDirectories: false)
    let recovered = try ClipboardPersistence.open(applicationSupport: root, bundleIdentifier: "test.empty")
    try check(try ModelContext(recovered).fetchCount(FetchDescriptor<ClipboardEntry>()) == 0,
              "first launch retries an empty directory left by an earlier initialization failure")
    let fresh = try ClipboardPersistence.open(applicationSupport: root, bundleIdentifier: "test.fresh")
    try check(try ModelContext(fresh).fetchCount(FetchDescriptor<ClipboardEntry>()) == 0
              && !files.contentsOfDirectory(atPath: root.path).contains(where: { $0.hasPrefix(".LocalPaste-create-") }),
              "fresh database initialization publishes a complete store and removes its staging directory")

    let incompleteDirectory = root.appendingPathComponent("test.incomplete", isDirectory: true)
    try files.createDirectory(at: incompleteDirectory, withIntermediateDirectories: false)
    let sentinel = incompleteDirectory.appendingPathComponent("default.store-wal")
    let sentinelData = Data("artificial uncommitted store data".utf8)
    try sentinelData.write(to: sentinel)
    var incompleteRejected = false
    do { _ = try ClipboardPersistence.open(applicationSupport: root, bundleIdentifier: "test.incomplete") }
    catch ClipboardPersistenceError.incompleteStore { incompleteRejected = true }
    try check(incompleteRejected && (try Data(contentsOf: sentinel)) == sentinelData,
              "incomplete nonempty database directories retain all existing files")

    let source = try makeStore()
    let work = source.addCategory(named: "Work")!
    let personal = source.addCategory(named: "Personal")!
    let entry = add(source, "category collision fixture")
    source.assign(entry, to: work)
    source.assign(entry, to: personal)
    let archive = try ClipboardBackup.decode(source.backupSnapshot().preparingForExport().encoded())
    let target = try makeStore()
    target.modelContext.insert(ClipCategory(id: work.id, name: "Personal", createdAt: work.createdAt))
    try target.persistChanges()
    target.refresh()
    _ = try target.importBackup(archive, preview: target.planImport(archive))
    let restored = target.entries.first { $0.id == entry.id }!
    try check(restored.categoryIDs == [work.id.uuidString] && target.categories.count == 1,
              "renamed category and same-name category merge to a single membership")
    let mergedArchive = try ClipboardBackup.decode(target.backupSnapshot().preparingForExport().encoded())
    let roundTrip = try makeStore()
    _ = try roundTrip.importBackup(mergedArchive, preview: roundTrip.planImport(mergedArchive))
    try check(roundTrip.entries.first?.categoryIDs == [work.id.uuidString],
              "merged category memberships survive another export and import")
    restored.categoryIDsData = try JSONEncoder().encode([work.id.uuidString, work.id.uuidString])
    try target.persistChanges()
    target.refresh()
    let repairedArchive = try ClipboardBackup.decode(target.backupSnapshot().preparingForExport().encoded())
    try check(repairedArchive.entries.first?.categoryIDs == [work.id],
              "export recovers repeated memberships written by older versions")

    let metadataStore = try makeStore()
    let overlongName = String(repeating: "x", count: ClipboardStore.maximumCategoryNameLength + 1)
    try check(metadataStore.addCategory(named: overlongName) == nil && metadataStore.lastErrorMessage != nil,
              "new overlong category names are rejected with an actionable error")
    let shortCategory = metadataStore.addCategory(named: "Short")!
    try check(!metadataStore.renameCategory(shortCategory, to: overlongName) && shortCategory.name == "Short",
              "category renaming uses the same length limit without changing saved data")
    let legacyCategory = ClipCategory(name: overlongName)
    metadataStore.modelContext.insert(legacyCategory)
    let legacyTitle = String(repeating: "file-fixture, ", count: 1_000)
    let payload = try JSONEncoder().encode(textPayload("legacy metadata fixture"))
    let legacyEntry = ClipboardEntry(title: legacyTitle, contentTypeRaw: "text", payloadData: payload,
                                    categoryIDsData: try JSONEncoder().encode([legacyCategory.id.uuidString]))
    metadataStore.modelContext.insert(legacyEntry)
    try metadataStore.persistChanges()
    metadataStore.refresh()
    try check(metadataStore.renameCategory(legacyCategory, to: overlongName),
              "unchanged legacy category names remain valid when closing the editor")
    let metadataArchive = try ClipboardBackup.decode(metadataStore.backupSnapshot().preparingForExport().encoded())
    let metadataTarget = try makeStore()
    _ = try metadataTarget.importBackup(metadataArchive, preview: metadataTarget.planImport(metadataArchive))
    try check(metadataTarget.entries.first?.title == legacyTitle
              && metadataTarget.categories.first(where: { $0.id == legacyCategory.id })?.name == overlongName,
              "legacy long category names and file titles round-trip without truncation")

    let oldPasswordID = "com.agilebits.onepassword7"
    let currentPasswordID = "com.1password.1password"
    var suites: [String] = []
    defer { for suite in suites { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) } }
    func isolatedDefaults() -> UserDefaults {
        let suite = "LocalPasteExclusionsRepair.\(UUID())"
        suites.append(suite)
        return UserDefaults(suiteName: suite)!
    }
    func exclusionStore(_ defaults: UserDefaults) throws -> ClipboardStore {
        let container = try ModelContainer(for: ClipboardEntry.self, ClipCategory.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ClipboardStore(modelContainer: container, defaults: defaults)
    }
    let freshDefaults = isolatedDefaults()
    let freshExclusions = try exclusionStore(freshDefaults)
    try check(freshExclusions.isExcluded(bundleIdentifier: oldPasswordID)
              && freshExclusions.isExcluded(bundleIdentifier: currentPasswordID),
              "fresh privacy defaults exclude both 1Password application identifiers")

    let oldDefaults = isolatedDefaults()
    let custom = ExcludedApplication(bundleIdentifier: "synthetic.private.app", name: "Private fixture")
    try oldDefaults.set(JSONEncoder().encode([ExcludedApplication(bundleIdentifier: oldPasswordID, name: "1Password"), custom]),
                        forKey: ClipboardStore.excludedApplicationsKey)
    let migrated = try exclusionStore(oldDefaults)
    try check(migrated.isExcluded(bundleIdentifier: currentPasswordID)
              && migrated.excludedApplications.contains(custom),
              "existing exclusions gain current 1Password only when the old exclusion remains")
    migrated.removeExcludedApplication(migrated.excludedApplications.first { $0.bundleIdentifier == currentPasswordID }!)
    let reopened = try exclusionStore(oldDefaults)
    try check(!reopened.isExcluded(bundleIdentifier: currentPasswordID) && reopened.isExcluded(bundleIdentifier: oldPasswordID),
              "removing the new 1Password exclusion persists across later launches")

    let removedDefaults = isolatedDefaults()
    try removedDefaults.set(JSONEncoder().encode([custom]), forKey: ClipboardStore.excludedApplicationsKey)
    let removed = try exclusionStore(removedDefaults)
    try check(!removed.isExcluded(bundleIdentifier: oldPasswordID)
              && !removed.isExcluded(bundleIdentifier: currentPasswordID) && removed.excludedApplications == [custom],
              "users who removed the old 1Password exclusion retain their exact preferences")
}
