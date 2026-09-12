import AppKit
import SwiftUI
import ApplicationServices

@MainActor enum WelcomeExperience {
    static let completedKey = "welcomeCompleted"

    static func shouldPresent(defaults: UserDefaults, hasExistingData: Bool) -> Bool {
        if defaults.object(forKey: completedKey) != nil { return !defaults.bool(forKey: completedKey) }
        let hasPreferences = [ClipboardStore.historyLimitKey, ClipboardStore.pausedKey,
                              ClipboardStore.excludedApplicationsKey].contains { defaults.object(forKey: $0) != nil }
        return !hasExistingData && !hasPreferences
    }
}

struct WelcomeView: View {
    @ObservedObject var shortcutManager: GlobalShortcutManager
    var allowsSystemChanges = true
    var startTitle = "开始使用"
    let onStart: () -> Void
    @State private var authorized = AXIsProcessTrusted()

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(spacing: 10) {
                Image(nsImage: AppBrand.icon).resizable().frame(width: 72, height: 72).accessibilityHidden(true)
                Text("欢迎使用\(AppBrand.name)").font(.title2.weight(.semibold))
                Text("随手复制，随时找回。")
                    .foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 18) {
                step("doc.on.doc", "像平时一样复制", "文字、图片和文件，都会留在历史中。")
                step("keyboard", "按 \(shortcutManager.shortcut.displayName) 打开历史", "也可以从菜单栏打开。")
                step("mouse", "滚动浏览，点击粘贴", "上下滚轮浏览卡片，空格预览内容。")
            }

            HStack(spacing: 12) {
                Image(systemName: authorized ? "checkmark.circle.fill" : "cursorarrow.click")
                    .foregroundStyle(authorized ? .green : .orange)
                VStack(alignment: .leading, spacing: 4) {
                    Text(authorized ? "已允许自动粘贴" : "允许自动粘贴").font(.callout.weight(.medium))
                    if !authorized {
                        Text("未授权时，也可复制后手动按 ⌘V。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                if !authorized {
                    Button("前往授权") {
                        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
                        _ = AXIsProcessTrustedWithOptions(options)
                    }.disabled(!allowsSystemChanges)
                }
            }
            .padding(14)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))

            HStack {
                Label("历史保存在这台 Mac", systemImage: "internaldrive")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(startTitle, action: onStart)
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
        }
        .padding(28).frame(width: 460)
        .tint(.orange)
        .onAppear { authorized = AXIsProcessTrusted() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            authorized = AXIsProcessTrusted()
        }
    }

    private func step(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol).font(.system(size: 20)).foregroundStyle(.orange).frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.callout.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
