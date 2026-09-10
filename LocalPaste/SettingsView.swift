import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var store: ClipboardStore
    @ObservedObject var shortcutManager: GlobalShortcutManager

    @State private var isRecordingShortcut = false
    @State private var showCreateCategory = false
    @State private var showRenameCategory = false
    @State private var newCategoryName = ""
    @State private var categoryToRename: ClipCategory?

    var body: some View {
        Form {
            Section {
                Toggle("暂停剪贴板采集", isOn: $store.isPaused)
                Stepper(value: $store.historyLimit, in: 50...5_000, step: 50) {
                    HStack {
                        Text("普通历史上限")
                        Spacer()
                        Text("\(store.historyLimit) 条")
                            .foregroundStyle(.secondary)
                    }
                }
                Text("收藏条目不参与淘汰。历史只存储在本机的 LocalPaste Application Support 数据库中。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("历史")
            }

            Section {
                HStack {
                    Text("当前快捷键")
                    Spacer()
                    Text(shortcutManager.shortcut.displayName)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 10) {
                    ShortcutRecorderView(
                        isRecording: isRecordingShortcut,
                        displayName: isRecordingShortcut ? "按下快捷键…" : shortcutManager.shortcut.displayName
                    ) { keyCode, modifiers in
                        isRecordingShortcut = false
                        let spec = ShortcutSpec(keyCode: UInt32(keyCode), modifiers: modifiers)
                        _ = shortcutManager.apply(spec)
                    }
                    .frame(width: 180, height: 30)
                    Button(isRecordingShortcut ? "取消" : "录制") {
                        isRecordingShortcut.toggle()
                    }
                }
                if !shortcutManager.isRegistered {
                    Label("快捷键当前未注册。", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
                if let error = shortcutManager.lastErrorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .textSelection(.enabled)
                }
                Text("注册失败会保留原快捷键，并显示系统返回的实际 OSStatus。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("全局快捷键")
            }

            Section {
                ForEach(store.excludedApplications) { app in
                    HStack {
                        Image(systemName: "app.dashed")
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading) {
                            Text(app.name)
                            Text(app.bundleIdentifier)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("移除") { store.removeExcludedApplication(app) }
                            .buttonStyle(.borderless)
                    }
                }
                Button("添加应用…", systemImage: "plus") {
                    chooseExcludedApplication()
                }
                Text("排除检查先于内容读取，应用切换期间的变化会保守丢弃。macOS 不提供可靠的写入来源，排除属于尽力保护；复制敏感内容前请暂停采集。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("排除应用")
            }

            Section {
                ForEach(store.categories) { category in
                    HStack {
                        Text(category.name)
                        Spacer()
                        Button("重命名") {
                            categoryToRename = category
                            newCategoryName = category.name
                            showRenameCategory = true
                        }
                        .buttonStyle(.borderless)
                        Button("删除", role: .destructive) {
                            store.deleteCategory(category)
                        }
                        .buttonStyle(.borderless)
                    }
                }
                Button("新建分类", systemImage: "plus") {
                    newCategoryName = ""
                    showCreateCategory = true
                }
                Text("删除分类不会删除剪贴板条目。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("分类")
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 620)
        .padding(.top, 12)
        .alert("新建分类", isPresented: $showCreateCategory) {
            TextField("分类名称", text: $newCategoryName)
            Button("取消", role: .cancel) { }
            Button("创建") {
                _ = store.addCategory(named: newCategoryName)
                newCategoryName = ""
            }
        }
        .alert("重命名分类", isPresented: $showRenameCategory) {
            TextField("分类名称", text: $newCategoryName)
            Button("取消", role: .cancel) { }
            Button("保存") {
                if let categoryToRename {
                    store.renameCategory(categoryToRename, to: newCategoryName)
                }
                newCategoryName = ""
                categoryToRename = nil
            }
        }
    }

    private func chooseExcludedApplication() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.prompt = "排除"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let bundle = Bundle(url: url)
        let bundleIdentifier = bundle?.bundleIdentifier ?? url.path
        let name = bundle?.localizedInfoDictionary?["CFBundleDisplayName"] as? String
            ?? bundle?.localizedInfoDictionary?["CFBundleName"] as? String
            ?? url.deletingPathExtension().lastPathComponent
        store.addExcludedApplication(bundleIdentifier: bundleIdentifier, name: name)
    }
}

struct ShortcutRecorderView: NSViewRepresentable {
    let isRecording: Bool
    let displayName: String
    let onRecord: (UInt16, UInt32) -> Void

    func makeNSView(context: Context) -> ShortcutCaptureView {
        let view = ShortcutCaptureView()
        view.onRecord = onRecord
        view.displayName = displayName
        view.isRecording = isRecording
        return view
    }

    func updateNSView(_ nsView: ShortcutCaptureView, context: Context) {
        nsView.onRecord = onRecord
        nsView.displayName = displayName
        nsView.isRecording = isRecording
        if isRecording {
            nsView.window?.makeFirstResponder(nsView)
        }
    }
}

final class ShortcutCaptureView: NSView {
    var isRecording = false { didSet { needsDisplay = true } }
    var displayName = "" { didSet { needsDisplay = true } }
    var onRecord: ((UInt16, UInt32) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else { return }
        let modifiers = event.modifierFlags.carbonShortcutModifiers
        guard modifiers != 0 else {
            NSSound.beep()
            return
        }
        onRecord?(event.keyCode, modifiers)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.controlBackgroundColor.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 7, yRadius: 7).fill()
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph
        ]
        let text = isRecording ? "按下快捷键…" : displayName
        (text as NSString).draw(in: NSRect(x: 6, y: (bounds.height - 17) / 2, width: bounds.width - 12, height: 17), withAttributes: attributes)
        NSColor.separatorColor.setStroke()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 7, yRadius: 7).stroke()
    }
}
