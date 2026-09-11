import Foundation
import SwiftUI
import AppKit

struct HistoryView: View {
    @ObservedObject var viewModel: HistoryViewModel
    @ObservedObject var store: ClipboardStore
    let onPaste: (ClipboardEntry, Bool) -> Void
    let onClose: () -> Void
    let onSettings: () -> Void

    @State private var showCreateCategory = false
    @State private var showClearConfirmation = false
    @State private var showStoreError = false
    @State private var categoryToRename: ClipCategory?
    @State private var hoveredEntryID: UUID?
    @FocusState private var searchFocused: Bool
    @FocusState private var focusedEntryID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            categoryBar
            content
            footer
        }
        .padding(16)
        .frame(minWidth: 720, minHeight: 344)
        .background(.regularMaterial)
        .clipShape(.rect(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        }
        .onAppear { viewModel.ensureSelection() }
        .onChange(of: focusedEntryID) { _, id in
            viewModel.focusedCardID = id
            if let id { viewModel.selectedID = id }
        }
        .onChange(of: viewModel.selectedID) { _, id in
            if focusedEntryID != nil {
                focusedEntryID = id
            }
        }
        .sheet(isPresented: Binding(
            get: { viewModel.previewEntryID != nil },
            set: { isPresented in if !isPresented { viewModel.previewEntryID = nil } }
        )) {
            if let entry = viewModel.store.entries.first(where: { $0.id == viewModel.previewEntryID }) {
                PreviewView(entry: entry)
            }
        }
        .sheet(isPresented: $showCreateCategory) {
            CategoryEditor(title: "新建分类", store: store) { name in
                store.addCategory(named: name) != nil
            }
        }
        .sheet(item: $categoryToRename) { category in
            CategoryEditor(title: "重命名分类", name: category.name, store: store) { name in
                store.renameCategory(category, to: name)
            }
        }
        .alert("操作失败", isPresented: $showStoreError) {
            Button("知道了") { store.lastErrorMessage = nil }
        } message: {
            Text(store.lastErrorMessage ?? "")
        }
        .confirmationDialog("清空历史", isPresented: $showClearConfirmation) {
            Button("清空非收藏条目", role: .destructive) {
                store.clearHistory(preservingFavorites: true)
                viewModel.ensureSelection()
            }
            Button("取消", role: .cancel) { }
        } message: {
            Text("收藏会保留，原文件不会被删除。")
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            HStack(spacing: 9) {
                Image(nsImage: AppBrand.icon)
                    .resizable().interpolation(.high)
                    .frame(width: 28, height: 28)
                    .accessibilityHidden(true)
                Text(AppBrand.name).font(.headline)
            }

            Spacer(minLength: 12)
            searchField
            Menu {
                Button("清空历史…", role: .destructive) { showClearConfirmation = true }
            } label: { Image(systemName: "ellipsis.circle") }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .accessibilityLabel("更多操作")
            Button {
                onSettings()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 14, weight: .medium))
            }
            .buttonStyle(.borderless)
            .frame(width: 24, height: 24)
            .help("打开设置")
            .accessibilityLabel("设置")
            Button {
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.borderless)
            .frame(width: 24, height: 24)
            .help("关闭面板")
            .accessibilityLabel("关闭面板")
        }
        .frame(height: 34)
    }

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            TextField("搜索历史", text: $viewModel.query)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .onSubmit { viewModel.ensureSelection() }
                .help("搜索内容或来源应用")
            if !viewModel.query.isEmpty {
                Button("清除", systemImage: "xmark.circle.fill") {
                    viewModel.query = ""
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("清除搜索")
            }
        }
        .padding(.horizontal, 9)
        .frame(width: 268, height: 30)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.72))
        .clipShape(.rect(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(searchFocused ? Color.orange.opacity(0.72) : Color.white.opacity(0.12), lineWidth: 1)
        }
    }

    private var categoryBar: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    categoryChip(title: "全部", id: nil)
                    categoryChip(title: "收藏", id: "favorites", symbol: "heart.fill")
                    ForEach(store.categories) { category in
                        categoryChip(title: category.name, id: category.id.uuidString)
                            .contextMenu {
                                Button("重命名") {
                                    categoryToRename = category
                                }
                                Button("删除分类", role: .destructive) {
                                    if viewModel.selectedCategoryID == category.id.uuidString {
                                        viewModel.selectedCategoryID = nil
                                    }
                                    store.deleteCategory(category)
                                }
                            }
                    }
                    Button("新建分类", systemImage: "plus") {
                        showCreateCategory = true
                    }
                    .buttonStyle(.borderless)
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.orange)
                    .help("新建分类")
                }
            }
            if store.isPaused {
                Button { store.isPaused = false } label: {
                    Label("继续记录", systemImage: "play.circle.fill")
                }
                .buttonStyle(.borderless)
                .font(.caption)
                .foregroundStyle(.orange)
                .help("已暂停，点击继续记录")
                .fixedSize()
            }
        }
        .font(.caption)
        .frame(height: 26)
    }

    private func categoryChip(title: String, id: String?, symbol: String? = nil) -> some View {
        Button {
            viewModel.selectedCategoryID = id
        } label: {
            HStack(spacing: 4) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 10, weight: .semibold))
                }
                Text(title)
                    .lineLimit(1)
            }
            .padding(.horizontal, 9)
            .frame(height: 25)
            .background(viewModel.selectedCategoryID == id ? Color.orange.opacity(0.18) : Color.white.opacity(0.07))
            .foregroundStyle(viewModel.selectedCategoryID == id ? .orange : .primary)
            .clipShape(.capsule)
            .overlay {
                Capsule()
                    .stroke(viewModel.selectedCategoryID == id ? Color.orange.opacity(0.5) : Color.white.opacity(0.08), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.visibleEntries.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "clipboard")
                    .font(.system(size: 28, weight: .regular))
                    .foregroundStyle(.secondary)
                Text(viewModel.emptyTitle)
                    .font(.headline)
                Text(viewModel.emptyHint)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                if !viewModel.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button("清除搜索") { viewModel.query = "" }
                        .buttonStyle(.bordered)
                } else if store.isPaused && viewModel.selectedCategoryID == nil {
                    Button("继续记录") { store.isPaused = false }
                        .buttonStyle(.borderedProminent)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(viewModel.visibleEntries) { entry in
                            entryCard(entry).id(entry.id)
                        }
                    }
                    .padding(.vertical, 5)
                }
                .onChange(of: viewModel.selectedID) { _, id in
                    if let id { proxy.scrollTo(id, anchor: .center) }
                }
                .onAppear {
                    if let id = viewModel.selectedID { proxy.scrollTo(id, anchor: .center) }
                }
            }
            .frame(height: 194)
        }
    }

    private func entryCard(_ entry: ClipboardEntry) -> some View {
        let isSelected = viewModel.selectedID == entry.id
        let isHovered = hoveredEntryID == entry.id
        let isFocused = focusedEntryID == entry.id
        let title = entry.title.isEmpty ? store.displayText(for: entry) : entry.title

        return Button {
            viewModel.select(entry)
            onPaste(entry, false)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 7) {
                    Image(systemName: entry.contentType.symbolName)
                        .font(.system(size: 11, weight: .semibold))
                    Text(entry.contentType.label)
                        .font(.caption2.weight(.medium))
                    Spacer(minLength: 4)
                    if entry.isFavorite {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.pink)
                            .accessibilityLabel("已收藏")
                    }
                }
                .foregroundStyle(.secondary)

                Text(title)
                    .font(.headline)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)

                cardPreview(entry)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 0)
                HStack(spacing: 5) {
                    Text(entry.sourceName)
                        .lineLimit(1)
                    Circle()
                        .frame(width: 2, height: 2)
                        .foregroundStyle(.tertiary)
                    Text(entry.createdAt, style: .relative)
                        .lineLimit(1)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            .padding(13)
            .frame(width: 236, height: 184, alignment: .topLeading)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? Color.orange.opacity(0.13) : Color(nsColor: .controlBackgroundColor).opacity(isHovered ? 0.78 : 0.56))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        isFocused ? Color.orange : (isSelected ? Color.orange.opacity(0.78) : (isHovered ? Color.white.opacity(0.34) : Color.white.opacity(0.12))),
                        lineWidth: isFocused ? 2 : (isSelected ? 1.5 : 1)
                    )
            }
            .contentShape(.rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .focusable()
        .focused($focusedEntryID, equals: entry.id)
        .focusEffectDisabled()
        .onKeyPress(.return) {
            viewModel.select(entry)
            onPaste(entry, false)
            return .handled
        }
        .onKeyPress(.space) {
            viewModel.select(entry)
            viewModel.showPreviewForSelection()
            return .handled
        }
        .help("点击粘贴；Space 预览；右键查看更多操作")
        .onHover { isHovering in
            hoveredEntryID = isHovering ? entry.id : nil
        }
        .contextMenu {
            Button("粘贴") { onPaste(entry, false) }
            Button("纯文本粘贴") { onPaste(entry, true) }
                .disabled(store.plainText(for: entry) == nil)
            Button(entry.isFavorite ? "取消收藏" : "收藏") { store.toggleFavorite(entry) }
            Button("预览") {
                viewModel.select(entry)
                viewModel.previewEntryID = entry.id
            }
            Menu("加入分类") {
                if store.categories.isEmpty {
                    Text("暂无分类")
                } else {
                    ForEach(store.categories) { category in
                        Button(category.name) { store.assign(entry, to: category) }
                    }
                }
            }
            Menu("移出分类") {
                ForEach(store.categories.filter { entry.categoryIDs.contains($0.id.uuidString) }) { category in
                    Button(category.name) { store.remove(entry, from: category) }
                }
            }
            Divider()
            Button("删除", role: .destructive) {
                store.delete(entry)
                viewModel.ensureSelection()
            }
        }
        .accessibilityLabel("\(title)，\(entry.contentType.label)，来自\(entry.sourceName)")
        .accessibilityValue(isSelected ? "已选中" : "")
    }

    @ViewBuilder
    private func cardPreview(_ entry: ClipboardEntry) -> some View {
        if let payload = entry.payload {
            switch entry.contentType {
            case .image, .mixed:
                if let data = imageData(from: payload), let image = NSImage(data: data) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, minHeight: 66, maxHeight: 66, alignment: .leading)
                        .background(Color.black.opacity(0.12))
                        .clipShape(.rect(cornerRadius: 7))
                } else {
                    textPreview(payload.displayText.isEmpty ? "图片" : payload.displayText)
                }
            case .fileReference:
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(payload.filePaths.prefix(2)), id: \.self) { path in
                        HStack(spacing: 6) {
                            Image(systemName: "doc.fill")
                                .foregroundStyle(.secondary)
                            Text(path.components(separatedBy: "/").last ?? path)
                                .lineLimit(1)
                        }
                    }
                    if payload.filePaths.count > 2 {
                        Text("+\(payload.filePaths.count - 2) 个文件")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.callout)
            default:
                let text = store.displayText(for: entry)
                let lines = text.components(separatedBy: .newlines)
                let excerpt = lines.first == entry.title ? lines.dropFirst().joined(separator: "\n") : text
                textPreview(excerpt.isEmpty ? "\(text.count) 个字符" : excerpt)
            }
        } else {
            textPreview("无法读取内容")
        }
    }

    private func textPreview(_ text: String) -> some View {
        Text(text.isEmpty ? "无内容" : text)
            .font(.callout)
            .foregroundStyle(.primary)
            .lineLimit(3)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func imageData(from payload: StoredPasteboardPayload) -> Data? {
        for item in payload.items {
            for representation in item.representations where representation.uti == "public.png" || representation.uti == "public.tiff" {
                if let data = representation.data { return data }
            }
        }
        return nil
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if let error = store.lastErrorMessage {
                Button { showStoreError = true } label: {
                    Label("操作未完成 · 查看详情", systemImage: "exclamationmark.triangle")
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
                .help(error)
                .accessibilityHint("打开完整错误说明")
            } else if let statusMessage = viewModel.statusMessage {
                Label(statusMessage, systemImage: statusMessage == "已粘贴" ? "checkmark.circle" : "info.circle")
                    .font(.caption)
                    .foregroundStyle(statusMessage == "已粘贴" ? .green : .orange)
                    .lineLimit(1)
            } else {
                HStack(spacing: 14) {
                    keyboardHint("↵", action: "粘贴")
                    keyboardHint("空格", action: "预览")
                }
                .help("← → 选择 · Return 粘贴 · 空格预览 · Esc 关闭")
            }
            Spacer()
            Text("\(viewModel.visibleEntries.count) 条")
                .font(.caption).foregroundStyle(.secondary).monospacedDigit()
        }
        .frame(height: 18)
    }

    private func keyboardHint(_ key: String, action: String) -> some View {
        HStack(spacing: 5) {
            Text(key).font(.system(size: 10, weight: .medium))
                .padding(.horizontal, 4).padding(.vertical, 1)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 3))
            Text(action).font(.caption)
        }
        .foregroundStyle(.secondary)
    }
}
