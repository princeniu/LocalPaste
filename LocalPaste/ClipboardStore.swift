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

@MainActor
final class ClipboardStore: ObservableObject {
    static let historyLimitKey = "historyLimit"
    static let pausedKey = "monitorPaused"
    static let excludedApplicationsKey = "excludedApplications"
    static let defaultHistoryLimit = 500

    let modelContext: ModelContext
    private let defaults: UserDefaults
    private let allowsSave: Bool
    private struct ContentSummary {
        let text: String
        let plainText: String?
        let searchText: String
    }
    private var summaries: [UUID: ContentSummary] = [:]

    @Published private(set) var entries: [ClipboardEntry] = []
    @Published private(set) var categories: [ClipCategory] = []
    @Published private(set) var revision = 0
    @Published var lastErrorMessage: String?
    @Published var isPaused: Bool {
        didSet { defaults.set(isPaused, forKey: Self.pausedKey) }
    }
    @Published var historyLimit: Int {
        didSet {
            let bounded = max(50, min(historyLimit, 5_000))
            if historyLimit != bounded {
                historyLimit = bounded
                return
            }
            defaults.set(historyLimit, forKey: Self.historyLimitKey)
            pruneHistory()
        }
    }
    @Published var excludedApplications: [ExcludedApplication] {
        didSet { saveExcludedApplications() }
    }

    init(modelContainer: ModelContainer, defaults: UserDefaults = .standard) {
        self.modelContext = ModelContext(modelContainer)
        self.modelContext.autosaveEnabled = false
        self.allowsSave = modelContainer.configurations.allSatisfy(\.allowsSave)
        self.defaults = defaults
        self.isPaused = defaults.bool(forKey: Self.pausedKey)
        let configuredLimit = defaults.object(forKey: Self.historyLimitKey) as? Int ?? Self.defaultHistoryLimit
        self.historyLimit = max(50, min(configuredLimit, 5_000))
        self.excludedApplications = Self.loadExcludedApplications(from: defaults)
        refresh()
    }

    @discardableResult
    func refresh() -> Bool {
        do {
            let entryDescriptor = FetchDescriptor<ClipboardEntry>(sortBy: [SortDescriptor(\ClipboardEntry.createdAt, order: .reverse)])
            let categoryDescriptor = FetchDescriptor<ClipCategory>(sortBy: [SortDescriptor(\ClipCategory.createdAt, order: .forward)])
            let fetchedEntries = try modelContext.fetch(entryDescriptor)
            let fetchedCategories = try modelContext.fetch(categoryDescriptor)
            let ids = Set(fetchedEntries.map(\.id))
            summaries = summaries.filter { ids.contains($0.key) }
            for entry in fetchedEntries where summaries[entry.id] == nil {
                let payload = entry.payload
                let plainText = payload.flatMap { PayloadText.plainText(from: $0) }
                let text = plainText ?? payload?.displayText ?? "无法读取内容"
                summaries[entry.id] = ContentSummary(text: text, plainText: plainText,
                    searchText: [entry.title, entry.sourceName, text].joined(separator: " ").lowercased())
            }
            entries = fetchedEntries
            categories = fetchedCategories
            revision += 1
            return true
        } catch {
            lastErrorMessage = "读取本地历史失败：\(error.localizedDescription)"
            return false
        }
    }

    @discardableResult
    func addEntry(
        payload: StoredPasteboardPayload,
        sourceBundleIdentifier: String,
        sourceName: String,
        title: String
    ) -> ClipboardEntry? {
        guard !payload.items.isEmpty else { return nil }
        do {
            let encoded = try JSONEncoder().encode(payload)
            let entry = ClipboardEntry(
                title: title,
                contentTypeRaw: payload.contentType,
                payloadData: encoded
            )
            entry.sourceBundleIdentifier = sourceBundleIdentifier
            entry.sourceName = sourceName
            modelContext.insert(entry)
            try persistChanges()
            refresh()
            pruneHistory()
            return entry
        } catch {
            modelContext.rollback()
            refresh()
            lastErrorMessage = "保存剪贴板历史失败：\(error.localizedDescription)"
            return nil
        }
    }

    func toggleFavorite(_ entry: ClipboardEntry) {
        entry.isFavorite.toggle()
        if saveAndRefresh() { pruneHistory() }
    }

    @discardableResult
    func addCategory(named name: String) -> ClipCategory? {
        guard let cleaned = validatedCategoryName(name) else { return nil }
        let category = ClipCategory(name: cleaned)
        modelContext.insert(category)
        return saveAndRefresh() ? category : nil
    }

    @discardableResult
    func renameCategory(_ category: ClipCategory, to name: String) -> Bool {
        guard let cleaned = validatedCategoryName(name, excluding: category.id) else { return false }
        category.name = cleaned
        return saveAndRefresh()
    }

