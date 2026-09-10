import Foundation
import AppKit
import Carbon.HIToolbox

struct ShortcutSpec: Codable, Equatable {
    let keyCode: UInt32
    let modifiers: UInt32
    let displayName: String

    static let defaultShortcut = ShortcutSpec(
        keyCode: 9,
        modifiers: UInt32(cmdKey | shiftKey),
        displayName: "⌘⇧V"
    )

    init(keyCode: UInt32, modifiers: UInt32, displayName: String? = nil) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.displayName = displayName ?? Self.displayName(keyCode: keyCode, modifiers: modifiers)
    }

    static func displayName(keyCode: UInt32, modifiers: UInt32) -> String {
        var result = ""
        if modifiers & UInt32(controlKey) != 0 { result += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { result += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { result += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { result += "⌘" }
        let keyNames: [UInt32: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
            8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 17: "T",
            31: "O", 32: "U", 34: "I", 35: "P", 37: "L", 38: "J", 40: "K", 45: "N",
            46: "M", 36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 53: "Esc"
        ]
        return result + (keyNames[keyCode] ?? "Key\(keyCode)")
    }
}

final class GlobalShortcutManager: NSObject, ObservableObject {
    @Published private(set) var shortcut: ShortcutSpec
    @Published private(set) var isRegistered = false
    @Published var lastErrorMessage: String?

    var onTrigger: (() -> Void)?

    private let defaults = UserDefaults.standard
    private let shortcutKey = "globalShortcut"
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private let hotKeyID = EventHotKeyID(signature: 0x4C50484B, id: 1)

    override init() {
        if let data = UserDefaults.standard.data(forKey: "globalShortcut"),
           let decoded = try? JSONDecoder().decode(ShortcutSpec.self, from: data) {
            shortcut = decoded
        } else {
            shortcut = .defaultShortcut
        }
        super.init()
        installEventHandler()
    }

    deinit {
        unregisterHotKey()
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
    }

    @discardableResult
    func registerInitialShortcut() -> Bool {
        guard !isRegistered else { return true }
        return register(shortcut, replacing: nil)
    }

    @discardableResult
    func apply(_ newShortcut: ShortcutSpec) -> Bool {
        let oldShortcut = shortcut
        guard register(newShortcut, replacing: oldShortcut) else { return false }
        shortcut = newShortcut
        if let data = try? JSONEncoder().encode(newShortcut) {
            defaults.set(data, forKey: shortcutKey)
        }
        return true
    }

    func unregisterHotKey() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        isRegistered = false
    }

    private func register(_ newShortcut: ShortcutSpec, replacing oldShortcut: ShortcutSpec?) -> Bool {
        guard eventHandlerRef != nil else {
            isRegistered = false
            return false
        }
        unregisterHotKey()
        var newRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            newShortcut.keyCode,
            newShortcut.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &newRef
        )
        guard status == noErr, let newRef else {
            lastErrorMessage = "全局快捷键 \(newShortcut.displayName) 注册失败（OSStatus \(status)）。可能与其他应用冲突。"
            if let oldShortcut {
                var restoredRef: EventHotKeyRef?
                let restoreStatus = RegisterEventHotKey(
                    oldShortcut.keyCode,
                    oldShortcut.modifiers,
                    hotKeyID,
                    GetApplicationEventTarget(),
                    0,
                    &restoredRef
                )
                if restoreStatus == noErr {
                    hotKeyRef = restoredRef
                    isRegistered = true
                }
            }
            return false
        }
        hotKeyRef = newRef
        isRegistered = true
        lastErrorMessage = nil
        return true
    }

    private func installEventHandler() {
        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let userData = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            localPasteHotKeyEventHandler,
            1,
            &eventSpec,
            userData,
            &eventHandlerRef
        )
        if status != noErr {
            lastErrorMessage = "全局快捷键事件监听安装失败（OSStatus \(status)）。"
        }
    }

    fileprivate func handleHotKeyEvent() {
        DispatchQueue.main.async { [weak self] in
            self?.onTrigger?()
        }
    }
}

private let localPasteHotKeyEventHandler: EventHandlerUPP = { _, _, userData in
    guard let userData else { return noErr }
    let manager = Unmanaged<GlobalShortcutManager>.fromOpaque(userData).takeUnretainedValue()
    manager.handleHotKeyEvent()
    return noErr
}

extension NSEvent.ModifierFlags {
    var carbonShortcutModifiers: UInt32 {
        var result: UInt32 = 0
        if contains(.command) { result |= UInt32(cmdKey) }
        if contains(.shift) { result |= UInt32(shiftKey) }
        if contains(.option) { result |= UInt32(optionKey) }
        if contains(.control) { result |= UInt32(controlKey) }
        return result
    }
}
