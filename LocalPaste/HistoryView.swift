import SwiftUI

struct HistoryView: View {
    @ObservedObject var viewModel: HistoryViewModel
    @ObservedObject var store: ClipboardStore
    let onPaste: (ClipboardEntry, Bool) -> Void
    let onClose: () -> Void
    let onSettings: () -> Void

    @State private var showCreateCategory = false
    @State private var showRenameCategory = false
    @State private var showClearConfirmation = false
    @State private var categoryName = ""
    @State private var categoryToRename: ClipCategory?
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            categoryBar
            content
            footer
        }
        .padding(18)
        .frame(minWidth: 720, minHeight: 318)
        .background(.regularMaterial)
        .clipShape(.rect(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        }
        .onAppear { viewModel.ensureSelection() }
        .onChange(of: viewModel.query) { _, _ in viewModel.ensureSelection() }
        .onChange(of: viewModel.selectedCategoryID) { _, _ in viewModel.ensureSelection() }
        .onMoveCommand { direction in
            guard !searchFocused else { return }
            switch direction {
            case .left: viewModel.moveSelection(by: -1)
            case .right: viewModel.moveSelection(by: 1)
            default: break
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
        .alert("新建分类", isPresented: $showCreateCategory) {
            TextField("分类名称", text: $categoryName)
            Button("取消", role: .cancel) { }
            Button("创建") {
                _ = store.addCategory(named: categoryName)
                categoryName = ""
            }
        }
        .alert("重命名分类", isPresented: $showRenameCategory) {
            TextField("分类名称", text: $categoryName)
            Button("取消", role: .cancel) { }
            Button("保存") {
                if let categoryToRename {
                    store.renameCategory(categoryToRename, to: categoryName)
                }
                categoryName = ""
                categoryToRename = nil
            }
        }
        .confirmationDialog("清空历史", isPresented: $showClearConfirmation) {
            Button("清空非收藏条目", role: .destructive) {
                store.clearHistory(preservingFavorites: true)
                viewModel.ensureSelection()
            }
            Button("取消", role: .cancel) { }
        } message: {
            Text("默认保留收藏条目。此操作只删除 LocalPaste 的本地历史，不会删除原文件。")
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.on.clipboard")
                .foregroundStyle(.cyan)
                .font(.title2)
            Text("LocalPaste")
                .font(.headline)
            Text("\(viewModel.visibleEntries.count) 条")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("搜索内容、标题或来源", text: $viewModel.query)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                    .onSubmit { viewModel.ensureSelection() }
                if !viewModel.query.isEmpty {
                    Button("清除", systemImage: "xmark.circle.fill") {
                        viewModel.query = ""
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("清除搜索")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(width: 280)
            .background(Color(nsColor: .textBackgroundColor).opacity(0.45))
            .clipShape(.rect(cornerRadius: 9))
            Button("设置", systemImage: "gear") {
                onSettings()
            }
            .buttonStyle(.plain)
            .help("打开设置")
            Button("关闭", systemImage: "xmark") { onClose() }
                .buttonStyle(.plain)
                .help("关闭面板")
        }
    }

    private var categoryBar: some View {
        HStack(spacing: 7) {
            categoryChip(title: "全部", id: nil)
            categoryChip(title: "收藏", id: "favorites", symbol: "heart.fill")
            ForEach(store.categories) { category in
                categoryChip(title: category.name, id: category.id.uuidString)
                    .contextMenu {
                        Button("重命名") {
                            categoryToRename = category
                            categoryName = category.name
                            showRenameCategory = true
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
                categoryName = ""
                showCreateCategory = true
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.cyan)
            Spacer()
            if store.isPaused {
                Label("已暂停", systemImage: "pause.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .font(.caption)
    }

    private func categoryChip(title: String, id: String?, symbol: String? = nil) -> some View {
        Button {
            viewModel.selectedCategoryID = id
        } label: {
            HStack(spacing: 4) {
                if let symbol { Image(systemName: symbol) }
                Text(title)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(viewModel.selectedCategoryID == id ? Color.cyan.opacity(0.22) : Color.white.opacity(0.08))
            .foregroundStyle(viewModel.selectedCategoryID == id ? .cyan : .primary)
            .clipShape(.capsule)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.visibleEntries.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "clipboard")
                    .font(.system(size: 32))
                    .foregroundStyle(.secondary)
                Text(viewModel.query.isEmpty ? "还没有新的剪贴板历史" : "没有匹配条目")
                    .font(.headline)
                Text(viewModel.query.isEmpty ? "复制文字、图片或 Finder 文件后，LocalPaste 会从启动后开始记录。" : "尝试搜索内容、标题或来源应用。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(viewModel.visibleEntries) { entry in
                        entryCard(entry)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func entryCard(_ entry: ClipboardEntry) -> some View {
        Button {
            viewModel.select(entry)
            onPaste(entry, false)
        } label: {
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: entry.contentType.symbolName)
                        .foregroundStyle(.cyan)
                    Text(entry.contentType.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if entry.isFavorite {
                        Image(systemName: "heart.fill")
                            .foregroundStyle(.pink)
                    }
                }
                Text(entry.title.isEmpty ? (entry.payload?.displayText ?? "无标题") : entry.title)
                    .font(.headline)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(entry.payload?.displayText ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 0)
                HStack {
                    Text(entry.sourceName)
                        .lineLimit(1)
                    Spacer()
                    Text(entry.createdAt, style: .relative)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            .padding(13)
            .frame(width: 214, height: 162, alignment: .topLeading)
            .background(viewModel.selectedID == entry.id ? Color.cyan.opacity(0.16) : Color.white.opacity(0.07))
            .clipShape(.rect(cornerRadius: 13))
            .overlay {
                RoundedRectangle(cornerRadius: 13)
                    .stroke(viewModel.selectedID == entry.id ? Color.cyan.opacity(0.8) : Color.white.opacity(0.1), lineWidth: viewModel.selectedID == entry.id ? 1.5 : 1)
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("粘贴") { onPaste(entry, false) }
            Button("纯文本粘贴") { onPaste(entry, true) }
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
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if let statusMessage = viewModel.statusMessage {
                Label(statusMessage, systemImage: statusMessage == "已粘贴" ? "checkmark.circle" : "info.circle")
                    .font(.caption)
                    .foregroundStyle(statusMessage == "已粘贴" ? .green : .orange)
                    .lineLimit(1)
            } else {
                Text("← → 选择 · Enter 粘贴 · Space 预览 · Esc 关闭")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("清空历史", systemImage: "trash") {
                showClearConfirmation = true
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
        }
    }
}
