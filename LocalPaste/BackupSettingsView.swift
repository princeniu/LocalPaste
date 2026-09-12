import AppKit
import SwiftUI
import UniformTypeIdentifiers

private struct PendingBackup: Identifiable {
    let id = UUID()
    let archive: ClipboardBackup
    let plan: BackupImportPlan
}

struct BackupSettingsView: View {
    @ObservedObject var store: ClipboardStore
    @State private var busy = false
    @State private var message: String?
    @State private var errorMessage: String?
    @State private var pending: PendingBackup?

    var body: some View {
        Section {
            HStack(spacing: 0) {
                statistic("历史", count: store.entries.count)
                statistic("收藏", count: store.entries.filter(\.isFavorite).count)
                statistic("分类", count: store.categories.count)
            }
            .padding(.vertical, 14)
            HStack {
                Button("导出备份…", systemImage: "square.and.arrow.up") { exportBackup() }
                Spacer()
                Button("从备份导入…", systemImage: "square.and.arrow.down") { selectBackup() }
            }
            .disabled(busy)
            if busy { ProgressView("正在处理…").controlSize(.small) }
            if let message {
                Label(message, systemImage: "checkmark.circle.fill")
                    .font(.callout).foregroundStyle(.secondary)
            }
        } header: { Text("备份与恢复") }
          footer: {
            Text("备份包含剪贴板内容，未加密，请妥善保存。文件类记录只保存引用，不包含原文件。")
        }
        .alert("未能完成操作", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("好") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
        .sheet(item: $pending) { pending in
            BackupImportView(store: store, archive: pending.archive, initialPlan: pending.plan) { result in
                message = result.entries.isEmpty && result.categories.isEmpty
                    ? "备份内容已在本机，无需重复导入。"
                    : "已导入 \(result.entries.count) 条历史、\(result.categories.count) 个分类。"
                self.pending = nil
            }
        }
    }

    private func statistic(_ title: String, count: Int) -> some View {
        VStack(spacing: 5) {
            Text(count.formatted()).font(.title2.weight(.semibold)).monospacedDigit()
            Text(title).font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity)
    }

    private func exportBackup() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "clipmori") ?? .data]
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = .current
        dateFormatter.dateFormat = "yyyy-MM-dd"
        panel.nameFieldStringValue = "Clipmori-\(dateFormatter.string(from: .now)).clipmori"
        panel.prompt = "导出"
        panel.message = "保存一份历史、收藏和分类的备份。"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        busy = true
        message = nil
        do {
            let snapshot = try store.backupSnapshot()
            Task { @MainActor in
                defer { busy = false }
                do {
                    try await Task.detached(priority: .userInitiated) {
                        try snapshot.preparingForExport().write(to: url)
                    }.value
                    message = "已导出 \(snapshot.entries.count) 条历史。"
                } catch { errorMessage = error.localizedDescription }
            }
        } catch {
            busy = false
            errorMessage = error.localizedDescription
        }
    }

    private func selectBackup() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "clipmori") ?? .data]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.prompt = "查看备份"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        busy = true
        message = nil
        Task { @MainActor in
            defer { busy = false }
            do {
                let archive = try await Task.detached(priority: .userInitiated) {
                    try ClipboardBackup.read(from: url)
                }.value
                pending = PendingBackup(archive: archive, plan: try store.planImport(archive))
            } catch { errorMessage = error.localizedDescription }
        }
    }
}

struct BackupImportView: View {
    @ObservedObject var store: ClipboardStore
    let archive: ClipboardBackup
    let onComplete: (BackupImportPlan) -> Void
    @State private var plan: BackupImportPlan
    @State private var importing = false
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    init(store: ClipboardStore, archive: ClipboardBackup, initialPlan: BackupImportPlan,
         onComplete: @escaping (BackupImportPlan) -> Void) {
        self.store = store
        self.archive = archive
        self.onComplete = onComplete
        _plan = State(initialValue: initialPlan)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("导入备份").font(.title2.weight(.semibold))
            Text(archive.createdAt.formatted(date: .abbreviated, time: .shortened))
                .font(.callout).foregroundStyle(.secondary)
            VStack(spacing: 10) {
                LabeledContent("新增历史", value: "\(plan.entries.count) 条")
                LabeledContent("其中收藏", value: "\(plan.favoriteCount) 条")
                LabeledContent("新增分类", value: "\(plan.categories.count) 个")
                LabeledContent("已有记录", value: "\(plan.skippedCount) 条，保留本机版本")
            }
            Text("同名分类自动合并，现有历史不会被覆盖。")
                .font(.callout).foregroundStyle(.secondary)
            if plan.requiredLimit > plan.previousLimit {
                Text("保留条数将从 \(plan.previousLimit) 提高至 \(plan.requiredLimit)，以保留全部历史。")
                    .font(.callout).foregroundStyle(.secondary)
            }
            if plan.fileCount > 0 {
                Text("文件类记录需要原文件仍在原位置，才能再次使用。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let errorMessage {
                Text(errorMessage).font(.callout).foregroundStyle(.red)
            }
            HStack {
                if importing { ProgressView().controlSize(.small) }
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(plan.entries.isEmpty && plan.categories.isEmpty ? "完成" : "导入") { confirmImport() }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }.disabled(importing)
        }
        .padding(28).frame(width: 440)
        .interactiveDismissDisabled(importing)
        .onChange(of: store.revision) { _, _ in refreshPreview() }
        .onChange(of: store.historyLimit) { _, _ in refreshPreview() }
    }

    private func refreshPreview() {
        do { plan = try store.planImport(archive); errorMessage = nil }
        catch { errorMessage = error.localizedDescription }
    }

    private func confirmImport() {
        importing = true
        Task { @MainActor in
            defer { importing = false }
            await Task.yield()
            do {
                let result = try store.importBackup(archive, preview: plan)
                onComplete(result)
            } catch {
                refreshPreview()
                errorMessage = error.localizedDescription
            }
        }
    }
}
