import SwiftUI
import AppKit

struct PreviewView: View {
    let entry: ClipboardEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                Label(entry.contentType.label, systemImage: entry.contentType.symbolName)
                    .font(.headline)
                Spacer()
                Text(entry.sourceName)
                    .foregroundStyle(.secondary)
            }

            if let payload = entry.payload {
                previewContent(payload)
            } else {
                Text("无法读取此条目的本地内容。")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(22)
        .frame(minWidth: 480, minHeight: 280)
        .background(.regularMaterial)
    }

    @ViewBuilder
    private func previewContent(_ payload: StoredPasteboardPayload) -> some View {
        if let imageData = imageData(from: payload), let image = NSImage(data: imageData) {
            VStack(alignment: .leading, spacing: 12) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 560, maxHeight: 360)
                if !payload.plainText.isEmpty {
                    Text(payload.plainText)
                        .font(.body)
                        .textSelection(.enabled)
                }
            }
        } else if !payload.filePaths.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("文件引用不会复制文件本体；原文件移动或删除后引用可能失效。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                ForEach(payload.filePaths, id: \.self) { path in
                    Label {
                        Text(path)
                            .textSelection(.enabled)
                    } icon: {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                            .resizable()
                            .frame(width: 24, height: 24)
                    }
                }
            }
        } else if let attributed = attributedString(from: payload) {
            ScrollView {
                Text(AttributedString(attributed))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(4)
            }
            .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
            .clipShape(.rect(cornerRadius: 10))
        } else {
            ScrollView {
                Text(payload.displayText)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(4)
            }
            .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
            .clipShape(.rect(cornerRadius: 10))
        }
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