    private func validatedCategoryName(_ name: String, excluding id: UUID? = nil) -> String? {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            lastErrorMessage = "分类名称不能为空。"
            return nil
        }
        guard !categories.contains(where: { $0.id != id && $0.name.caseInsensitiveCompare(cleaned) == .orderedSame }) else {
            lastErrorMessage = "已有同名分类。"
            return nil
        }
        lastErrorMessage = nil
        return cleaned
    }

    func deleteCategory(_ category: ClipCategory) {
        let categoryID = category.id.uuidString
        for entry in entries where entry.categoryIDs.contains(categoryID) {
            entry.categoryIDsData = encodeCategoryIDs(entry.categoryIDs.filter { $0 != categoryID })
        }
        modelContext.delete(category)
        saveAndRefresh()
    }

    func assign(_ entry: ClipboardEntry, to category: ClipCategory) {
        var ids = entry.categoryIDs
        let id = category.id.uuidString
        if !ids.contains(id) { ids.append(id) }
        entry.categoryIDsData = encodeCategoryIDs(ids)
        saveAndRefresh()
    }

    func remove(_ entry: ClipboardEntry, from category: ClipCategory) {
        let id = category.id.uuidString
        entry.categoryIDsData = encodeCategoryIDs(entry.categoryIDs.filter { $0 != id })
        saveAndRefresh()
    }

    func delete(_ entry: ClipboardEntry) {
        modelContext.delete(entry)
        saveAndRefresh()
    }

    func clearHistory(preservingFavorites: Bool = true) {
        for entry in entries where !preservingFavorites || !entry.isFavorite {
            modelContext.delete(entry)
        }
        saveAndRefresh()
    }

    func addExcludedApplication(bundleIdentifier: String, name: String) {
        guard !bundleIdentifier.isEmpty else { return }
        guard !excludedApplications.contains(where: { $0.bundleIdentifier == bundleIdentifier }) else { return }
        excludedApplications.append(ExcludedApplication(bundleIdentifier: bundleIdentifier, name: name))
    }

    func removeExcludedApplication(_ app: ExcludedApplication) {
        excludedApplications.removeAll { $0.bundleIdentifier == app.bundleIdentifier }
    }

    func isExcluded(bundleIdentifier: String?) -> Bool {
        guard let bundleIdentifier else { return false }
        return excludedApplications.contains { $0.bundleIdentifier == bundleIdentifier }
    }

    func payload(for entry: ClipboardEntry) -> StoredPasteboardPayload? {
        entry.payload
    }

    func plainText(for entry: ClipboardEntry) -> String? {
        summaries[entry.id]?.plainText
    }

    func displayText(for entry: ClipboardEntry) -> String {
        summaries[entry.id]?.text ?? "无法读取内容"
    }

    func searchText(for entry: ClipboardEntry) -> String {
        summaries[entry.id]?.searchText ?? ""
    }

    private func pruneHistory() {
        let removable = entries
            .filter { !$0.isFavorite }
            .sorted { $0.createdAt < $1.createdAt }
        let overflow = max(0, removable.count - historyLimit)
        guard overflow > 0 else { return }
        for entry in removable.prefix(overflow) {
            modelContext.delete(entry)
        }
        saveAndRefresh()
    }

    @discardableResult
    private func saveAndRefresh() -> Bool {
        do {
            try persistChanges()
            return refresh()
        } catch {
            modelContext.rollback()
            refresh()
            lastErrorMessage = "保存本地设置失败：\(error.localizedDescription)"
            return false
        }
    }

    private func persistChanges() throws {
        // Some SwiftData runtimes log a read-only save failure without throwing it.
        guard allowsSave else { throw CocoaError(.fileWriteNoPermission) }
        try modelContext.save()
        guard !modelContext.hasChanges else {
            throw NSError(domain: "LocalPaste", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "更改尚未写入本地数据库。"])
        }
    }

    private func encodeCategoryIDs(_ ids: [String]) -> Data {
        (try? JSONEncoder().encode(ids)) ?? Data()
    }

    private func saveExcludedApplications() {
        do {
            defaults.set(try JSONEncoder().encode(excludedApplications), forKey: Self.excludedApplicationsKey)
        } catch {
            lastErrorMessage = "保存排除应用失败：\(error.localizedDescription)"
        }
    }

    private static func loadExcludedApplications(from defaults: UserDefaults) -> [ExcludedApplication] {
        if let data = defaults.data(forKey: Self.excludedApplicationsKey),
           let apps = try? JSONDecoder().decode([ExcludedApplication].self, from: data) {
            return apps
        }
        return [
            ExcludedApplication(bundleIdentifier: "com.agilebits.onepassword7", name: "1Password"),
            ExcludedApplication(bundleIdentifier: "com.bitwarden.desktop", name: "Bitwarden"),
            ExcludedApplication(bundleIdentifier: "com.lastpass.LastPass", name: "LastPass")
        ]
    }
}
