import AppKit
import SwiftData

@MainActor func testHistoryUX() throws {
    func key(_ code: UInt16, _ modifiers: NSEvent.ModifierFlags = [], editing: Bool = false,
             marked: Bool = false, navigation: Bool = true, undo: Bool = false) -> PanelController.KeyboardAction {
        PanelController.keyboardAction(keyCode: code, modifiers: modifiers, editingText: editing,
            hasMarkedText: marked, navigationFocused: navigation, cardFocused: false, canUndo: undo)
    }
    try check(key(36, editing: true) == .paste(plainText: false), "Enter in search pastes the selected result")
    try check(key(36, .shift, editing: true) == .paste(plainText: true)
              && key(76, .shift) == .paste(plainText: true), "Shift Enter supports plain text in search and navigation")
    try check(key(36, editing: true, marked: true) == .native
              && key(53, editing: true, marked: true) == .native,
              "input-method composition retains Enter and Escape instead of pasting or closing")
    try check(key(53, editing: true) == .close, "Escape closes search in one press when not composing")
    try check(key(123, editing: true) == .native && key(124, editing: true) == .native,
              "search caret arrow keys remain native")
    try check(key(6, .command, editing: true, undo: true) == .native
              && key(6, .command, undo: true) == .undo && key(6, .command) == .native,
              "Command Z preserves text editing and only restores history when undo is available")
    try check(key(3, .command, editing: true) == .focusSearch
              && key(3, .command, marked: true) == .native,
              "Command F focuses search without interrupting composition")
    try check(key(36, navigation: false) == .native && key(49, navigation: false) == .native,
              "focused controls retain native Enter and Space actions")
    try check(key(36, .command, editing: true) == .native && key(124, .option) == .native,
              "unassigned modified keys are not consumed as paste or navigation")
    try check(key(115) == .boundary(first: true) && key(119) == .boundary(first: false),
              "Home and End explicitly select list boundaries")

    let store = try makeStore()
    let older = add(store, "UX older"), latest = add(store, "UX latest")
    let model = HistoryViewModel(store: store)
    model.select(latest); model.moveSelection(by: -1)
    try check(model.selectedID == latest.id, "left arrow at the newest entry does not wrap to the oldest")
    model.select(older); model.moveSelection(by: 1)
    try check(model.selectedID == older.id, "right arrow at the oldest entry does not wrap to the newest")
    model.selectBoundary(first: true); let startRequest = model.scrollToStartRequest
    model.selectBoundary(first: false)
    try check(model.selectedID == older.id && startRequest == 1, "explicit boundary navigation selects the expected ends")
    store.toggleFavorite(older)
    model.selectedCategoryID = "favorites"; model.query = "older"; model.previewEntryID = older.id
    model.returnToLatest()
    try check(model.query.isEmpty && model.selectedCategoryID == nil && model.previewEntryID == nil
              && model.selectedID == latest.id && model.visibleEntries.count == 2,
              "return to latest clears temporary search and category filters")
    let request = model.scrollToStartRequest; model.returnToLatest()
    try check(model.scrollToStartRequest == request + 1 && model.selectedID == latest.id,
              "return to latest scrolls even if the latest card was already selected")

    let now = Date()
    let categoryA = store.addCategory(named: "Undo A")!, categoryB = store.addCategory(named: "Undo B")!
    store.assign(older, to: categoryA); store.assign(older, to: categoryB)
    let originalID = older.id, originalDate = older.createdAt, originalPayload = older.payloadData
    let originalSource = older.sourceBundleIdentifier, originalSourceName = older.sourceName
    let originalTitle = older.title, originalType = older.contentTypeRaw
    try check(store.deleteWithUndo(older, at: now) && store.entries.count == 1
              && store.canUndoDeletion(at: now.addingTimeInterval(9.999)),
              "single deletion exposes undo for ten seconds")
    let restored = store.undoDeletion(at: now.addingTimeInterval(1))!
    try check(restored.id == originalID && restored.createdAt == originalDate
              && restored.payloadData == originalPayload && restored.sourceBundleIdentifier == originalSource
              && restored.sourceName == originalSourceName && restored.title == originalTitle
              && restored.contentTypeRaw == originalType && restored.isFavorite
              && Set(restored.categoryIDs) == Set([categoryA.id.uuidString, categoryB.id.uuidString]),
              "undo restores original identity, payload, metadata, favorite and categories")
    try check(!store.canUndoDeletion(at: now) && store.undoDeletion(at: now) == nil,
              "a successful undo cannot restore the same item twice")
    _ = store.deleteWithUndo(restored, at: now)
    store.deleteCategory(categoryB)
    let withoutDeletedCategory = store.undoDeletion(at: now.addingTimeInterval(1))!
    try check(withoutDeletedCategory.categoryIDs == [categoryA.id.uuidString],
              "undo does not recreate categories intentionally removed after deletion")
    _ = store.deleteWithUndo(withoutDeletedCategory, at: now)
    try check(store.undoDeletion(at: now.addingTimeInterval(10)) == nil && store.entries.count == 1,
              "undo expires at the ten-second boundary without resurrecting history")

    let first = add(store, "delete first"), second = add(store, "delete second")
    let firstID = first.id, secondID = second.id
    _ = store.deleteWithUndo(first, at: now); _ = store.deleteWithUndo(second, at: now)
    _ = store.undoDeletion(at: now.addingTimeInterval(1))
    try check(store.entries.contains { $0.id == secondID } && !store.entries.contains { $0.id == firstID },
              "undo retains only the most recent single deletion")
    _ = store.deleteWithUndo(store.entries[0], at: now)
    store.clearHistory(preservingFavorites: false)
    try check(!store.canUndoDeletion(at: now) && store.undoDeletion(at: now) == nil && store.entries.isEmpty,
              "clearing history discards pending single-item undo")

    let bounded = try makeStore(limit: 50)
    let victim = add(bounded, "bounded victim"), victimID = victim.id
    _ = bounded.deleteWithUndo(victim, at: now)
    for index in 0..<50 { add(bounded, "replacement \(index)") }
    let existingIDs = Set(bounded.entries.map(\.id))
    try check(bounded.undoDeletion(at: now.addingTimeInterval(1)) == nil
              && Set(bounded.entries.map(\.id)) == existingIDs && bounded.canUndoDeletion(at: now.addingTimeInterval(1)),
              "undo at a full history limit preserves newer entries and remains retryable")
    bounded.historyLimit = 51
    let retry = bounded.undoDeletion(at: now.addingTimeInterval(2))!
    try check(retry.id == victimID && bounded.entries.count == 51 && bounded.lastErrorMessage == nil,
              "raising the limit allows undo without pruning existing history")
    bounded.toggleFavorite(retry); bounded.historyLimit = 50
    _ = bounded.deleteWithUndo(retry, at: now)
    try check(bounded.undoDeletion(at: now.addingTimeInterval(1))?.isFavorite == true && bounded.entries.count == 51,
              "restoring a favorite does not consume ordinary-history slots")

    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ClipmoriUndoReadOnly-\(UUID())")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("history.store")
    let seed = try ModelContainer(for: ClipboardEntry.self, ClipCategory.self, configurations: ModelConfiguration(url: url))
    let context = ModelContext(seed); context.autosaveEnabled = false
    let seeded = ClipboardEntry(title: "read only original", contentTypeRaw: "text", payloadData: Data("fixture".utf8))
    let seededID = seeded.id; context.insert(seeded); try context.save()
    let readOnly = try ModelContainer(for: ClipboardEntry.self, ClipCategory.self, configurations: ModelConfiguration(url: url, allowsSave: false))
    let denied = ClipboardStore(modelContainer: readOnly, defaults: UserDefaults(suiteName: "ClipmoriUndoDenied.\(UUID())")!)
    try check(!denied.deleteWithUndo(denied.entries[0], at: now) && denied.entries.first?.id == seededID
              && !denied.canUndoDeletion(at: now) && denied.lastErrorMessage != nil,
              "failed deletion rolls back the original record and does not advertise undo")
}
