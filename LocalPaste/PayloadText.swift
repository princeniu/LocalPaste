import AppKit
import libxml2

/// Text extraction never creates a web view or follows HTML resource URLs.
enum PayloadText {
    static func plainText(from payload: StoredPasteboardPayload) -> String? {
        if !payload.plainText.isEmpty { return payload.plainText }
        if !payload.filePaths.isEmpty { return payload.filePaths.joined(separator: "\n") }
        let parts = payload.items.compactMap { plainText(from: $0.representations) }
        return parts.isEmpty ? nil : parts.joined(separator: "\n")
    }

    static func plainText(from representations: [StoredPasteboardRepresentation]) -> String? {
        for uti in ["public.utf8-plain-text", "public.plain-text", "public.text", "public.url"] {
            if let value = representations.first(where: { $0.uti == uti })?.stringValue {
                return value
            }
        }
        for representation in representations {
            guard let data = representation.data ?? representation.stringValue?.data(using: .utf8) else { continue }
            switch representation.uti {
            case "public.html":
                if let text = htmlText(data) { return text }
            case "public.rtf", "com.apple.flat-rtfd":
                let type: NSAttributedString.DocumentType = representation.uti == "public.rtf" ? .rtf : .rtfd
                if let text = try? NSAttributedString(data: data, options: [.documentType: type], documentAttributes: nil).string {
                    return text.replacingOccurrences(of: "\u{fffc}", with: "")
                }
            default: break
            }
        }
        return nil
    }

    private static func htmlText(_ data: Data) -> String? {
        guard !data.isEmpty, data.count <= Int(Int32.max) else { return nil }
        let options = Int32(HTML_PARSE_RECOVER.rawValue | HTML_PARSE_NONET.rawValue |
                            HTML_PARSE_NOERROR.rawValue | HTML_PARSE_NOWARNING.rawValue)
        let encoding: String? = String(data: data, encoding: .utf8) == nil ? nil : "UTF-8"
        let document = data.withUnsafeBytes { bytes in
            htmlReadMemory(bytes.baseAddress?.assumingMemoryBound(to: CChar.self), Int32(data.count), nil, encoding, options)
        }
        guard let document else { return nil }
        defer { xmlFreeDoc(document) }
        let blocks: Set<String> = ["p", "div", "section", "article", "header", "footer", "li", "ul", "ol", "blockquote", "pre", "tr", "h1", "h2", "h3", "h4", "h5", "h6"]
        var output = ""
        func visit(_ first: xmlNodePtr?, preformatted: Bool = false) {
            var current = first
            while let node = current {
                defer { current = node.pointee.next }
                let name = node.pointee.name.map { String(cString: $0).lowercased() } ?? ""
                if ["head", "script", "style", "template", "noscript"].contains(name) { continue }
                if node.pointee.type == XML_TEXT_NODE || node.pointee.type == XML_CDATA_SECTION_NODE {
                    if let content = node.pointee.content {
                        let text = String(cString: content).replacingOccurrences(of: "\u{00a0}", with: " ")
                        output += preformatted ? text : text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                    }
                } else {
                    if name == "br" || blocks.contains(name) { output += "\n" }
                    visit(node.pointee.children, preformatted: preformatted || name == "pre")
                    if blocks.contains(name) { output += "\n" }
                    if name == "td" || name == "th" { output += "\t" }
                }
            }
        }
        visit(xmlDocGetRootElement(document))
        return output.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
