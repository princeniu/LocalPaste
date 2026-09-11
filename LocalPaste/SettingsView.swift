import SwiftUI
import AppKit
import ApplicationServices

struct SettingsView: View {
    @ObservedObject var store: ClipboardStore
    @ObservedObject var shortcutManager: GlobalShortcutManager
    @ObservedObject var loginItemManager: LoginItemManager

    private enum Page: String, CaseIterable, Identifiable {
        case general = "通用", privacy = "隐私", categories = "分类", about = "关于"
        var id: Self { self }
    }
    @State private var page: Page = .general
    @State private var isRecordingShortcut = false
    @State private var showCreateCategory = false
    @State private var categoryToRename: ClipCategory?
    @State private var errorDetails: String?
    @State private var pasteAuthorized = AXIsProcessTrusted()

    var body: some View {
        VStack(spacing: 0) {
            Picker("设置", selection: $page) {
                ForEach(Page.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 28)
            .padding(.vertical, 18)

            Form {
                if let error = store.lastErrorMessage {
                    issueRow("操作未完成", details: error)
                }
                switch page {
                case .general: generalSettings
                case .privacy: privacySettings
                case .categories: categorySettings
                case .about: aboutSettings
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(.orange)
        .frame(width: 540, height: 480)
        .onAppear { refreshSystemStatus() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshSystemStatus()
        }
        .onChange(of: page) { _, _ in isRecordingShortcut = false }
        .onDisappear { isRecordingShortcut = false }
        .alert("详细信息", isPresented: Binding(
            get: { errorDetails != nil },
            set: { if !$0 { errorDetails = nil } }
        )) {
            Button("好", role: .cancel) { errorDetails = nil }
        } message: { Text(errorDetails ?? "") }
        .sheet(isPresented: $showCreateCategory) {
            CategoryEditor(title: "新建分类", store: store) { store.addCategory(named: $0) != nil }
        }
        .sheet(item: $categoryToRename) { category in
            CategoryEditor(title: "重命名分类", name: category.name, store: store) { name in
                store.renameCategory(category, to: name)
            }
        }
    }

    private var generalSettings: some View {
        Group {
            Section {
                Toggle(isOn: Binding(get: { !store.isPaused }, set: { store.isPaused = !$0 })) {
                    HStack(spacing: 8) {
                        Text("记录剪贴板历史")
                        Text(store.isPaused ? "已暂停" : "记录中")
                            .font(.caption)
                            .foregroundStyle(store.isPaused ? .orange : .secondary)
                    }
                }
                .accessibilityLabel("记录剪贴板历史")
                .accessibilityValue(store.isPaused ? "已暂停" : "记录中")
                Stepper(value: $store.historyLimit, in: 50...5_000, step: 50) {
                    HStack {
                        Text("保留条数")
                        Spacer()
                        Text("\(store.historyLimit) 条").foregroundStyle(.secondary).monospacedDigit()
                    }
                }
            } header: { Text("历史") }
              footer: { Text("收藏的内容会一直保留。") }

            Section("启动与快捷键") {
                Toggle("登录时启动", isOn: Binding(
                    get: { loginItemManager.isEnabled },
                    set: { loginItemManager.setEnabled($0) }
                ))
                .disabled(!loginItemManager.allowsChanges || !loginItemManager.isAvailable)
                if loginItemManager.requiresApproval {
                    HStack {
                        Label("等待系统允许", systemImage: "exclamationmark.circle").foregroundStyle(.orange)
                        Spacer()
                        Button("前往设置") { loginItemManager.openSystemSettings() }
                            .disabled(!loginItemManager.allowsChanges)
                    }
                } else if !loginItemManager.isAvailable {
                    Text("请将\(AppBrand.name)放入“应用程序”后重试。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let error = loginItemManager.lastErrorMessage {
                    issueRow("无法更改登录启动设置", details: error)
                }

                HStack {
                    Text("打开历史")
                    Spacer()
                    ShortcutRecorderView(
                        isRecording: isRecordingShortcut,
                        displayName: shortcutManager.shortcut.displayName,
                        onBeginRecording: { isRecordingShortcut = true },
                        onCancel: { isRecordingShortcut = false }
                    ) { code, modifiers in
                        isRecordingShortcut = false
                        _ = shortcutManager.apply(ShortcutSpec(keyCode: UInt32(code), modifiers: modifiers))
                    }
                    .frame(width: 156, height: 30)
                    if isRecordingShortcut {
                        Button("取消") { isRecordingShortcut = false }.controlSize(.small)
                    }
                }
                if let error = shortcutManager.lastErrorMessage {
                    issueRow("快捷键不可用，请换一个组合", details: error)
                } else if !shortcutManager.isRegistered {
                    Label("快捷键暂不可用", systemImage: "exclamationmark.circle")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
        }
    }

    private var privacySettings: some View {
        Group {
            Section("自动粘贴") {
                HStack {
                    Label(pasteAuthorized ? "已允许自动粘贴" : "需要辅助功能权限",
                          systemImage: pasteAuthorized ? "checkmark.circle.fill" : "hand.raised")
                        .foregroundStyle(pasteAuthorized ? Color.secondary : Color.primary)
                    Spacer()
                    if !pasteAuthorized {
                        Button("前往授权") {
                            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
                            _ = AXIsProcessTrustedWithOptions(options)
                        }
                        .disabled(!loginItemManager.allowsChanges)
                    }
                }
            }
            Section {
                ForEach(store.excludedApplications) { app in
                    HStack(spacing: 10) {
                        Image(nsImage: appIcon(app.bundleIdentifier))
                            .resizable().frame(width: 24, height: 24).accessibilityHidden(true)
                        Text(app.name).lineLimit(1)
                        Spacer()
                        Button { store.removeExcludedApplication(app) } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                        .help("移除 \(app.name)")
                        .accessibilityLabel("移除 \(app.name)")
                    }
                }
                Button("添加应用…", systemImage: "plus") { chooseExcludedApplication() }
            } header: { Text("忽略这些应用") }
              footer: { Text("应用排除受 macOS 限制，复制敏感内容前请先暂停记录。") }
            Section {
                Label("历史仅保存在这台 Mac", systemImage: "internaldrive")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var categorySettings: some View {
        Section {
            if store.categories.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "tag").font(.system(size: 28)).foregroundStyle(.tertiary)
                    Text("整理常用内容").font(.headline)
                    Text("用分类收纳工作、链接和灵感。")
                        .font(.callout).foregroundStyle(.secondary)
                    Button("新建分类", systemImage: "plus") { showCreateCategory = true }
                        .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 28)
            } else {
                ForEach(store.categories) { category in
                    HStack(spacing: 10) {
                        Image(systemName: "tag").foregroundStyle(.secondary)
                        Text(category.name).lineLimit(1)
                        Spacer()
                        Menu {
                            Button("重命名") { categoryToRename = category }
                            Button("删除分类", role: .destructive) { store.deleteCategory(category) }
                        } label: { Image(systemName: "ellipsis") }
                        .menuStyle(.borderlessButton).fixedSize()
                        .accessibilityLabel("管理分类 \(category.name)")
                    }
                }
                Button("新建分类", systemImage: "plus") { showCreateCategory = true }
            }
        } header: { Text("分类") }
          footer: { if !store.categories.isEmpty { Text("删除分类不会删除其中的历史。") } }
    }

    private var aboutSettings: some View {
        Section {
            VStack(spacing: 12) {
                Image(nsImage: AppBrand.icon)
                    .resizable().interpolation(.high)
                    .frame(width: 88, height: 88)
                    .accessibilityHidden(true)
                Text(AppBrand.displayName).font(.title2.weight(.semibold))
                Text("随手复制，随时找回。")
                    .foregroundStyle(.secondary)
                Text("版本 \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 24)
            DisclosureGroup("版本详情") {
                LabeledContent("构建", value: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—")
                if let revision = Bundle.main.infoDictionary?["LocalPasteRevision"] as? String, !revision.isEmpty {
                    LabeledContent("修订", value: revision)
                }
            }
            .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func issueRow(_ title: String, details: String) -> some View {
        HStack {
            Label(title, systemImage: "exclamationmark.circle").foregroundStyle(.orange)
            Spacer()
            Button("详情") { errorDetails = details }.controlSize(.small)
        }
    }

    private func refreshSystemStatus() {
        loginItemManager.refreshStatus()
        pasteAuthorized = AXIsProcessTrusted()
    }

    private func appIcon(_ identifier: String) -> NSImage {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return NSImage(systemSymbolName: "app", accessibilityDescription: nil) ?? NSImage()
    }

    private func chooseExcludedApplication() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.prompt = "添加"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let bundle = Bundle(url: url)
        let name = bundle?.localizedInfoDictionary?["CFBundleDisplayName"] as? String
            ?? bundle?.localizedInfoDictionary?["CFBundleName"] as? String
            ?? url.deletingPathExtension().lastPathComponent
        store.addExcludedApplication(bundleIdentifier: bundle?.bundleIdentifier ?? url.path, name: name)
    }
}

struct ShortcutRecorderView: NSViewRepresentable {
    let isRecording: Bool
    let displayName: String
    var onBeginRecording: () -> Void = {}
    var onCancel: () -> Void = {}
    let onRecord: (UInt16, UInt32) -> Void

    func makeNSView(context: Context) -> ShortcutCaptureView {
        let view = ShortcutCaptureView()
        view.onRecord = onRecord
        view.onBeginRecording = onBeginRecording
        view.onCancel = onCancel
        view.displayName = displayName
        view.isRecording = isRecording
        return view
    }

    func updateNSView(_ nsView: ShortcutCaptureView, context: Context) {
        nsView.onRecord = onRecord
        nsView.onBeginRecording = onBeginRecording
        nsView.onCancel = onCancel
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
    var onBeginRecording: (() -> Void)?
    var onCancel: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    private func updateAccessibility() {
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("打开历史快捷键")
        setAccessibilityValue(isRecording ? "请按下新的快捷键" : displayName)
        setAccessibilityHelp("点击修改，按 Esc 取消。")
    }

    override func mouseDown(with event: NSEvent) {
        onBeginRecording?()
        window?.makeFirstResponder(self)
    }

    override func accessibilityPerformPress() -> Bool {
        onBeginRecording?()
        window?.makeFirstResponder(self)
        return true
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording else { return super.performKeyEquivalent(with: event) }
        keyDown(with: event)
        return true
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            if event.keyCode == 36 || event.keyCode == 49 { onBeginRecording?() }
            else { super.keyDown(with: event) }
            return
        }
        if event.keyCode == 53 { onCancel?(); return }
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
