import Foundation
import CryptoKit

enum BackupError: LocalizedError {
    case invalid, unsupportedVersion, tooLarge, tooManyEntries, historyChanged
    var errorDescription: String? {
        switch self {
        case .invalid: return "备份已损坏或格式不正确，未导入任何内容。"
        case .unsupportedVersion: return "此备份来自更新的版本，请先更新拾贴。"
        case .tooLarge: return "备份超过 256 MB，暂时无法处理。"
        case .tooManyEntries: return "合并后普通历史将超过 5,000 条。请先将需要长期保留的本机记录加入收藏，再重试。"
        case .historyChanged: return "历史已更新，请确认新的导入预览。"
        }
    }
}

struct ClipboardBackup: Codable, Sendable {
    struct Category: Codable, Sendable {
        let id: UUID
        let name: String
        let createdAt: Date
    }
    struct Entry: Codable, Sendable {
        let id: UUID
        let createdAt: Date
        let sourceBundleIdentifier: String
        let sourceName: String
        let title: String
        let contentTypeRaw: String
        let isFavorite: Bool
        let payloadData: Data
        let payloadSHA256: String
        let categoryIDs: [UUID]
    }

    let format: String
    let version: Int
    let createdAt: Date
    let categories: [Category]
    let entries: [Entry]
    private(set) var isValidated = false

    private enum CodingKeys: String, CodingKey {
        case format, version, createdAt, categories, entries
    }

    static let maximumBytes = 256 * 1_024 * 1_024

    init(categories: [Category], entries: [Entry], createdAt: Date = .now) {
        format = "com.clipmori.backup"
        version = 1
        self.createdAt = createdAt
        self.categories = categories
        self.entries = entries
    }

    static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    func encoded() throws -> Data {
        try validate()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let data = try encoder.encode(self)
        guard data.count <= Self.maximumBytes else { throw BackupError.tooLarge }
        return data
    }

    static func decode(_ data: Data) throws -> ClipboardBackup {
        guard data.count <= maximumBytes else { throw BackupError.tooLarge }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        var archive: ClipboardBackup
        do { archive = try decoder.decode(Self.self, from: data) }
        catch { throw BackupError.invalid }
        try archive.validate()
        archive.isValidated = true
        return archive
    }

    static func read(from url: URL) throws -> ClipboardBackup {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var data = Data()
        while let chunk = try handle.read(upToCount: min(1_024 * 1_024, maximumBytes - data.count + 1)), !chunk.isEmpty {
            data.append(chunk)
            guard data.count <= maximumBytes else { throw BackupError.tooLarge }
        }
        return try decode(data)
    }

    func write(to url: URL) throws {
        try encoded().write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    func validate() throws {
        guard format == "com.clipmori.backup" else { throw BackupError.invalid }
        guard version == 1 else { throw BackupError.unsupportedVersion }
        guard validDate(createdAt), entries.count <= 50_000, categories.count <= 5_000,
              Set(entries.map(\.id)).count == entries.count,
              Set(categories.map(\.id)).count == categories.count else { throw BackupError.invalid }
        let categoryIDs = Set(categories.map(\.id))
        for category in categories {
            guard validDate(category.createdAt), !category.name.isEmpty,
                  category.name == category.name.trimmingCharacters(in: .whitespacesAndNewlines),
                  category.name.count <= 1_000 else { throw BackupError.invalid }
        }
        var bytes = 0
        for entry in entries {
            bytes += entry.payloadData.count
            guard bytes <= Self.maximumBytes else { throw BackupError.tooLarge }
            guard validDate(entry.createdAt), entry.title.count <= 8_192,
                  entry.sourceName.count <= 1_024, entry.sourceBundleIdentifier.count <= 1_024,
                  ClipboardContentType(rawValue: entry.contentTypeRaw) != nil,
                  Set(entry.categoryIDs).isSubset(of: categoryIDs),
                  Set(entry.categoryIDs).count == entry.categoryIDs.count,
                  Self.digest(entry.payloadData) == entry.payloadSHA256,
                  let payload = try? JSONDecoder().decode(StoredPasteboardPayload.self, from: entry.payloadData),
                  payload.contentType == entry.contentTypeRaw, !payload.items.isEmpty,
                  payload.items.allSatisfy({ !$0.representations.isEmpty && $0.representations.allSatisfy({ !$0.uti.isEmpty && $0.uti.count <= 512 }) })
            else { throw BackupError.invalid }
        }
    }

    private func validDate(_ date: Date) -> Bool {
        date.timeIntervalSince1970.isFinite && date >= .distantPast && date <= .distantFuture
    }
}

struct BackupImportPlan {
    let revision: Int
    let previousLimit: Int
    let requiredLimit: Int
    let categories: [ClipboardBackup.Category]
    let entries: [ClipboardBackup.Entry]
    let categoryMapping: [UUID: UUID]
    let skippedCount: Int
    var favoriteCount: Int { entries.filter(\.isFavorite).count }
    var fileCount: Int { entries.filter { $0.contentTypeRaw == "fileReference" }.count }
}

extension ClipboardStore {
    func backupSnapshot() throws -> ClipboardBackup {
        let records = try entries.map { entry -> ClipboardBackup.Entry in
            let ids = entry.categoryIDsData.isEmpty ? [] : try JSONDecoder().decode([String].self, from: entry.categoryIDsData)
            let categoryIDs = try ids.map { value -> UUID in
                guard let id = UUID(uuidString: value) else { throw BackupError.invalid }
                return id
            }
            return .init(id: entry.id, createdAt: entry.createdAt,
                         sourceBundleIdentifier: entry.sourceBundleIdentifier, sourceName: entry.sourceName,
                         title: entry.title, contentTypeRaw: entry.contentTypeRaw, isFavorite: entry.isFavorite,
                         payloadData: entry.payloadData, payloadSHA256: "", categoryIDs: categoryIDs)
        }
        // Hashing and serialization happen off the main thread, after this value snapshot.
        return ClipboardBackup(categories: categories.map { .init(id: $0.id, name: $0.name, createdAt: $0.createdAt) }, entries: records)
    }

