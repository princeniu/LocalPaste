import Foundation
import AppKit
import SwiftData
import SwiftUI
import CryptoKit

struct RegressionFailure: Error { let message: String }
func check(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
    guard try condition() else { throw RegressionFailure(message: message) }
    log("PASS \(message)")
}
func log(_ text: String) { FileHandle.standardOutput.write(Data((text + "\n").utf8)) }
@MainActor func makeStore(limit: Int = 500, allowsSave: Bool = true) throws -> ClipboardStore {
    let container = try ModelContainer(for: ClipboardEntry.self, ClipCategory.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true, allowsSave: allowsSave))
    let defaults = UserDefaults(suiteName: "LocalPasteRegression.\(UUID())")!
    defaults.set(limit, forKey: ClipboardStore.historyLimitKey)
    return ClipboardStore(modelContainer: container, defaults: defaults)
}
func textPayload(_ text: String) -> StoredPasteboardPayload {
    StoredPasteboardPayload(items: [.init(representations: [.init(uti: "public.utf8-plain-text", data: Data(text.utf8), stringValue: text, filePath: nil)])], plainText: text, displayText: text, contentType: "text", filePaths: [])
}
@MainActor @discardableResult func add(_ store: ClipboardStore, _ text: String) -> ClipboardEntry {
    store.addEntry(payload: textPayload(text), sourceBundleIdentifier: "synthetic.test", sourceName: "人工样例", title: text)!
}
func namedBoard() -> NSPasteboard { NSPasteboard(name: .init("LocalPasteRegression.\(UUID())")) }
func write(_ board: NSPasteboard, text: String) { board.clearContents(); board.setString(text, forType: .string) }

@MainActor func testStore() throws {
    let store = try makeStore(limit: 50)
    let vm = HistoryViewModel(store: store)
    let entry = add(store, "first")
    try check(vm.visibleEntries.count == 1, "new history refreshes the cached view model")
    let a = store.addCategory(named: "A")!, b = store.addCategory(named: "B")!
    store.assign(entry, to: a); vm.selectedCategoryID = a.id.uuidString
    store.deleteCategory(a)
    try check(vm.selectedCategoryID == nil && vm.visibleEntries.count == 1, "deleting selected category returns to all history")
    let c = store.addCategory(named: "C")!
    try check(!store.renameCategory(c, to: " b ") && c.name == "C", "rename rejects case-insensitive duplicate without changing original")
    try check(store.lastErrorMessage != nil, "category failure exposes an error")
    try check(store.renameCategory(b, to: "b"), "category can rename itself")
    try check(store.addCategory(named: "  ") == nil, "empty category rejected")
    store.toggleFavorite(entry); vm.selectedCategoryID = "favorites"
    store.toggleFavorite(entry)
    try check(vm.visibleEntries.isEmpty && vm.selectedID == nil && vm.emptyTitle == "还没有收藏", "removing favorite repairs selection and empty state")
    vm.selectedCategoryID = nil; store.toggleFavorite(entry)
    for i in 0..<55 { add(store, "normal \(i)") }
    try check(store.entries.count == 51 && store.entries.filter{ !$0.isFavorite }.count == 50, "history limit preserves favorite")
    store.toggleFavorite(entry)
    try check(store.entries.count == 50 && !store.entries.contains(where: { $0.id == entry.id }), "unfavorite prunes oldest normal entry immediately")
    let keep = store.entries[0]; store.toggleFavorite(keep); store.clearHistory()
    try check(store.entries.count == 1 && store.entries[0].isFavorite, "clear history retains favorite")
    let deniedDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("LocalPasteReadOnly-\(UUID())")
    try FileManager.default.createDirectory(at: deniedDirectory, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: deniedDirectory) }
    let deniedURL = deniedDirectory.appendingPathComponent("history.store")
    try autoreleasepool {
        _ = try ModelContainer(for: ClipboardEntry.self, ClipCategory.self, configurations: ModelConfiguration(url: deniedURL))
    }
    let readOnly = try ModelContainer(for: ClipboardEntry.self, ClipCategory.self, configurations: ModelConfiguration(url: deniedURL, allowsSave: false))
    let denied = ClipboardStore(modelContainer: readOnly, defaults: UserDefaults(suiteName: "LocalPasteReadOnly.\(UUID())")!)
    let result = denied.addEntry(payload: textPayload("must not save"), sourceBundleIdentifier: "test", sourceName: "Test", title: "denied")
    try check(result == nil && denied.lastErrorMessage != nil && denied.entries.isEmpty, "save failure rolls back and exposes error")
    let failedCategory = denied.addCategory(named: "unsaved")
    try check(failedCategory == nil && denied.categories.isEmpty, "category save failure does not return a false success")
}

