import SwiftUI

/// Where a shot should be filed. `library` is the app's own folder; `folder`
/// is a remembered recent destination; `other` means "let me pick in Finder".
enum SaveChoice: Hashable {
    case library
    case other
    case folder(URL)
}

/// The Apple-Preview-style save sheet that appears when you click the floating
/// preview. Name, Finder tags, and a "Where" dropdown. Esc cancels.
struct SavePopoverView: View {
    @State private var name: String
    @State private var tagsText: String = ""
    @State private var destination: SaveChoice = .library

    let recents: [URL]
    var onSave: (_ name: String, _ tags: [String], _ choice: SaveChoice) -> Void
    var onCancel: () -> Void

    init(
        initialName: String,
        recents: [URL],
        onSave: @escaping (String, [String], SaveChoice) -> Void,
        onCancel: @escaping () -> Void
    ) {
        _name = State(initialValue: initialName)
        self.recents = recents
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Save Screenshot")
                .font(.headline)

            field("Name") {
                TextField("Name", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            field("Tags") {
                TextField("comma, separated", text: $tagsText)
                    .textFieldStyle(.roundedBorder)
            }

            field("Where") {
                Picker("", selection: $destination) {
                    Text("Lightscreen library").tag(SaveChoice.library)
                    if !recents.isEmpty {
                        Divider()
                        ForEach(recents, id: \.self) { url in
                            Text(url.lastPathComponent).tag(SaveChoice.folder(url))
                        }
                    }
                    Divider()
                    Text("Other…").tag(SaveChoice.other)
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }

            HStack {
                Spacer()
                Button("Cancel") { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    onSave(cleanName, parsedTags, destination)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .frame(width: 320)
    }

    private func field<Content: View>(_ label: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            content()
        }
    }

    private var cleanName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Screenshot" : trimmed
    }

    private var parsedTags: [String] {
        tagsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
