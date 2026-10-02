import AppKit

@MainActor func testPasteRepairs() throws {
    let store = try makeStore()
    let board = namedBoard()
    defer { board.releaseGlobally() }
    let entry = add(store, "selected fixture")
    let target = NSRunningApplication.current
    let targetPID = target.processIdentifier
    let ownPID = targetPID + 10_000
    let otherPID = targetPID + 20_000
    var frontmost: pid_t? = targetPID
    var terminated = false
    var trusted = true
    var callbacks: [() -> Void] = []
    var activations = 0, sent = 0, permissionRequests = 0
    var feedback = ""
    var environment = PasteCoordinator.Environment()
    environment.pasteboard = board
    environment.frontmostPID = { frontmost }
    environment.currentApplicationPID = { ownPID }
    environment.isTerminated = { _ in terminated }
    environment.isTrusted = { trusted }
    environment.requestPermission = { permissionRequests += 1 }
    environment.activate = { application in
        activations += 1
        frontmost = application.processIdentifier
    }
    environment.schedule = { callbacks.append($0) }
    environment.sendCommandV = { sent += 1; return true }
    let coordinator = PasteCoordinator(store: store, environment: environment)

    coordinator.paste(entry: entry, plainTextOnly: false, targetApplication: target) { feedback = $0 }
    try check(callbacks.count == 1 && activations == 1 && board.string(forType: .string) == "selected fixture",
              "current destination accepts the selected clip")
    callbacks.removeFirst()()
    try check(sent == 1 && !coordinator.isPasting, "current destination sends once and finishes")

    write(board, text: "keep before app switch")
    let beforeSwitch = board.changeCount
    frontmost = otherPID
    coordinator.paste(entry: entry, plainTextOnly: false, targetApplication: target) { feedback = $0 }
    try check(board.changeCount == beforeSwitch && activations == 1 && callbacks.isEmpty && feedback.contains("当前应用已改变"),
              "changed destination is rejected without replacing the clipboard or activating the old app")

    frontmost = nil
    coordinator.paste(entry: entry, plainTextOnly: false, targetApplication: target) { feedback = $0 }
    try check(board.changeCount == beforeSwitch && callbacks.isEmpty && feedback.contains("无法确认"),
              "unknown foreground preserves the clipboard and sends nothing")

    terminated = true
    frontmost = targetPID
    coordinator.paste(entry: entry, plainTextOnly: false, targetApplication: target) { feedback = $0 }
    try check(board.changeCount == beforeSwitch && activations == 1 && feedback.contains("已退出"),
              "terminated destination preserves the clipboard")
    terminated = false

    frontmost = ownPID
    coordinator.paste(entry: entry, plainTextOnly: false, targetApplication: target) { feedback = $0 }
    try check(activations == 2 && callbacks.count == 1 && frontmost == targetPID,
              "returning from the app's own menu can reactivate the remembered destination")
    callbacks.removeFirst()()
    try check(sent == 2, "returning from the app's own menu pastes into the remembered destination")

    frontmost = nil
    coordinator.paste(entry: entry, plainTextOnly: false, targetApplication: nil) { feedback = $0 }
    try check(board.string(forType: .string) == "selected fixture" && activations == 2 && callbacks.isEmpty && feedback.contains("按 ⌘V"),
              "missing destination safely degrades to manual copy without activation or a key")

    trusted = false
    frontmost = targetPID
    coordinator.paste(entry: entry, plainTextOnly: false, targetApplication: target) { feedback = $0 }
    try check(board.string(forType: .string) == "selected fixture" && callbacks.isEmpty && permissionRequests == 1 && feedback.contains("需要辅助功能"),
              "untrusted valid destination retains the manual-copy fallback")
    write(board, text: "keep before untrusted stale request")
    let beforeUntrusted = board.changeCount
    frontmost = otherPID
    coordinator.paste(entry: entry, plainTextOnly: false, targetApplication: target) { feedback = $0 }
    try check(board.changeCount == beforeUntrusted && permissionRequests == 1,
              "stale untrusted request does not replace the clipboard or request permission")
    trusted = true

    let emptyHTML = StoredPasteboardPayload(
        items: [.init(representations: [.init(uti: "public.html", data: Data("<img src='missing.png'>".utf8), stringValue: nil, filePath: nil)])],
        plainText: "", displayText: "HTML", contentType: "html", filePaths: [])
    let emptyEntry = store.addEntry(payload: emptyHTML, sourceBundleIdentifier: "synthetic.test", sourceName: "人工样例", title: "image only HTML")!
    frontmost = targetPID
    coordinator.paste(entry: emptyEntry, plainTextOnly: true, targetApplication: target) { feedback = $0 }
    try check(board.changeCount == beforeUntrusted && callbacks.isEmpty && feedback.contains("没有可提取的文字"),
              "empty derived text cannot erase the clipboard through plain paste")

    let whitespaceEntry = add(store, "  \n")
    coordinator.paste(entry: whitespaceEntry, plainTextOnly: true, targetApplication: target) { feedback = $0 }
    try check(board.string(forType: .string) == "  \n" && callbacks.count == 1,
              "explicit whitespace text remains a valid plain paste")
    callbacks.removeFirst()()

    var foregroundReads = 0
    environment.frontmostPID = {
        foregroundReads += 1
        return foregroundReads == 1 ? targetPID : otherPID
    }
    let switching = PasteCoordinator(store: store, environment: environment)
    write(board, text: "keep during clipboard snapshot")
    let beforeSnapshot = board.changeCount
    let activationsBeforeSnapshot = activations
    switching.paste(entry: entry, plainTextOnly: false, targetApplication: target) { feedback = $0 }
    try check(board.changeCount == beforeSnapshot && activations == activationsBeforeSnapshot && callbacks.isEmpty,
              "destination change during preparation is rejected before clipboard replacement")

    foregroundReads = 0
    environment.frontmostPID = {
        foregroundReads += 1
        if foregroundReads == 2 { write(board, text: "new copy during preparation") }
        return targetPID
    }
    let copying = PasteCoordinator(store: store, environment: environment)
    copying.paste(entry: entry, plainTextOnly: false, targetApplication: target) { feedback = $0 }
    try check(board.string(forType: .string) == "new copy during preparation" && callbacks.isEmpty && feedback.contains("取消"),
              "a new copy during preparation is preserved instead of overwritten")

    environment.frontmostPID = { frontmost }
    frontmost = targetPID
    let delayed = PasteCoordinator(store: store, environment: environment)
    delayed.paste(entry: entry, plainTextOnly: false, targetApplication: target) { feedback = $0 }
    frontmost = otherPID
    let sentBeforeSwitch = sent
    callbacks.removeFirst()()
    try check(sent == sentBeforeSwitch && !delayed.isPasting && feedback.contains("按 ⌘V"),
              "destination change after copy prevents the queued paste key")
}