@MainActor func testCaptureAndPaste() throws {
    let board = namedBoard(); defer { board.releaseGlobally() }
    let store = try makeStore()
    let app = NSRunningApplication.current
    let monitor = ClipboardMonitor(store: store, pasteboard: board, frontmostApplication: { app })
    store.isPaused = true; write(board, text: "paused secret fixture"); store.isPaused = false; monitor.poll()
    try check(store.entries.isEmpty, "resume discards copy made during pause before a poll")
    write(board, text: "after resume"); monitor.poll()
    try check(store.entries.count == 1, "copy after resume is captured")
    let html = "<html><head><style>body{color:red}</style><script>hidden()</script></head><body><p>AUDIT &amp; 中文</p><p>rich <b>only</b> &#x1F600;</p><img src='http://127.0.0.1:1/must-not-fetch'></body></html>"
    let htmlItem = NSPasteboardItem(); htmlItem.setData(Data(html.utf8), forType: .html)
    board.clearContents(); board.writeObjects([htmlItem]); monitor.poll()
    let rich = store.entries[0]
    try check(store.plainText(for: rich) == "AUDIT & 中文\n\nrich only 😀", "HTML-only extraction decodes Unicode/entities and paragraph boundaries")
    let vm = HistoryViewModel(store: store); vm.query = "rich only"
    try check(vm.visibleEntries.first?.id == rich.id && vm.visibleEntries.count == 1, "HTML-only body is searchable")
    let concealed = NSPasteboardItem(); concealed.setString("concealed fixture", forType: .string)
    concealed.setData(Data(), forType: .init("org.nspasteboard.ConcealedType"))
    board.clearContents(); board.writeObjects([concealed]); monitor.poll()
    try check(store.entries.count == 2, "concealed content remains excluded")
    let rtf = try NSAttributedString(string: "RTF 中文").data(from: NSRange(location: 0, length: 6), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
    let rtfItem = NSPasteboardItem(); rtfItem.setData(rtf, forType: .rtf)
    board.clearContents(); board.writeObjects([rtfItem]); monitor.poll()
    try check(store.plainText(for: store.entries[0]) == "RTF 中文", "RTF plain text stays correct")
    let fileItems = ["/tmp/LocalPaste-a.txt", "/tmp/LocalPaste-b.txt"].map { path -> NSPasteboardItem in
        let item = NSPasteboardItem(); item.setString(URL(fileURLWithPath: path).absoluteString, forType: .fileURL); return item
    }
    board.clearContents(); board.writeObjects(fileItems); monitor.poll()
    let files = store.entries[0]
    try check(files.payload?.filePaths.count == 2 && files.payload?.items.count == 2, "multi-file references are retained")
    let a = add(store, "A"), b = add(store, "B")
    var callbacks: [() -> Void] = [], sent: [String] = [], feedback = ""
    var environment = PasteCoordinator.Environment()
    environment.pasteboard = board; environment.isTrusted = { true }; environment.requestPermission = {}
    environment.activate = { _ in }; environment.frontmostPID = { app.processIdentifier }
    environment.schedule = { callbacks.append($0) }
    environment.sendCommandV = { sent.append(board.string(forType: .string) ?? ""); return true }
    let paste = PasteCoordinator(store: store, monitor: monitor, environment: environment)
    paste.paste(entry: a, plainTextOnly: false, targetApplication: app) { feedback = $0 }
    paste.paste(entry: b, plainTextOnly: false, targetApplication: app) { _ in }
    try check(callbacks.count == 1 && board.string(forType: .string) == "A", "second paste cannot overwrite in-flight content")
    callbacks.removeFirst()()
    try check(sent == ["A"] && !paste.isPasting, "one accepted paste sends exactly once")
    paste.paste(entry: b, plainTextOnly: false, targetApplication: app) { feedback = $0 }
    write(board, text: "external copy"); callbacks.removeFirst()()
    try check(sent == ["A"] && feedback.contains("取消") && !paste.isPasting, "external clipboard changes cancel queued paste")
    paste.paste(entry: rich, plainTextOnly: true, targetApplication: app) { _ in }
    callbacks.removeFirst()()
    try check(sent.last == "AUDIT & 中文\n\nrich only 😀", "HTML plain paste restores real text")
    try check(board.data(forType: .html) == nil && board.data(forType: .rtf) == nil && board.pasteboardItems?.count == 1,
              "plain paste removes rich representations (system text aliases are allowed)")
    paste.paste(entry: files, plainTextOnly: false, targetApplication: app) { _ in }
    callbacks.removeFirst()()
    try check(board.pasteboardItems?.count == 2, "normal paste preserves multiple file items")
    environment.isTrusted = { false }
    let manual = PasteCoordinator(store: store, environment: environment)
    manual.paste(entry: a, plainTextOnly: false, targetApplication: app) { feedback = $0 }
    try check(feedback.contains("需要辅助功能") && !manual.isPasting && callbacks.isEmpty, "untrusted path copies with manual feedback and no scheduled key")
}

@MainActor func testSearch() throws {
    let store = try makeStore()
    let payload = StoredPasteboardPayload(items: [.init(representations: [.init(uti: "public.png", data: Data(repeating: 41, count: 1_048_576), stringValue: nil, filePath: nil)])], plainText: "", displayText: "图片", contentType: "image", filePaths: [])
    for i in 0..<50 { _ = store.addEntry(payload: payload, sourceBundleIdentifier: "test", sourceName: "Synthetic", title: "Image \(i)") }
    let vm = HistoryViewModel(store: store)
    let start = Date(); vm.query = "unlikely search"; let result = vm.visibleEntries.count
    log("SEARCH 50x1MiB query-and-filter ms=\(Date().timeIntervalSince(start)*1000)")
    try check(result == 0, "large-payload search uses correct cached text")
    vm.query = "image 49"; try check(vm.visibleEntries.count == 1, "cached search still matches titles")
    // Changing payload bytes after summaries were built proves filtering does not decode them.
    for entry in store.entries { entry.payloadData = Data() }
    vm.query = "Synthetic"; try check(vm.visibleEntries.count == 50, "search does not consult payload bytes after indexing")
}

@MainActor func testHorizontalWheel() throws {
    // In-memory events only: these are never posted to the system event queue.
    func wheel(_ y: Int32, _ x: Int32 = 0, units: CGScrollEventUnit = .line) -> NSEvent {
        NSEvent(cgEvent: CGEvent(scrollWheelEvent2Source: nil, units: units,
                               wheelCount: 2, wheel1: y, wheel2: x, wheel3: 0)!)!
    }
    for delta: Int32 in [-3, 3] {
        let original = wheel(delta)
        let mapped = HorizontalWheelEvent.redirect(original)!
        try check(mapped.scrollingDeltaX == original.scrollingDeltaY && mapped.scrollingDeltaY == 0
                  && !mapped.hasPreciseScrollingDeltas && original.scrollingDeltaX == 0,
                  "vertical mouse wheel maps to horizontal with original direction (\(delta))")
    }
    let precise = wheel(-24, units: .pixel)
    let cg = precise.cgEvent!
    cg.setIntegerValueField(.scrollWheelEventScrollPhase, value: Int64(CGScrollPhase.changed.rawValue))
    cg.setIntegerValueField(.scrollWheelEventMomentumPhase, value: Int64(CGMomentumScrollPhase.continuous.rawValue))
    let gesture = NSEvent(cgEvent: cg)!
    let mapped = HorizontalWheelEvent.redirect(gesture)!
    try check(!gesture.phase.isEmpty && !gesture.momentumPhase.isEmpty
              && mapped.hasPreciseScrollingDeltas && mapped.scrollingDeltaX == gesture.scrollingDeltaY
              && mapped.phase == gesture.phase && mapped.momentumPhase == gesture.momentumPhase,
              "precise wheel retains pixel distance and gesture phases")
    try check(HorizontalWheelEvent.redirect(wheel(0, -3)) == nil
              && HorizontalWheelEvent.redirect(wheel(-3, -1, units: .pixel)) == nil
              && HorizontalWheelEvent.redirect(wheel(0)) == nil,
              "horizontal and diagonal trackpad gestures and zero deltas stay native")
}

@MainActor func testMigration(_ fixture: URL) throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("LocalPasteMigration-\(UUID())", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: root) }
    let sourceDirectory = root.appendingPathComponent("legacy")
    try FileManager.default.copyItem(at: fixture, to: sourceDirectory)
    let source = sourceDirectory.appendingPathComponent("default.store")
    let before = try Data(contentsOf: source)
    let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: sourceDirectory.appendingPathComponent("manifest.json"))) as! [String: String]
    let container = try ClipboardPersistence.open(applicationSupport: root, bundleIdentifier: "test.migrated", legacyURL: source)
    let context = ModelContext(container)
    let entries = try context.fetch(FetchDescriptor<ClipboardEntry>())
    let categories = try context.fetch(FetchDescriptor<ClipCategory>())
    try check(entries.count == 2 && categories.count == 1, "legacy migration retains records and category")
    let large = entries.first{ $0.title == "legacy large" }!
    try check(large.isFavorite && large.id.uuidString == manifest["largeID"] && large.categoryIDs == [categories[0].id.uuidString], "migration retains IDs, favorite, category membership")
    try check(SHA256.hash(data: large.payloadData).map{ String(format:"%02x",$0) }.joined() == manifest["payloadHash"], "migration preserves external payload bytes")
    try check(try Data(contentsOf: source) == before, "shared source database remains unchanged")
    let destination = ClipboardPersistence.storeURL(applicationSupport: root, bundleIdentifier: "test.migrated")
    try check(destination != source && FileManager.default.fileExists(atPath: source.path), "migration uses isolated path and preserves old store")
    let other = try ClipboardPersistence.open(applicationSupport: root, bundleIdentifier: "test.other")
    try check(try ModelContext(other).fetchCount(FetchDescriptor<ClipboardEntry>()) == 0, "unrelated bundle starts in its own database")
    let reopened = try ClipboardPersistence.open(applicationSupport: root, bundleIdentifier: "test.migrated", legacyURL: source)
    try check(try ModelContext(reopened).fetchCount(FetchDescriptor<ClipboardEntry>()) == 2, "second launch opens destination without duplicating migration")
    let wrongSource = root.appendingPathComponent("foreign.store")
    let foreign = try ModelContainer(for: ClipCategory.self, configurations: ModelConfiguration(url: wrongSource))
    _ = foreign
    var rejected = false
    do { _ = try ClipboardPersistence.open(applicationSupport: root, bundleIdentifier: "test.reject", legacyURL: wrongSource) }
    catch ClipboardPersistenceError.incompatibleLegacyStore { rejected = true }
    try check(rejected && !FileManager.default.fileExists(atPath: root.appendingPathComponent("test.reject").path), "incompatible shared store is refused without publishing an empty destination")
}

