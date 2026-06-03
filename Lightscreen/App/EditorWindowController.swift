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
    /// A tiny copy used to render the vibe-strip thumbnails (lots of them, fast).
    private let thumbSource: NSImage
    private let input: EditorInput
    private let store: LibraryStore
    let recents: RecentDestinationsStore
    let vibes: VibeStore

    @Published var name: String
    @Published var draft: BeautifyDraft
    @Published private(set) var rendered: NSImage?

    /// How many panels a tall capture is split into (1 = not split), and where
    /// the cuts fall (fractions down from the top). Kept out of the draft so
    /// dragging a cut line doesn't trigger a full re-render.
    @Published var splitCount = 1
    @Published var splitFractions: [Double] = []

    private static let ratioKey = "last_aspect_ratio"

    /// Fired after a successful save (so the window closes and the library refreshes).
    var onSaved: (() -> Void)?
    /// Fired when the user backs out without saving.
    var onClose: (() -> Void)?

    /// The two colours the Auto vibe lands on for this image — sampled once and
    /// reused, so we don't re-scan pixels on every keystroke.
    private let autoColors: (Color, Color)

    /// Whether the save-button glow + filename shimmer plays on save (Settings).
    let saveDelightEnabled: Bool

    init(input: EditorInput, store: LibraryStore, recents: RecentDestinationsStore, vibes: VibeStore, settings: SettingsStore) {
        self.original = input.image
        self.previewSource = input.image.downscaled(maxPixel: 1100)
        self.thumbSource = input.image.downscaled(maxPixel: 180)
        self.input = input
        self.store = store
        self.recents = recents
        self.vibes = vibes
        self.name = input.suggestedName
        self.saveDelightEnabled = settings.saveDelight
        let sampled = ColorSampler.dominantColors(input.image, count: 2)
        self.autoColors = (sampled.first ?? .blue, sampled.count > 1 ? sampled[1] : .purple)
        var draft = BeautifyDraft.makeDefault(from: input.image)
        // Restore the sticky output ratio from last session.
        if let saved = UserDefaults.standard.string(forKey: Self.ratioKey),
           let option = AspectRatioOption(rawValue: saved) {
            draft.ratioOption = option
        }
        // A tall full-page catch shouldn't get squeezed into a 16:9 or square —
        // it always opens at its own shape so nothing's cropped off.
        if input.captureMode == CaptureMode.fullPage.rawValue {
            draft.ratioOption = .original
        }
        // Honour the default vibe from Settings, if one is set, so Beautified
        // catches open already dressed in your house style.
        if let vibeID = settings.defaultVibeID,
           let vibe = vibes.all.first(where: { $0.id == vibeID }) {
            let (c1, c2, angle) = vibe.resolvedColors(for: input.image)
            draft.backgroundKind = .gradient
            draft.color1 = c1
            draft.color2 = c2
            draft.angle = angle
        }
        self.draft = draft
        rerender()
    }

    /// Remember the chosen ratio for next session. Call when it changes.
    func persistRatio() {
        UserDefaults.standard.set(draft.ratioOption.rawValue, forKey: Self.ratioKey)
    }

    // MARK: - Splitting tall captures

    /// The captured image's own width ÷ height (chrome aside — close enough to
    /// decide whether splitting is on offer).
    private var contentAspect: Double {
        let s = original.size
        return s.height > 0 ? Double(s.width / s.height) : 1
    }

    /// Whether the "Split into…" option should show: the shot is clearly tall,
    /// or taller than the current output ratio would comfortably hold.
    var canSplit: Bool {
        if contentAspect < 0.9 { return true }
        if let ratio = draft.resolvedAspectRatio, contentAspect < ratio * 0.9 { return true }
        return false
    }

    func setSplit(_ count: Int) {
        splitCount = max(1, count)
        splitFractions = Splitter.evenFractions(splitCount)
    }

    func clearSplit() {
        splitCount = 1
        splitFractions = []
    }

    /// Move one cut line, keeping it between its neighbours.
    func updateFraction(_ index: Int, to value: Double) {
        guard splitFractions.indices.contains(index) else { return }
        let lower = index > 0 ? splitFractions[index - 1] + 0.02 : 0.02
        let upper = index < splitFractions.count - 1 ? splitFractions[index + 1] - 0.02 : 0.98
        splitFractions[index] = min(max(value, lower), upper)
    }

    /// Repaint the preview from the current draft. Called on every change.
    func rerender() {
        rendered = BeautifyRenderer.render(previewSource, style: draft.toStyle())
    }

    // MARK: - Vibes

    /// Apply a vibe: swap the backdrop to its gradient (Auto re-samples the
    /// image), leaving padding, shadow, and corners untouched.
    func apply(_ vibe: Vibe) {
        let (c1, c2, angle) = vibe.color1 != nil
            ? (vibe.color1!, vibe.color2!, vibe.angle)
            : (autoColors.0, autoColors.1, 135.0)
        draft.backgroundKind = .gradient
        draft.color1 = c1
        draft.color2 = c2
        draft.angle = angle
        rerender()
    }

    /// A small preview of the current screenshot dressed in `vibe` — what the
    /// strip thumbnails show, so you compare real output, not swatches. Keeps the
    /// current padding/shadow/corners and only swaps the backdrop.
    func thumbnail(for vibe: Vibe) -> NSImage? {
        var d = draft
        let (c1, c2, angle) = vibe.color1 != nil
            ? (vibe.color1!, vibe.color2!, vibe.angle)
            : (autoColors.0, autoColors.1, 135.0)
        d.backgroundKind = .gradient
        d.color1 = c1; d.color2 = c2; d.angle = angle
        return BeautifyRenderer.render(thumbSource, style: d.toStyle())
    }

    /// Which vibe (if any) the current backdrop exactly matches — drives the
    /// active highlight. A manual colour tweak makes this nil.
    var activeVibeID: String? {
        guard draft.backgroundKind == .gradient else { return nil }
        for vibe in vibes.all {
            let (c1, c2, angle) = vibe.color1 != nil
                ? (vibe.color1!, vibe.color2!, vibe.angle)
                : (autoColors.0, autoColors.1, 135.0)
            if draft.color1 == c1, draft.color2 == c2, draft.angle == angle {
                return vibe.id
            }
        }
        return nil
    }

    /// Save the current backdrop as a new custom vibe.
    func saveCurrentAsVibe(named name: String) {
        vibes.add(name: name, color1: draft.color1, color2: draft.color2, angle: draft.angle)
    }

    /// True when the backdrop is transparent — the view shows a checkerboard
    /// behind the canvas so see-through areas read clearly.
    var showsTransparencyCheckerboard: Bool {
        draft.backgroundKind == .transparent
    }

    // MARK: - Saving

    /// Render the full-resolution styled image and file it. When split is on,
    /// saves one PNG per panel as `name_01.png`, `name_02.png`, … New library
    /// entries — the original stays untouched.
    func commit(name: String, tags: [String], choice: SaveChoice) -> Bool {
        let outputs = renderOutputs(named: name)
        guard !outputs.isEmpty else {
            NSLog("Lightscreen: beautify render produced no data")
            return false
        }

        do {
            let folder: URL?
            switch choice {
            case .library: folder = nil
            case .folder(let f): folder = f
            case .other:
                guard let picked = pickFolder() else { return false } // cancelled: keep sheet open
                folder = picked
            }

            for output in outputs {
                if let folder {
                    try store.saveToFolder(data: output.data, folder: folder, name: output.name, tags: tags)
                } else {
                    try store.saveToLibrary(
                        data: output.data, name: output.name, tags: tags,
                        captureMode: input.captureMode,
                        outputMode: OutputMode.beautified.rawValue,
                        sourceAppBundleID: input.sourceAppBundleID,
                        capturedAt: input.capturedAt
                    )
                }
            }
            if let folder { recents.remember(folder) }
            onSaved?()
            return true
        } catch {
            NSLog("Lightscreen: beautified save failed — \(error.localizedDescription)")
            return false
        }
    }

    /// The finished image(s) as named PNGs: one when whole, several when split.
    private func renderOutputs(named name: String) -> [(name: String, data: Data)] {
        let style = draft.toStyle()
        if splitCount > 1, let full = BeautifyRenderer.renderCGImage(original, style: style) {
            let panels = Splitter.split(full, atFractions: splitFractions)
            return panels.enumerated().compactMap { index, panel in
                guard let data = NSBitmapImageRep(cgImage: panel).representation(using: .png, properties: [:]) else { return nil }
                return (String(format: "%@_%02d", name, index + 1), data)
            }
        }
        if let data = BeautifyRenderer.pngData(original, style: style) {
            return [(name, data)]
        }
        return []
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
    private let vibes: VibeStore
    private let settings: SettingsStore
    private var window: NSWindow?
    private var model: EditorModel?

    /// Set by the app: called after a save so the library window can refresh.
    var onLibraryChanged: (() -> Void)?

    init(store: LibraryStore, recents: RecentDestinationsStore, vibes: VibeStore, settings: SettingsStore) {
        self.store = store
        self.recents = recents
        self.vibes = vibes
        self.settings = settings
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
        let model = EditorModel(input: input, store: store, recents: recents, vibes: vibes, settings: settings)
        model.onClose = { [weak self] in self?.close() }
        model.onSaved = { [weak self] in
            self?.onLibraryChanged?()
            self?.close()
        }
        self.model = model

        let win = window ?? makeWindow()
        win.contentView = NSHostingView(rootView: AccentRoot(settings: settings) { EditorView(model: model, vibes: vibes) })
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
