import Foundation
import CryptoKit

struct ClipboardContentSummary: Codable, Sendable {
    let text: String
    let plainText: String?
    let searchText: String
    let payloadBytes: Int
}

/// Rebuildable metadata beside the database. Payloads remain in SwiftData.
/// Entry payloads are immutable; IDs and their descriptive metadata identify a summary.
@MainActor
final class ClipboardSummaryCache {
    private struct Record: Codable, Sendable {
        let id: UUID
        let createdAt: Date
        let title: String
        let sourceName: String
        let contentType: String
        let summary: ClipboardContentSummary

        func matches(_ entry: ClipboardEntry) -> Bool {
            id == entry.id && createdAt == entry.createdAt && title == entry.title
                && sourceName == entry.sourceName && contentType == entry.contentTypeRaw
        }
    }
    private struct Archive: Codable, Sendable {
        let version: Int
        let records: [Record]
    }
    private struct Envelope: Codable {
        let data: Data
        let sha256: String
    }

    nonisolated static let maximumBytes = 16 * 1_024 * 1_024
    private let url: URL?
    private let writer = DispatchQueue(label: "com.clipmori.summary-cache", qos: .utility)
    private var records: [UUID: Record] = [:]

    init(url: URL?) {
        self.url = url
        guard let url,
              let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size <= Self.maximumBytes,
              let data = try? Data(contentsOf: url), data.count <= Self.maximumBytes,
              let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              envelope.sha256 == Self.digest(envelope.data),
              let archive = try? JSONDecoder().decode(Archive.self, from: envelope.data), archive.version == 1 else { return }
        for record in archive.records where record.summary.payloadBytes >= 0 {
            records[record.id] = record
        }
    }

    func summary(for entry: ClipboardEntry) -> ClipboardContentSummary? {
        guard let record = records[entry.id], record.matches(entry) else { return nil }
        return record.summary
    }

    func save(entries: [ClipboardEntry], summaries: [UUID: ClipboardContentSummary]) {
        guard let url else { return }
        if entries.isEmpty {
            records.removeAll()
            writer.async { try? FileManager.default.removeItem(at: url) }
            return
        }
        var remaining = Self.maximumBytes / 2 - 1_024
        var updated: [UUID: Record] = [:]
        var changed = false
        for entry in entries {
            guard let summary = summaries[entry.id] else { continue }
            // JSON can escape a byte into six bytes. Bound the on-disk index before encoding.
            let textBytes = summary.text.utf8.count + (summary.plainText?.utf8.count ?? 0)
                + summary.searchText.utf8.count + entry.title.utf8.count + entry.sourceName.utf8.count
            let estimate = textBytes * 6 + 1_024
            guard estimate <= remaining else { continue }
            remaining -= estimate
            if let old = records[entry.id], old.matches(entry) {
                updated[entry.id] = old
            } else {
                updated[entry.id] = Record(id: entry.id, createdAt: entry.createdAt, title: entry.title,
                    sourceName: entry.sourceName, contentType: entry.contentTypeRaw, summary: summary)
                changed = true
            }
        }
        changed = changed || Set(updated.keys) != Set(records.keys)
        records = updated
        guard changed else { return }
        let archive = Archive(version: 1, records: Array(updated.values))
        writer.async {
            guard let payload = try? JSONEncoder().encode(archive),
                  let data = try? JSONEncoder().encode(Envelope(data: payload, sha256: Self.digest(payload))),
                  data.count <= Self.maximumBytes else { return }
            // Protect the replacement before publishing it, including the first write.
            let temporary = url.deletingLastPathComponent().appendingPathComponent(".summary-\(UUID()).tmp")
            defer { try? FileManager.default.removeItem(at: temporary) }
            guard FileManager.default.createFile(atPath: temporary.path, contents: nil,
                attributes: [.posixPermissions: 0o600]) else { return }
            do {
                try data.write(to: temporary)
                if FileManager.default.fileExists(atPath: url.path) {
                    _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary, options: .usingNewMetadataOnly)
                } else {
                    try FileManager.default.moveItem(at: temporary, to: url)
                }
            } catch { /* This optional cache can always be rebuilt from the database. */ }
        }
    }

    /// Used when verifying durable cache behavior without waiting on a timer.
    func waitForPendingWrites() { writer.sync {} }

    nonisolated private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
