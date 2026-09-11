import Foundation
import SwiftData
import CoreData

enum ClipboardPersistenceError: LocalizedError {
    case incompatibleLegacyStore
    case incompleteStore
    case unreadablePayload

    var errorDescription: String? {
        switch self {
        case .incompatibleLegacyStore:
            return "旧数据库不匹配 LocalPaste，已保留原文件并停止迁移。请先检查旧数据来源。"
        case .incompleteStore:
            return "历史目录已存在，但数据库不完整。已保留目录，请检查后重新打开。"
        case .unreadablePayload:
            return "旧历史含有无法读取的内容，迁移未完成，原数据库仍保留。"
        }
    }
}

@MainActor
enum ClipboardPersistence {
    nonisolated static let productionBundleID = "com.prince.LocalPaste"
    static let schema = Schema([ClipboardEntry.self, ClipCategory.self])

    static func storeURL(applicationSupport: URL, bundleIdentifier: String) -> URL {
        applicationSupport.appendingPathComponent(bundleIdentifier, isDirectory: true)
            .appendingPathComponent("default.store")
    }

    static func open(applicationSupport: URL = .applicationSupportDirectory,
                     bundleIdentifier: String = Bundle.main.bundleIdentifier ?? productionBundleID,
                     legacyURL: URL? = nil) throws -> ModelContainer {
        let destination = storeURL(applicationSupport: applicationSupport, bundleIdentifier: bundleIdentifier)
        let directory = destination.deletingLastPathComponent()
        let files = FileManager.default
        if files.fileExists(atPath: destination.path) { return try container(at: destination) }
        guard !files.fileExists(atPath: directory.path) else { throw ClipboardPersistenceError.incompleteStore }
        try files.createDirectory(at: applicationSupport, withIntermediateDirectories: true)
        // Alternate builds never inspect the shared legacy location by default.
        let legacy = legacyURL ?? (bundleIdentifier == productionBundleID
            ? applicationSupport.appendingPathComponent("default.store") : nil)
        if let legacy, files.fileExists(atPath: legacy.path) {
            try importLegacyStore(from: legacy, to: destination)
        } else {
            try files.createDirectory(at: directory, withIntermediateDirectories: false)
        }
        return try container(at: destination)
    }

    private static func container(at url: URL) throws -> ModelContainer {
        try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
    }

    private static func importLegacyStore(from source: URL, to destination: URL) throws {
        let files = FileManager.default
        let parent = destination.deletingLastPathComponent().deletingLastPathComponent()
        let staging = parent.appendingPathComponent(".LocalPaste-import-\(UUID().uuidString)", isDirectory: true)
        try files.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { if files.fileExists(atPath: staging.path) { try? files.removeItem(at: staging) } }
        let reference = staging.appendingPathComponent("reference", isDirectory: true)
        try files.createDirectory(at: reference, withIntermediateDirectories: false)
        let referenceURL = reference.appendingPathComponent("default.store")
        try autoreleasepool { _ = try container(at: referenceURL) }
        let options: [AnyHashable: Any] = [NSReadOnlyPersistentStoreOption: true,
                                         NSMigratePersistentStoresAutomaticallyOption: false]
        let expected = try NSPersistentStoreCoordinator.metadataForPersistentStore(type: .sqlite, at: referenceURL, options: options)
        let actual = try NSPersistentStoreCoordinator.metadataForPersistentStore(type: .sqlite, at: source, options: options)
        guard let expectedHashes = expected[NSStoreModelVersionHashesKey] as? NSDictionary,
              let actualHashes = actual[NSStoreModelVersionHashesKey] as? NSDictionary,
              expectedHashes.isEqual(actualHashes) else {
            throw ClipboardPersistenceError.incompatibleLegacyStore
        }
        try files.removeItem(at: reference)
        let stagedURL = staging.appendingPathComponent("default.store")
        // Core Data copies SQLite journals and external binary storage using its store-aware API.
        // The shared source is never moved, deleted, or opened for migration.
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: NSManagedObjectModel())
        try coordinator.replacePersistentStore(at: stagedURL, withPersistentStoreFrom: source,
                                               sourceOptions: options, type: .sqlite)
        try autoreleasepool {
            let copy = try container(at: stagedURL)
            let context = ModelContext(copy)
            for entry in try context.fetch(FetchDescriptor<ClipboardEntry>()) {
                guard entry.payload != nil,
                      entry.categoryIDsData.isEmpty || (try? JSONDecoder().decode([String].self, from: entry.categoryIDsData)) != nil else {
                    throw ClipboardPersistenceError.unreadablePayload
                }
            }
            _ = try context.fetch(FetchDescriptor<ClipCategory>())
        }
        // Publish the entire validated directory together, including any external payloads.
        try files.moveItem(at: staging, to: destination.deletingLastPathComponent())
    }
}
