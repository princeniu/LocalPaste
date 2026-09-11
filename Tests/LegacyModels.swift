// Frozen pre-fix models for the legacy store migration fixture. Compile separately.
import Foundation
import SwiftData
import AppKit

struct StoredPasteboardRepresentation: Codable {
    let uti: String
    let data: Data?
    let stringValue: String?
    let filePath: String?
}

struct StoredPasteboardItem: Codable {
    let representations: [StoredPasteboardRepresentation]
}

struct StoredPasteboardPayload: Codable {
    let items: [StoredPasteboardItem]
    let plainText: String
    let displayText: String
    let contentType: String
    let filePaths: [String]
}

enum ClipboardContentType: String {
    case text
    case html
    case richText
    case image
    case fileReference
    case mixed

    var label: String {
        switch self {
        case .text: return "文本"
        case .html: return "HTML"
        case .richText: return "富文本"
        case .image: return "图片"
        case .fileReference: return "文件引用"
        case .mixed: return "多格式"
        }
    }

    var symbolName: String {
        switch self {
        case .text: return "doc.plaintext"
        case .html: return "chevron.left.forwardslash.chevron.right"
        case .richText: return "textformat"
        case .image: return "photo"
        case .fileReference: return "doc"
        case .mixed: return "square.stack.3d.up"
        }
    }
}

@Model
final class ClipboardEntry {
    var id: UUID
    var createdAt: Date
    var sourceBundleIdentifier: String
    var sourceName: String
    var title: String
    var contentTypeRaw: String
    var isFavorite: Bool
    @Attribute(.externalStorage) var payloadData: Data
    var categoryIDsData: Data

    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        sourceBundleIdentifier: String = "",
        sourceName: String = "未知应用",
        title: String,
        contentTypeRaw: String,
        isFavorite: Bool = false,
        payloadData: Data,
        categoryIDsData: Data = Data()
    ) {
        self.id = id
        self.createdAt = createdAt
        self.sourceBundleIdentifier = sourceBundleIdentifier
        self.sourceName = sourceName
        self.title = title
        self.contentTypeRaw = contentTypeRaw
        self.isFavorite = isFavorite
        self.payloadData = payloadData
        self.categoryIDsData = categoryIDsData
    }

    var contentType: ClipboardContentType {
        ClipboardContentType(rawValue: contentTypeRaw) ?? .mixed
    }

    var payload: StoredPasteboardPayload? {
        try? JSONDecoder().decode(StoredPasteboardPayload.self, from: payloadData)
    }

    var categoryIDs: [String] {
        (try? JSONDecoder().decode([String].self, from: categoryIDsData)) ?? []
    }
}

@Model
final class ClipCategory {
    var id: UUID
    var name: String
    var createdAt: Date

    init(id: UUID = UUID(), name: String, createdAt: Date = .now) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
    }
}

struct ExcludedApplication: Codable, Hashable, Identifiable {
    let bundleIdentifier: String
    let name: String

    var id: String { bundleIdentifier }
}
