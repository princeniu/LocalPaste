import AppKit
import SwiftUI
import SwiftData

@main struct RenderCover {
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
  let view = NSHostingView(rootView: HistoryView(viewModel: model, store: store, onPaste: {_,_ in}, onClose: {}, onSettings: {}))
  let window = NSWindow(contentRect: NSRect(x: 0,y: 0,width: 1080,height: 344), styleMask: [.borderless], backing: .buffered, defer: false)
  window.contentView = view
  view.frame = NSRect(x: 0,y: 0,width: 1080,height: 344)
  view.layoutSubtreeIfNeeded()
  RunLoop.main.run(until: Date().addingTimeInterval(1))
  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
  view.cacheDisplay(in: view.bounds, to: rep)
  try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "output/portfolio/clipmori-real-ui.png"))
  print("Rendered actual HistoryView with in-memory sample data")
 }
}
