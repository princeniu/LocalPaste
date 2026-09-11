import AppKit

enum AppBrand {
    static let name = "拾贴"
    static let englishName = "Clipmori"
    static let displayName = "\(name) · \(englishName)"

    static var icon: NSImage {
        NSImage(named: "BrandIcon")
            ?? NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: name)
            ?? NSImage(size: NSSize(width: 32, height: 32))
    }
}
