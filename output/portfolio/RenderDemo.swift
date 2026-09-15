import AppKit
import SwiftUI
import SwiftData

@main struct RenderDemo {
 @MainActor static func main() throws {
  let app = NSApplication.shared
  app.setActivationPolicy(.prohibited)
  app.appearance = NSAppearance(named: .aqua)
  let icon = NSImage(contentsOfFile: "LocalPaste/Assets.xcassets/BrandIcon.imageset/brand-icon@2x.png")!
  icon.setName("BrandIcon")
  let container = try ModelContainer(for: ClipboardEntry.self, ClipCategory.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
  let suite = "ClipmoriPortfolio.\(UUID())"
  let defaults = UserDefaults(suiteName: suite)!
  defer { defaults.removePersistentDomain(forName: suite) }
  let store = ClipboardStore(modelContainer: container, defaults: defaults)
  for (title, body, source) in [
   ("A little less friction.", "Small tools. Thoughtful details.\nMake room for the work that matters.", "备忘录"),
   ("周五设计回顾", "检查搜索与键盘操作\n整理界面细节\n记录下一次迭代的想法", "备忘录"),
   ("Apple Design Resources", "https://developer.apple.com/design/resources/", "Safari"),
   ("灵感，随手留下。", "好的想法不必一次写完。\n先复制下来，需要时再找回。", "TextEdit")
  ] {
   let payload = StoredPasteboardPayload(items: [.init(representations: [.init(uti: "public.utf8-plain-text", data: Data(body.utf8), stringValue: body, filePath: nil)])], plainText: body, displayText: body, contentType: "text", filePaths: [])
   _ = store.addEntry(payload: payload, sourceBundleIdentifier: "portfolio.sample", sourceName: source, title: title)
  }
  _ = store.addCategory(named: "工作")
  _ = store.addCategory(named: "灵感")
  if let entry = store.entries.last { store.toggleFavorite(entry) }
  let model = HistoryViewModel(store: store)
  model.ensureSelection()
  let output = URL(fileURLWithPath: "output/portfolio/demo-frames")
  try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
  let texts = [
   ["随手复制，随时找回。", "浏览之前复制的内容", "输入关键词", "输入关键词", "找到需要的内容", "预览完整内容", "收藏常用内容", "拾贴 · Clipmori"],
   ["Copy now. Find it later.", "Browse earlier clips", "Search your history", "Search your history", "Find the clip you need", "Preview the full content", "Keep favorites close", "Clipmori"]
  ]
  for (language, captions) in zip(["zh", "en"], texts) {
   for step in 0..<8 {
    model.selectedCategoryID = step == 6 ? "favorites" : nil
    model.query = step == 2 ? "A" : step == 3 ? "App" : (step == 4 || step == 5) ? "Apple" : ""
    model.ensureSelection()
    let preview = step == 5 ? model.selectedEntry : nil
    let scene = DemoScene(model: model, store: store, title: captions[step], language: language, step: step, preview: preview)
    let view = NSHostingView(rootView: scene)
    let window = NSWindow(contentRect: NSRect(x: 0,y: 0,width: 960,height: 540), styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentView = view
    view.frame = NSRect(x: 0,y: 0,width: 960,height: 540)
    view.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.15))
    let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
    view.cacheDisplay(in: view.bounds, to: rep)
    try rep.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(String(format: "%@-%02d.png", language, step)))
   }
  }
  print("Rendered bilingual demo scenes from actual HistoryView and PreviewView")
 }
}

struct DemoScene: View {
 let model: HistoryViewModel
 let store: ClipboardStore
 let title: String
 let language: String
 let step: Int
 let preview: ClipboardEntry?
 var body: some View {
  ZStack {
   LinearGradient(colors: [Color(red: 0.99, green: 0.98, blue: 0.96), Color(red: 1, green: 0.9, blue: 0.8)], startPoint: .topLeading, endPoint: .bottomTrailing)
   VStack(alignment: .leading, spacing: 0) {
    HStack(spacing: 9) {
     Image(nsImage: AppBrand.icon).resizable().frame(width: 30, height: 30)
     Text("拾贴 · Clipmori").font(.system(size: 18, weight: .semibold))
     Spacer()
     Text("macOS · " + (language == "zh" ? "开源" : "Open source")).font(.system(size: 13)).foregroundStyle(.secondary)
    }
    .padding(.bottom, 14)
    Text(title).font(.system(size: 34, weight: .bold)).foregroundStyle(Color(red: 0.1, green: 0.12, blue: 0.13))
    Text(language == "zh" ? "原生 macOS 剪贴板历史工具" : "A native macOS clipboard history app")
     .font(.system(size: 16)).foregroundStyle(.secondary).padding(.top, 6)
    Spacer(minLength: 10)
    Group {
     if let preview {
      PreviewView(entry: preview).frame(width: 680, height: 420).scaleEffect(0.68).frame(width: 820, height: 286)
     } else {
      HistoryView(viewModel: model, store: store, onPaste: {_,_ in}, onClose: {}, onSettings: {})
       .frame(width: 1080, height: 344).scaleEffect(0.76).frame(width: 820, height: 262)
     }
    }.shadow(color: .black.opacity(0.12), radius: 12, y: 8)
    Spacer(minLength: 10)
    HStack {
     Text(step == 7 ? "github.com/princeniu/LocalPaste" : (language == "zh" ? "真实界面 · 示例数据" : "Actual interface · Sample data"))
     Spacer()
     Text(String(format: "%02d / 08", step + 1))
    }.font(.system(size: 12)).foregroundStyle(.secondary)
   }.padding(.horizontal, 70).padding(.vertical, 28)
  }.frame(width: 960, height: 540).environment(\.colorScheme, .light)
 }
}
