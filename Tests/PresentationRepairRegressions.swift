import AppKit
import Carbon.HIToolbox
import ImageIO

@MainActor func testPresentationRepairs() throws {
    func html(_ text: String) -> StoredPasteboardRepresentation {
        .init(uti: "public.html", data: Data(text.utf8), stringValue: nil, filePath: nil)
    }
    let ordinary = html("<html><head><style>hidden</style><script>hidden()</script></head><body><p>AUDIT &amp; 中文</p><p>rich <b>only</b> &#x1F600;</p></body></html>")
    try check(PayloadText.plainText(from: [ordinary]) == "AUDIT & 中文\n\nrich only 😀",
              "HTML extraction retains existing entity, Unicode and paragraph behavior")
    let code = "    def f():\n\n\n        return 1\n"
    try check(PayloadText.plainText(from: [html("<pre>    def f():\n\n\n        return <b>1</b>\n</pre>")]) == code,
              "HTML pre preserves leading indentation, repeated blank lines and trailing newline")
    try check(PayloadText.plainText(from: [html("<p>Before</p><pre>  code\n\n\n  more</pre><p>After</p>")])
              == "Before\n\n  code\n\n\n  more\n\nAfter",
              "preformatted sections preserve their whitespace beside ordinary paragraphs")
    try check(PayloadText.plainText(from: [html("<p>&nbsp; <br></p><pre>\n  </pre>")]) == nil
              && PayloadText.plainText(from: [html("<img alt='image'>")]) == nil,
              "HTML with no visible text has no plain-text paste representation")

    let blankRich = NSAttributedString(string: " \n\t ")
    let blankRTF = try blankRich.data(from: NSRange(location: 0, length: blankRich.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
    let richRepresentation = StoredPasteboardRepresentation(uti: "public.rtf", data: blankRTF, stringValue: nil, filePath: nil)
    let oldDerivedWhitespace = StoredPasteboardPayload(items: [.init(representations: [richRepresentation])], plainText: " \n\t ", displayText: " \n\t ", contentType: "richText", filePaths: [])
    try check(PayloadText.plainText(from: [richRepresentation]) == nil && PayloadText.plainText(from: oldDerivedWhitespace) == nil,
              "whitespace-only text derived from RTF is unavailable for plain-text paste")
    let explicitWhitespace = " \n\t "
    try check(PayloadText.plainText(from: textPayload(explicitWhitespace)) == explicitWhitespace
              && PayloadText.plainText(from: [.init(uti: "public.utf8-plain-text", data: nil, stringValue: explicitWhitespace, filePath: nil)]) == explicitWhitespace,
              "explicit plain-text clipboard whitespace remains unchanged")

    let legacyHTML = "<html><head><meta charset='windows-1252'></head><body>Café £</body></html>"
    let legacy = StoredPasteboardRepresentation(uti: "public.html", data: legacyHTML.data(using: .windowsCP1252)!, stringValue: nil, filePath: nil)
    try check(PayloadText.attributedString(from: legacy)?.string.trimmingCharacters(in: .whitespacesAndNewlines) == "Café £"
              && PayloadText.plainText(from: [legacy]) == "Café £",
              "HTML preview and text extraction honor declared non-UTF8 encoding")
    let unicode = "<html><body>中文 Café</body></html>"
    let utf16 = StoredPasteboardRepresentation(uti: "public.html", data: unicode.data(using: .utf16)!, stringValue: nil, filePath: nil)
    try check(PayloadText.attributedString(from: html(unicode))?.string.trimmingCharacters(in: .whitespacesAndNewlines) == "中文 Café"
              && PayloadText.attributedString(from: utf16)?.string.trimmingCharacters(in: .whitespacesAndNewlines) == "中文 Café",
              "HTML preview preserves unlabelled UTF8 fragments and UTF16 BOM input")

    let bitmap = CGContext(data: nil, width: 2_048, height: 1_024, bitsPerComponent: 8,
                           bytesPerRow: 2_048 * 4, space: CGColorSpaceCreateDeviceRGB(),
                           bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    bitmap.setFillColor(CGColor(red: 0.8, green: 0.3, blue: 0.1, alpha: 1))
    bitmap.fill(CGRect(x: 0, y: 0, width: 2_048, height: 1_024))
    let png = NSMutableData()
    let destination = CGImageDestinationCreateWithData(png as CFMutableData, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, bitmap.makeImage()!, nil)
    try check(CGImageDestinationFinalize(destination), "synthetic thumbnail fixture encodes successfully")
    let imagePayload = StoredPasteboardPayload(items: [.init(representations: [.init(uti: "public.png", data: png as Data, stringValue: nil, filePath: nil)])],
                                               plainText: "", displayText: "图片", contentType: "image", filePaths: [])
    func imageEntry() throws -> ClipboardEntry {
        ClipboardEntry(title: "Synthetic thumbnail", contentTypeRaw: "image", payloadData: try JSONEncoder().encode(imagePayload))
    }
    let first = try imageEntry(), second = try imageEntry(), third = try imageEntry()
    let cache = CardPreviewCache(entryLimit: 2)
    let thumbnail = cache.preview(for: first).thumbnail!
    let raster = thumbnail.cgImage(forProposedRect: nil, context: nil, hints: nil)!
    try check(raster.width <= CardPreviewCache.thumbnailPixelLimit && raster.height <= CardPreviewCache.thumbnailPixelLimit
              && raster.width == raster.height * 2 && thumbnail === cache.preview(for: first).thumbnail,
              "image cards reuse a bounded-size thumbnail with original aspect ratio")
    let onePreviewCost = cache.cachedByteCount
    _ = cache.preview(for: second)
    _ = cache.preview(for: third)
    try check(cache.cachedCount == 2 && cache.cachedByteCount <= 2 * onePreviewCost,
              "thumbnail cache evicts entries at its count limit")
    let byteBounded = CardPreviewCache(byteLimit: onePreviewCost + 1)
    _ = byteBounded.preview(for: first)
    _ = byteBounded.preview(for: second)
    try check(byteBounded.cachedCount == 1 && byteBounded.cachedByteCount <= onePreviewCost + 1,
              "thumbnail cache also evicts entries at its byte limit")
    byteBounded.retainEntries(withIDs: [])
    try check(byteBounded.cachedCount == 0 && byteBounded.cachedByteCount == 0,
              "deleted entries release their cached previews")
    let files = StoredPasteboardPayload(items: [], plainText: "", displayText: "files", contentType: "fileReference",
                                       filePaths: ["/synthetic/one/a.txt", "/synthetic/two/a.txt", "/synthetic/b.txt"])
    let fileEntry = ClipboardEntry(title: "Synthetic files", contentTypeRaw: "fileReference", payloadData: try JSONEncoder().encode(files))
    let filePreview = cache.preview(for: fileEntry)
    try check(filePreview.fileNames == ["a.txt", "a.txt"] && filePreview.fileCount == 3 && filePreview.thumbnail == nil,
              "file cards cache only visible names and total count without opening files")
    try check(ShortcutSpec.displayName(keyCode: 18, modifiers: UInt32(cmdKey)) == "⌘1"
              && ShortcutSpec.displayName(keyCode: 123, modifiers: UInt32(controlKey)) == "⌃←"
              && ShortcutSpec.displayName(keyCode: 122, modifiers: UInt32(optionKey)) == "⌥F1"
              && ShortcutSpec.displayName(keyCode: 82, modifiers: UInt32(shiftKey)) == "⇧Num 0",
              "numeric, arrow, function and keypad shortcuts display readable names")
}
