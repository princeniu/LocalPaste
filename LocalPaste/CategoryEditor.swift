import SwiftUI

struct CategoryEditor: View {
    let title: String
    @ObservedObject var store: ClipboardStore
    let onSave: (String) -> Bool
    @State private var name: String
    @FocusState private var nameFocused: Bool
    @Environment(\.dismiss) private var dismiss

    init(title: String, name: String = "", store: ClipboardStore, onSave: @escaping (String) -> Bool) {
        self.title = title
        self.store = store
        self.onSave = onSave
        _name = State(initialValue: name)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.headline)
            TextField("分类名称", text: $name)
                .focused($nameFocused)
                .onSubmit(save)
            if let error = store.lastErrorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            HStack {
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("保存", action: save).keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 340)
        .onAppear { nameFocused = true }
    }

    private func save() {
        if onSave(name) { dismiss() }
    }
}
