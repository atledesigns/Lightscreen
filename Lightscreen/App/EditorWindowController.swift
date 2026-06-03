import AppKit
import SwiftUI

/// Everything the editor needs to dress up one image and save it: the picture
/// itself plus the facts we carry onto the saved file.
struct EditorInput {
    let image: NSImage
    let suggestedName: String   // no extension — the save sheet adds it
    let captureMode: String
    let sourceAppBundleID: String?
    let capturedAt: Date
}

/// The editor's brain. Holds the live, editable style (the "draft"), re-renders
/// the preview whenever a knob moves, and commits the finished image to the
/// library when you save. The view stays about layout; this does the work.
@MainActor
final class EditorModel: ObservableObject {
    /// Full-resolution original, used when we save.
    private let original: NSImage
    /// A shrunk copy used for the live preview, so sliders stay buttery on big shots.
    private let previewSource: NSImage
    private let input: EditorInput
    private let store: LibraryStore
    let recents: RecentDestinationsStore

    @Published var name: String
    @Published var draft: BeautifyDraft
    @Published private(set) var rendered: NSImage?

    /// Fired after a successful save (so the window closes and the library refreshes).
    var onSaved: (() -> Void)?
    /// Fired when the user backs out without saving.
    var onClose: (() -> Void)?

    init(input: EditorInput, store: LibraryStore, recents: RecentDestinationsStore) {
        self.original = input.image
        self.previewSource = input.image.downscaled(maxPixel: 1100)
        self.input = input
        self.store = store
        self.recents = recents
        self.name = input.suggestedName
        self.draft = BeautifyDraft.makeDefault(from: input.image)
        rerender()
    }

    /// Repaint the preview from the current draft. Called on every change.
    func rerender() {
        rendered = BeautifyRenderer.render(previewSource, style: draft.toStyle())
    }

    /// True when the backdrop is transparent — the view shows a checkerboard
    /// behind the canvas so see-through areas read clearly.
    var showsTransparencyCheckerboard: Bool {
        draft.backgroundKind == .transparent
    }

    // MARK: - Saving

    /// Render the full-resolution styled image and file it. New library entry —
    /// the original stays untouched.
    func commit(name: String, tags: [String], choice: SaveChoice) -> Bool {
        guard let data = BeautifyRenderer.pngData(original, style: draft.toStyle()) else {
            NSLog("Lightscreen: beautify render produced no data")
            return false
        }
        do {
            switch choice {
            case .library:
                try store.saveToLibrary(
                    data: data, name: name, tags: tags,
                    captureMode: input.captureMode,
                    outputMode: OutputMode.beautified.rawValue,
                    sourceAppBundleID: input.sourceAppBundleID,
                    capturedAt: input.capturedAt
                )
            case .folder(let folder):
                try store.saveToFolder(data: data, folder: folder, name: name, tags: tags)
                recents.remember(folder)
            case .other:
                guard let folder = pickFolder() else { return false } // cancelled: keep sheet open
                try store.saveToFolder(data: data, folder: folder, name: name, tags: tags)
                recents.remember(folder)
            }
            onSaved?()
            return true
        } catch {
            NSLog("Lightscreen: beautified save failed — \(error.localizedDescription)")
            return false
        }
    }

    private func pickFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Save Here"
        return panel.runModal() == .OK ? panel.url : nil
    }
}

/// Owns the single editor window. Opening a new image reuses the window, swapping
/// in a fresh model so the old shot doesn't linger.
@MainActor
final class EditorWindowController: NSObject, NSWindowDelegate {
    private let store: LibraryStore
    private let recents: RecentDestinationsStore
    private var window: NSWindow?
    private var model: EditorModel?

    /// Set by the app: called after a save so the library window can refresh.
    var onLibraryChanged: (() -> Void)?

    init(store: LibraryStore, recents: RecentDestinationsStore) {
        self.store = store
        self.recents = recents
    }

    /// Open the editor on a just-taken capture (the Beautified path).
    func open(from pending: PendingCapture) {
        open(EditorInput(
            image: pending.image,
            suggestedName: (pending.suggestedName as NSString).deletingPathExtension,
            captureMode: pending.captureMode.rawValue,
            sourceAppBundleID: pending.sourceAppBundleID,
            capturedAt: pending.capturedAt
        ))
    }

    /// Open the editor on any image + its facts (also used for past library shots).
    func open(_ input: EditorInput) {
        let model = EditorModel(input: input, store: store, recents: recents)
        model.onClose = { [weak self] in self?.close() }
        model.onSaved = { [weak self] in
            self?.onLibraryChanged?()
            self?.close()
        }
        self.model = model

        let win = window ?? makeWindow()
        win.contentView = NSHostingView(rootView: EditorView(model: model))
        window = win

        NSApp.activate()
        win.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1040, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        win.title = "Edit"
        win.titlebarAppearsTransparent = true
        win.isReleasedWhenClosed = false
        win.minSize = NSSize(width: 820, height: 560)
        win.delegate = self
        win.center()
        return win
    }

    private func close() {
        window?.orderOut(nil)
        model = nil
    }

    func windowWillClose(_ notification: Notification) {
        model = nil
    }
}
