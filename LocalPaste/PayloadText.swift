import AppKit
import libxml2

/// Plain-text extraction never creates a web view or follows HTML resource URLs.
enum PayloadText {
    private static let plainTextUTIs = ["public.utf8-plain-text", "public.plain-text", "public.text", "public.url"]

    static func plainText(from payload: StoredPasteboardPayload) -> String? {
        if !payload.plainText.isEmpty {
            let hasExplicitText = payload.items.contains { item in
                item.representations.contains { plainTextUTIs.contains($0.uti) }
            }
            if hasExplicitText || !payload.plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return payload.plainText
            }
        }
        if !payload.filePaths.isEmpty { return payload.filePaths.joined(separator: "\n") }
        let parts = payload.items.compactMap { plainText(from: $0.representations) }
        return parts.isEmpty ? nil : parts.joined(separator: "\n")
    }

    static func plainText(from representations: [StoredPasteboardRepresentation]) -> String? {
        for uti in plainTextUTIs {
            if let value = representations.first(where: { $0.uti == uti })?.stringValue, !value.isEmpty {
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
                    let extracted = text.replacingOccurrences(of: "\u{fffc}", with: "")
                    if !extracted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return extracted }
                }
            default: break
            }
        }
        return nil
    }

    /// Honor HTML's declared encoding; unlabelled UTF-8 fragments are common on the pasteboard.
    static func attributedString(from representation: StoredPasteboardRepresentation) -> NSAttributedString? {
        let type: NSAttributedString.DocumentType
        switch representation.uti {
        case "public.html": type = .html
        case "public.rtf": type = .rtf
        case "com.apple.flat-rtfd": type = .rtfd
        default: return nil
        }
        guard let data = representation.data ?? representation.stringValue?.data(using: .utf8) else { return nil }
        var options: [NSAttributedString.DocumentReadingOptionKey: Any] = [.documentType: type]
        if type == .html, let html = String(data: data, encoding: .utf8),
           html.range(of: "(?is)<meta\\b[^>]*\\bcharset\\s*=", options: .regularExpression) == nil {
            options[.characterEncoding] = String.Encoding.utf8.rawValue
        }
        return try? NSAttributedString(data: data, options: options, documentAttributes: nil)
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
        // Keep preformatted sections separate so trimming and paragraph normalization
        // never remove code indentation or intentional empty lines inside <pre>.
        var sections: [(text: String, preformatted: Bool)] = []
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
                    if name == "pre", !preformatted {
                        sections.append((output + "\n", false))
                        output = ""
                        visit(node.pointee.children, preformatted: true)
                        sections.append((output, true))
                        output = "\n"
                    } else {
                        if name == "br" || (!preformatted && blocks.contains(name)) { output += "\n" }
                        visit(node.pointee.children, preformatted: preformatted)
                        if !preformatted && blocks.contains(name) { output += "\n" }
                        if !preformatted && (name == "td" || name == "th") { output += "\t" }
                    }
                }
            }
        }
        visit(xmlDocGetRootElement(document))
        sections.append((output, false))
        for index in sections.indices where !sections[index].preformatted {
            sections[index].text = sections[index].text.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
        }
        if !sections[0].preformatted {
            sections[0].text = sections[0].text.replacingOccurrences(of: "^\\s+", with: "", options: .regularExpression)
        }
        let last = sections.count - 1
        if !sections[last].preformatted {
            sections[last].text = sections[last].text.replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression)
        }
        let text = sections.map(\.text).joined()
        return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text
    }
}
