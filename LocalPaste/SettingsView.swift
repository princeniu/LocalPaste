import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var store: ClipboardStore
    @ObservedObject var shortcutManager: GlobalShortcutManager
    @ObservedObject var loginItemManager: LoginItemManager

    @State private var isRecordingShortcut = false
    @State private var showCreateCategory = false
    @State private var showRenameCategory = false
    @State private var newCategoryName = ""
    @State private var categoryToRename: ClipCategory?

    private let surfaceColor = Color(nsColor: .windowBackgroundColor)

    var body: some View {
        Form {
            if let error = store.lastErrorMessage {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                    Button("关闭错误提示") { store.lastErrorMessage = nil }
                } header: {
                    Text("操作失败")
                }
            }
            Section {
                Toggle(
                    "开启剪贴板采集",
                    isOn: Binding(
                        get: { !store.isPaused },
                        set: { store.isPaused = !$0 }
                    )
                )

                Text(store.isPaused
                     ? "已暂停采集。开启后仅记录新复制的内容。"
                     : "正在采集新复制的内容，排除应用规则仍然生效。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Stepper(value: $store.historyLimit, in: 50...5_000, step: 50) {
                    HStack(spacing: 12) {
                        Text("普通历史上限")
                        Spacer(minLength: 12)
                        Text("\(store.historyLimit) 条")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }

                Text("收藏条目不参与淘汰。历史只存储在本机的 LocalPaste Application Support 数据库中。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                sectionHeader("历史", symbol: "clock.arrow.circlepath")
            }

            Section {
                Toggle(
                    "登录时启动",
                    isOn: Binding(
                        get: { loginItemManager.isEnabled },
                        set: { loginItemManager.setEnabled($0) }
                    )
                )
                .disabled(!loginItemManager.allowsChanges)

                Text(loginItemManager.statusMessage)
                    .font(.footnote)
                    .foregroundStyle(loginItemManager.requiresApproval ? .orange : .secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if loginItemManager.requiresApproval && loginItemManager.allowsChanges {
                    Button("打开登录项设置…") {
                        loginItemManager.openSystemSettings()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                if !loginItemManager.allowsChanges {
                    Text("此 UI 验证副本仅展示登录项状态，开关已禁用。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let error = loginItemManager.lastErrorMessage {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } header: {
                sectionHeader("系统", symbol: "power")
            }

            Section {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("当前快捷键")
                            .font(.body.weight(.medium))
                        Text("用于打开 LocalPaste 面板")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 12)
                    Text(shortcutManager.shortcut.displayName)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.orange.opacity(0.12))
                        .clipShape(.capsule)
                        .overlay {
                            Capsule()
                                .stroke(Color.orange.opacity(0.32), lineWidth: 1)
                        }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("录制新的快捷键")
                        .font(.subheadline.weight(.medium))
                    HStack(spacing: 10) {
                        ShortcutRecorderView(
                            isRecording: isRecordingShortcut,
                            displayName: isRecordingShortcut ? "按下快捷键…" : shortcutManager.shortcut.displayName
                        ) { keyCode, modifiers in
                            isRecordingShortcut = false
                            let spec = ShortcutSpec(keyCode: UInt32(keyCode), modifiers: modifiers)
                            _ = shortcutManager.apply(spec)
                        }
                        .frame(width: 184, height: 32)

                        Button(isRecordingShortcut ? "取消" : "录制") {
                            isRecordingShortcut.toggle()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }

                if !shortcutManager.isRegistered {
                    Label("快捷键当前未注册。", systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
                if let error = shortcutManager.lastErrorMessage {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("注册失败会保留原快捷键，并显示系统返回的实际 OSStatus。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                sectionHeader("全局快捷键", symbol: "keyboard")
            }

            Section {
                ForEach(store.excludedApplications) { app in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "app.dashed")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(app.name)
                                .font(.body.weight(.medium))
                            Text(app.bundleIdentifier)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Button("移除") {
                            store.removeExcludedApplication(app)
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                    }
                }

                Button("添加应用…", systemImage: "plus") {
                    chooseExcludedApplication()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Text("排除检查先于内容读取，应用切换期间的变化会保守丢弃。macOS 不提供可靠的写入来源，排除属于尽力保护；复制敏感内容前请暂停采集。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                sectionHeader("排除应用", symbol: "hand.raised")
            }

            Section {
                ForEach(store.categories) { category in
                    HStack(spacing: 10) {
                        Image(systemName: "tag")
                            .foregroundStyle(.secondary)
                        Text(category.name)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button("重命名") {
                            categoryToRename = category
                            newCategoryName = category.name
                            showRenameCategory = true
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                        Button("删除", role: .destructive) {
                            store.deleteCategory(category)
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                    }
                }

                Button("新建分类", systemImage: "plus") {
                    newCategoryName = ""
                    showCreateCategory = true
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Text("删除分类不会删除剪贴板条目。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                sectionHeader("分类", symbol: "square.grid.2x2")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(surfaceColor)
        .tint(.orange)
        .padding(.top, 8)
        .frame(width: 520, height: 620)
        .onAppear {
            loginItemManager.refreshStatus()
        }
        .sheet(isPresented: $showCreateCategory) {
            CategoryEditor(title: "新建分类", store: store) { name in
                store.addCategory(named: name) != nil
            }
        }
        .sheet(isPresented: $showRenameCategory) {
            CategoryEditor(title: "重命名分类", name: newCategoryName, store: store) { name in
                guard let categoryToRename else { return false }
                return store.renameCategory(categoryToRename, to: name)
            }
        }
    }

    private func sectionHeader(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.headline)
            .foregroundStyle(.orange)
            .textCase(nil)
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
    var isRecording = false { didSet { updateAccessibility(); needsDisplay = true } }
    var displayName = "" { didSet { updateAccessibility(); needsDisplay = true } }
    var onRecord: ((UInt16, UInt32) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    private func updateAccessibility() {
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel("快捷键录制")
        setAccessibilityValue(isRecording ? "正在录制，请按下含修饰键的快捷键" : displayName)
        setAccessibilityHelp("使用旁边的录制或取消按钮控制录制。")
    }

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
        let fillColor = isRecording
            ? NSColor.systemOrange.withAlphaComponent(0.14)
            : NSColor.controlBackgroundColor
        fillColor.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8).fill()

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: isRecording ? NSColor.systemOrange : NSColor.labelColor,
            .paragraphStyle: paragraph
        ]
        let text = isRecording ? "按下快捷键…" : displayName
        (text as NSString).draw(
            in: NSRect(x: 8, y: (bounds.height - 17) / 2, width: bounds.width - 16, height: 17),
            withAttributes: attributes
        )

        let borderColor = isRecording
            ? NSColor.systemOrange.withAlphaComponent(0.82)
            : NSColor.white.withAlphaComponent(0.16)
        borderColor.setStroke()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8).stroke()
    }
}