@MainActor final class VerificationDelegate: NSObject, NSApplicationDelegate {
    var store: ClipboardStore!, panel: PanelController!, settings: NSWindow!
    var shortcuts: GlobalShortcutManager!, login: LoginItemManager!
    let board = namedBoard()
    var observation: Timer?
    var lastCount = 0
    var fixtureDirectory: URL?
    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            store = try makeStore(); shortcuts = GlobalShortcutManager(); login = LoginItemManager(allowsChanges: false)
            let richText = NSMutableAttributedString(string: "FIX rich preview — 富文本与附件\n", attributes: [.font: NSFont.boldSystemFont(ofSize: 18), .foregroundColor: NSColor.systemRed])
            let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 32, pixelsHigh: 32, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            if let pixels = bitmap.bitmapData {
                for y in 0..<32 { for x in 0..<32 {
                    let offset = y * bitmap.bytesPerRow + x * 4
                    pixels[offset] = 255; pixels[offset + 1] = 128
                    pixels[offset + 2] = 0; pixels[offset + 3] = 255
                } }
            }
            let wrapper = FileWrapper(regularFileWithContents: bitmap.representation(using: .png, properties: [:])!)
            wrapper.preferredFilename = "fixture.png"
            richText.append(NSAttributedString(attachment: NSTextAttachment(fileWrapper: wrapper)))
            let rtfd = try richText.data(from: NSRange(location: 0, length: richText.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd])
            let richPayload = StoredPasteboardPayload(items: [.init(representations: [.init(uti: "com.apple.flat-rtfd", data: rtfd, stringValue: nil, filePath: nil)])], plainText: "FIX rich preview", displayText: "FIX rich preview", contentType: "richText", filePaths: [])
            _ = store.addEntry(payload: richPayload, sourceBundleIdentifier: "synthetic.test", sourceName: "人工样例", title: "FIX rich preview")
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("LocalPasteUI-\(UUID())")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
            fixtureDirectory = directory
            let file = directory.appendingPathComponent("设计笔记.txt")
            try "LocalPaste product preview fixture".write(to: file, atomically: true, encoding: .utf8)
            let paths = [file.path, directory.appendingPathComponent("已移走的文件.txt").path]
            let filePayload = StoredPasteboardPayload(items: paths.map { .init(representations: [.init(uti: "public.file-url", data: nil, stringValue: URL(fileURLWithPath: $0).absoluteString, filePath: $0)]) }, plainText: "", displayText: "设计笔记", contentType: "fileReference", filePaths: paths)
            _ = store.addEntry(payload: filePayload, sourceBundleIdentifier: "synthetic.test", sourceName: "人工样例", title: "FIX file preview")
            for i in (1...12).reversed() { add(store, String(format: "FIX card %02d", i) + " — 人工键盘样例") }
            _ = store.addCategory(named: "已有分类")
            if CommandLine.arguments.contains("--empty") {
                store.clearHistory(preservingFavorites: false)
                for category in store.categories { store.deleteCategory(category) }
            }
            var environment = PasteCoordinator.Environment()
            environment.pasteboard = board; environment.isTrusted = { false }; environment.requestPermission = {}
            panel = PanelController(store: store, pasteCoordinator: PasteCoordinator(store: store, environment: environment), onSettings: { [weak self] in self?.showSettings() })
            let menu = NSMenu(), submenu = NSMenu(), root = NSMenuItem(); root.submenu = submenu; menu.addItem(root)
            for (title, selector, key) in [("打开历史",#selector(showHistory),"h"),("设置",#selector(showSettings),","),("退出验证副本",#selector(quit),"q")] {
                let item = NSMenuItem(title: title, action: selector, keyEquivalent: key); item.target = self; submenu.addItem(item)
            }
            NSApp.mainMenu = menu; NSApp.setActivationPolicy(.regular); NSApp.activate(ignoringOtherApps: true); panel.show()
            lastCount = board.changeCount
            observation = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.board.changeCount != self.lastCount else { return }
                    self.lastCount = self.board.changeCount
                    log("UI_RESTORED \(self.board.string(forType: .string) ?? "nontext")")
                }
            }
            log("UI_READY")
        } catch { log("UI_ERROR \(error)"); NSApp.terminate(nil) }
    }
    @objc func showHistory() { panel.show() }
    @objc func showSettings() {
        if settings == nil {
            settings = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 480), styleMask: [.titled,.closable], backing: .buffered, defer: false)
            settings.title = "LocalPaste 修复验证设置"; settings.isReleasedWhenClosed = false
            settings.contentViewController = NSHostingController(rootView: SettingsView(store: store, shortcutManager: shortcuts, loginItemManager: login)); settings.center()
        }
        NSApp.activate(ignoringOtherApps: true); settings.makeKeyAndOrderFront(nil)
    }
    @objc func quit() {
        observation?.invalidate(); board.releaseGlobally()
        if let fixtureDirectory { try? FileManager.default.removeItem(at: fixtureDirectory) }
        NSApp.terminate(nil)
    }
}
@main struct RegressionMain {
    @MainActor static func main() {
        _ = NSApplication.shared
        if CommandLine.arguments.contains("--ui") {
            let delegate = VerificationDelegate(); NSApp.delegate = delegate
            withExtendedLifetime(delegate) { NSApp.run() }
            return
        }
        do {
            try testStore(); try testCaptureAndPaste(); try testSearch(); try testHorizontalWheel()
            try testBackupAndRestore()
            if let fixture = CommandLine.arguments.dropFirst().first { try testMigration(URL(fileURLWithPath: fixture)) }
            else { throw RegressionFailure(message: "Legacy fixture path required") }
            log("ALL_REGRESSIONS_PASSED")
        } catch { log("FAILED \(error)"); exit(1) }
    }
}
