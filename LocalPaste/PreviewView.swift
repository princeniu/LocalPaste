import SwiftUI
import AppKit

struct PreviewView: View {
    let entry: ClipboardEntry
    @Environment(\.dismiss) private var dismiss

    private let surfaceColor = Color(nsColor: .windowBackgroundColor)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                Divider()
                    .overlay(Color.white.opacity(0.12))

                if let payload = entry.payload {
                    previewContent(payload)
                } else {
                    unavailableContent
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(surfaceColor)
        .tint(.orange)
        .frame(minWidth: 620, idealWidth: 680, minHeight: minimumHeight, idealHeight: idealHeight)
        .clipShape(.rect(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        }
    }

    private var minimumHeight: CGFloat {
        switch entry.contentType {
        case .image, .mixed:
            return 540
        default:
            return 420
        }
    }

    private var idealHeight: CGFloat {
        minimumHeight + 20
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: entry.contentType.symbolName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.orange)
                .frame(width: 40, height: 40)
                .background(Color.orange.opacity(0.16))
                .clipShape(.rect(cornerRadius: 11, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                Text(titleText)
                    .font(.title3.weight(.semibold))
                    .lineLimit(2)
                    .textSelection(.enabled)

                HStack(spacing: 6) {
                    Text(entry.contentType.label)
                    Circle()
                        .frame(width: 3, height: 3)
                        .foregroundStyle(.tertiary)
                    Text(entry.sourceName)
                        .lineLimit(1)
                    Circle()
                        .frame(width: 3, height: 3)
                        .foregroundStyle(.tertiary)
                    Text(entry.createdAt, style: .relative)
                        .lineLimit(1)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .keyboardShortcut(.cancelAction)
            .accessibilityLabel("关闭预览")
            .help("关闭预览（Esc）")
        }
    }

    private var titleText: String {
        if !entry.title.isEmpty { return entry.title }
        return entry.payload?.displayText.isEmpty == false
            ? (entry.payload?.displayText ?? entry.contentType.label)
            : entry.contentType.label
    }

    private var unavailableContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("内容不可用", systemImage: "exclamationmark.triangle")
                .font(.headline)
                .foregroundStyle(.orange)
            Text("无法读取此条目的本地内容。")
                .font(.body)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.06))
        .clipShape(.rect(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private func previewContent(_ payload: StoredPasteboardPayload) -> some View {
        if let imageData = imageData(from: payload), let image = NSImage(data: imageData) {
            imagePreview(image: image, payload: payload)
        } else if !payload.filePaths.isEmpty {
            filePreview(payload)
        } else if let attributed = attributedString(from: payload) {
            richTextPreview(attributed)
        } else {
            plainTextPreview(PayloadText.plainText(from: payload) ?? payload.displayText)
        }
    }

    private func imagePreview(image: NSImage, payload: StoredPasteboardPayload) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack {
                Color.black.opacity(0.24)
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: 420)
            }
            .frame(maxWidth: .infinity, minHeight: 220, maxHeight: 420)
            .clipShape(.rect(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            }

            if !payload.plainText.isEmpty {
                payloadNote(payload.plainText)
            }
        }
    }

    private func filePreview(_ payload: StoredPasteboardPayload) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(payload.filePaths, id: \.self) { path in
                    HStack(alignment: .top, spacing: 10) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                            .resizable()
                            .frame(width: 28, height: 28)
                            .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(URL(fileURLWithPath: path).lastPathComponent)
                                .font(.body.weight(.medium))
                            Text(FileManager.default.fileExists(atPath: path)
                                 ? (URL(fileURLWithPath: path).deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath
                                 : "原文件已移动或删除")
                                .font(.caption).foregroundStyle(.secondary)
                                .lineLimit(1).truncationMode(.middle)
                        }
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Button {
                            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                        } label: { Image(systemName: "magnifyingglass") }
                        .buttonStyle(.borderless)
                        .disabled(!FileManager.default.fileExists(atPath: path))
                        .help("在访达中显示")
                        .accessibilityLabel("在访达中显示 \(URL(fileURLWithPath: path).lastPathComponent)")
                    }
                    .padding(.vertical, 10)

                    if path != payload.filePaths.last {
                        Divider()
                            .overlay(Color.white.opacity(0.10))
                    }
                }
            }
            .padding(.horizontal, 14)
            .background(Color.white.opacity(0.06))
            .clipShape(.rect(cornerRadius: 12, style: .continuous))
            Text("保留原文件，之后才能再次粘贴。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func richTextPreview(_ attributed: NSAttributedString) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            RichTextContent(attributed: attributed)
            .frame(maxWidth: .infinity, minHeight: 190, idealHeight: 220, maxHeight: 360, alignment: .topLeading)
            .background(Color(nsColor: .textBackgroundColor).opacity(0.58))
            .clipShape(.rect(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            }
        }
    }

    private func plainTextPreview(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView {
                Text(text.isEmpty ? "无内容" : text)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(16)
            }
            .frame(maxWidth: .infinity, minHeight: 190, idealHeight: 220, maxHeight: 360, alignment: .topLeading)
            .background(Color.white.opacity(0.06))
            .clipShape(.rect(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            }
        }
    }

    private func payloadNote(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.06))
            .clipShape(.rect(cornerRadius: 10, style: .continuous))
    }

    private func attributedString(from payload: StoredPasteboardPayload) -> NSAttributedString? {
        for item in payload.items {
            for representation in item.representations {
                let documentType: NSAttributedString.DocumentType
                switch representation.uti {
                case "public.html": documentType = .html
                case "public.rtf": documentType = .rtf
                case "com.apple.flat-rtfd": documentType = .rtfd
                default: continue
                }
                guard let data = representation.data else { continue }
                let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
                    .documentType: documentType,
                    .characterEncoding: String.Encoding.utf8.rawValue
                ]
                if let attributed = try? NSAttributedString(data: data, options: options, documentAttributes: nil) {
                    return attributed
                }
            }
        }
        return nil
    }

    private func imageData(from payload: StoredPasteboardPayload) -> Data? {
        for item in payload.items {
            for representation in item.representations where representation.uti == "public.png" || representation.uti == "public.tiff" {
                if let data = representation.data { return data }
            }
        }
        return nil
    }
}

/// An AppKit document surface preserves rich text attachments and original colors.
private struct RichTextContent: NSViewRepresentable {
    let attributed: NSAttributedString

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.appearance = NSAppearance(named: .aqua)
        // TextKit 1 lays out imported RTFD attachment cells on the first display,
        // including when this view is initially created inside a SwiftUI sheet.
        let text = NSTextView(usingTextLayoutManager: false)
        text.isEditable = false
        text.isSelectable = true
        text.isRichText = true
        text.importsGraphics = true
        text.drawsBackground = true
        text.backgroundColor = .white
        text.textColor = .black
        text.textContainerInset = NSSize(width: 16, height: 16)
        text.isVerticallyResizable = true
        text.isHorizontallyResizable = false
        text.autoresizingMask = [.width]
        text.textContainer?.widthTracksTextView = true
        scroll.documentView = text
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let text = scroll.documentView as? NSTextView else { return }
        if text.attributedString() != attributed {
            text.textStorage?.setAttributedString(attributed)
            if let container = text.textContainer { text.layoutManager?.ensureLayout(for: container) }
            text.needsDisplay = true
        }
    }
}
