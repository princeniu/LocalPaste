import Foundation

@MainActor func testHistorySession() throws {
    let store = try makeStore()
    let older = add(store, "session older")
    let newer = add(store, "session newer")
    let model = HistoryViewModel(store: store)
    let closedAt = Date(timeIntervalSince1970: 1_000)

    model.select(older)
    model.prepareForPresentation(at: closedAt)
    try check(model.selectedID == older.id && model.scrollToStartRequest == 0,
              "first presentation has no expired browsing session")

    model.recordDismissal(at: closedAt)
    model.prepareForPresentation(at: closedAt.addingTimeInterval(299.999))
    try check(model.selectedID == older.id && model.scrollToStartRequest == 0,
              "reopening before five minutes preserves the browsing position")

    model.recordDismissal(at: closedAt)
    model.prepareForPresentation(at: closedAt.addingTimeInterval(300))
    try check(model.selectedID == newer.id && model.scrollToStartRequest == 1,
              "reopening at five minutes selects and scrolls to the newest card")

    model.recordDismissal(at: closedAt)
    let latest = add(store, "session latest while closed")
    model.prepareForPresentation(at: closedAt.addingTimeInterval(600))
    try check(model.selectedID == latest.id && model.scrollToStartRequest == 2,
              "expired browsing includes new history captured while closed")

    // Wheel-only browsing can leave selection on the first card.
    model.recordDismissal(at: closedAt)
    model.prepareForPresentation(at: closedAt.addingTimeInterval(301))
    try check(model.selectedID == latest.id && model.scrollToStartRequest == 3,
              "wheel-only browsing resets even when selection is already the first card")

    model.select(older)
    model.recordDismissal(at: closedAt.addingTimeInterval(600))
    model.prepareForPresentation(at: closedAt.addingTimeInterval(899))
    try check(model.selectedID == older.id && model.scrollToStartRequest == 3,
              "each dismissal starts a fresh five-minute preservation window")
    model.prepareForPresentation(at: closedAt.addingTimeInterval(2_000))
    try check(model.selectedID == older.id && model.scrollToStartRequest == 3,
              "consumed dismissal does not reset an ongoing browsing session")

    model.query = "session older"
    model.recordDismissal(at: closedAt)
    model.prepareForPresentation(at: closedAt.addingTimeInterval(300))
    try check(model.query == "session older" && model.selectedID == older.id && model.scrollToStartRequest == 4,
              "returning to the start preserves the active search")

    model.query = "no synthetic match"
    model.recordDismissal(at: closedAt)
    model.prepareForPresentation(at: closedAt.addingTimeInterval(300))
    try check(model.visibleEntries.isEmpty && model.selectedID == nil,
              "expired empty results remain safe without a scroll target")
}