    func planImport(_ backup: ClipboardBackup) throws -> BackupImportPlan {
        guard backup.isValidated else { throw BackupError.invalid }
        var mapping: [UUID: UUID] = [:]
        var additions: [ClipboardBackup.Category] = []
        for category in backup.categories {
            if let match = categories.first(where: { $0.id == category.id }) {
                mapping[category.id] = match.id
            } else if let match = categories.first(where: { $0.name.caseInsensitiveCompare(category.name) == .orderedSame }) {
                mapping[category.id] = match.id
            } else if let match = additions.first(where: { $0.name.caseInsensitiveCompare(category.name) == .orderedSame }) {
                mapping[category.id] = match.id
            } else {
                mapping[category.id] = category.id
                additions.append(category)
            }
        }
        let existingIDs = Set(entries.map(\.id))
        let newEntries = backup.entries.filter { !existingIDs.contains($0.id) }
        let normalCount = entries.filter { !$0.isFavorite }.count + newEntries.filter { !$0.isFavorite }.count
        guard normalCount <= 5_000 else { throw BackupError.tooManyEntries }
        return BackupImportPlan(revision: revision, previousLimit: historyLimit,
                                requiredLimit: max(historyLimit, ((normalCount + 49) / 50) * 50), categories: additions,
                                entries: newEntries, categoryMapping: mapping,
                                skippedCount: backup.entries.count - newEntries.count)
    }

    func importBackup(_ backup: ClipboardBackup, preview: BackupImportPlan) throws -> BackupImportPlan {
        guard revision == preview.revision, historyLimit == preview.previousLimit,
              !modelContext.hasChanges else { throw BackupError.historyChanged }
        let plan = try planImport(backup)
        do {
            for category in plan.categories {
                modelContext.insert(ClipCategory(id: category.id, name: category.name, createdAt: category.createdAt))
            }
            for record in plan.entries {
                let ids = try record.categoryIDs.map { id -> String in
                    guard let mapped = plan.categoryMapping[id] else { throw BackupError.invalid }
                    return mapped.uuidString
                }
                modelContext.insert(ClipboardEntry(id: record.id, createdAt: record.createdAt,
                    sourceBundleIdentifier: record.sourceBundleIdentifier, sourceName: record.sourceName,
                    title: record.title, contentTypeRaw: record.contentTypeRaw, isFavorite: record.isFavorite,
                    payloadData: record.payloadData, categoryIDsData: try JSONEncoder().encode(ids)))
            }
            try persistChanges()
        } catch {
            modelContext.rollback()
            _ = refresh()
            throw error
        }
        // Raising the limit precedes refresh, so restored records are never immediately pruned.
        if plan.requiredLimit > historyLimit { historyLimit = plan.requiredLimit }
        lastErrorMessage = nil
        _ = refresh()
        return plan
    }
}

extension ClipboardBackup {
    func preparingForExport() -> ClipboardBackup {
        ClipboardBackup(categories: categories, entries: entries.map {
            Entry(id: $0.id, createdAt: $0.createdAt, sourceBundleIdentifier: $0.sourceBundleIdentifier,
                  sourceName: $0.sourceName, title: $0.title, contentTypeRaw: $0.contentTypeRaw,
                  isFavorite: $0.isFavorite, payloadData: $0.payloadData,
                  payloadSHA256: Self.digest($0.payloadData), categoryIDs: $0.categoryIDs)
        }, createdAt: createdAt)
    }
}
