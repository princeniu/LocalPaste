import AppKit

@MainActor private final class DismissalSheetFixture: NSWindow {
    weak var fixtureParent: NSWindow?
    override var sheetParent: NSWindow? { fixtureParent }
}

@MainActor func testPanelDismissal() throws {
    func window() -> NSWindow {
        NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: true)
    }
    let panel = window(), other = window(), child = window(), nestedChild = window()
    func dismiss(_ target: NSWindow?, trackingMenu: Bool = false) -> Bool {
        PanelController.shouldDismissForMouseDown(in: target, panel: panel, menuIsTracking: trackingMenu)
    }
    try check(!dismiss(panel), "clicks within the history panel keep it open")
    try check(dismiss(other), "clicks in another window of the same app dismiss history")
    try check(dismiss(nil), "mouse clicks without a history window dismiss history")
    panel.addChildWindow(child, ordered: .above)
    child.addChildWindow(nestedChild, ordered: .above)
    defer {
        child.removeChildWindow(nestedChild)
        panel.removeChildWindow(child)
    }
    try check(!dismiss(child), "clicks within a panel-owned child window keep history open")
    try check(!dismiss(nestedChild), "nested panel-owned windows keep history open")
    let sheet = DismissalSheetFixture(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: true)
    sheet.fixtureParent = panel
    try check(!dismiss(sheet), "clicks within an attached preview or editor sheet keep history open")
    try check(!dismiss(other, trackingMenu: true), "menu tracking preserves menu item clicks")
    try check(dismiss(other, trackingMenu: false), "outside dismissal resumes after menu tracking ends")
}
