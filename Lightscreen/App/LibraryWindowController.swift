import AppKit
import SwiftUI

/// How the grid is ordered, set from the toolbar's sort menu.
enum LibrarySort: String, CaseIterable, Identifiable {
    case newest = "Newest first"
    case oldest = "Oldest first"
    var id: String { rawValue }
}

/// View modes the toolbar offers. Only grid is real in v1; list is a visible
/// placeholder so the control feels complete and the wiring is ready for later.
enum LibraryViewMode: String, CaseIterable, Identifiable {
    case grid = "Grid"
    case list = "List"
    var id: String { rawValue }
    var symbol: String { self == .grid ? "square.grid.2x2" : "list.bullet" }
}

/// The library window's brain: holds the shots, the search text, and the sort
/// choice, and runs the quick actions (reveal, move, delete) against the store.
/// Lives next to the window so the SwiftUI view can stay about layout.
@MainActor
final class LibraryModel: ObservableObject {
    @Published private(set) var captures: [Capture] = []
    @Published var searchText = ""
    @Published var sort: LibrarySort = .newest
    @Published var viewMode: LibraryViewMode = .grid

    let store: LibraryStore
    let thumbnails = ThumbnailCache()

    init(store: LibraryStore) {
        self.store = store
    }

    /// Pull the current library from disk. Cheap, so we call it on open and
    /// after any change.
    func reload() {
        captures = store.fetchAll() // already newest-first
    }

    // MARK: - Derived view of the list

    /// Search + sort applied, then folded back into ordered date groups with
    /// sticky-header order (Today → Earlier). Empty buckets drop out.
    var groups: [(group: DateGroup, captures: [Capture])] {
        let needle = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        var list = captures
        if !needle.isEmpty {
            list = list.filter { $0.filename.lowercased().contains(needle) }
        }
        list.sort { sort == .newest ? $0.capturedAt > $1.capturedAt : $0.capturedAt < $1.capturedAt }

        let now = Date()
        var buckets: [DateGroup: [Capture]] = [:]
        for capture in list {
            buckets[LibraryStore.group(for: capture.capturedAt, now: now), default: []].append(capture)
        }
        return DateGroup.allCases.compactMap { group in
            guard let captures = buckets[group], !captures.isEmpty else { return nil }
            return (group, captures)
        }
    }

    var isEmpty: Bool { captures.isEmpty }

    /// "12 catches · 4.6 MB total" for the bottom bar, from what's loaded.
    var statusLine: String {
        let count = captures.count
        let bytes = captures.reduce(Int64(0)) { $0 + $1.fileSizeBytes }
        let noun = count == 1 ? "catch" : "catches"
        let size = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
        return "\(count) \(noun) · \(size) total"
    }

    /// Greeting for the empty state, tuned to the time of day.
    var emptyStateGreeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<11:  return "Morning."
        case 11..<17: return "Afternoon."
        case 17..<22: return "Evening."
        default:      return "Late night."
        }
    }

    // MARK: - Per-shot actions

    func fileURL(for capture: Capture) -> URL { store.fileURL(for: capture) }

    /// Stable cache key that changes if the file is replaced.
    func thumbnailKey(for capture: Capture) -> String {
        "\(capture.relativePath)#\(capture.fileSizeBytes)"
    }

    func revealInFinder(_ capture: Capture) {
        NSWorkspace.shared.activateFileViewerSelecting([store.fileURL(for: capture)])
    }

    func delete(_ capture: Capture) {
        do {
            try store.deleteWithFile(capture)
            thumbnails.forget(key: thumbnailKey(for: capture))
            reload()
        } catch {
            NSLog("Lightscreen: delete failed — \(error.localizedDescription)")
        }
    }

    /// Ask for a destination folder, then move the shot there and out of the
    /// library. No-op if the picker is cancelled.
    func moveToFolder(_ capture: Capture) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Move Here"
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        do {
            _ = try store.moveOut(capture, to: folder)
            thumbnails.forget(key: thumbnailKey(for: capture))
            reload()
        } catch {
            NSLog("Lightscreen: move failed — \(error.localizedDescription)")
        }
    }

    /// Opening in the editor arrives in Stage 7; for now it's a friendly no-op.
    func openInEditor(_ capture: Capture) {
        NSLog("Lightscreen: in-app editor arrives in a later stage.")
    }
}

/// Owns the single Library window and keeps it in sync. Reopening just brings
/// the existing window forward and refreshes it.
@MainActor
final class LibraryWindowController: NSObject, NSWindowDelegate {
    private let model: LibraryModel
    private var window: NSWindow?

    init(store: LibraryStore) {
        self.model = LibraryModel(store: store)
    }

    func show() {
        model.reload()
        if let window {
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
            return
        }

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 920, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        win.title = "Library"
        win.titlebarAppearsTransparent = true
        win.isReleasedWhenClosed = false
        win.minSize = NSSize(width: 640, height: 460)
        win.delegate = self
        win.center()
        win.contentView = NSHostingView(rootView: LibraryView(model: model))
        window = win

        NSApp.activate()
        win.makeKeyAndOrderFront(nil)
    }

    /// New shots can land while the window sits in the background, so refresh
    /// whenever it comes back to the front.
    func windowDidBecomeKey(_ notification: Notification) {
        model.reload()
    }
}
