import AppKit
import SwiftUI

/// Where a bulk "Move to…" should send the selected catches.
enum MoveTarget: Hashable {
    case folder(URL)
    case other
}

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

    /// Which catches are selected right now (by id). Empty = normal browsing;
    /// non-empty lights up the bulk action bar.
    @Published var selection: Set<Int64> = []
    /// The 60-day "want to release some?" banner across the top.
    @Published var showReviewBanner = false

    /// Anchor for shift-click range selection — the last cell tapped plainly.
    private var selectionAnchor: Int64?

    let store: LibraryStore
    let recents: RecentDestinationsStore
    let thumbnails = ThumbnailCache()

    /// The 60-day tidy-up nudge. Optional so the model still works in previews.
    var reviewScheduler: ReviewScheduler?

    /// Set by the app to open a past shot in the Beautify editor. Until wired,
    /// the action stays a friendly no-op.
    var onOpenEditor: ((Capture) -> Void)?

    init(store: LibraryStore, recents: RecentDestinationsStore) {
        self.store = store
        self.recents = recents
    }

    /// Pull the current library from disk. Cheap, so we call it on open and
    /// after any change.
    func reload() {
        captures = store.fetchAll() // already newest-first
        // Drop any selected ids that no longer exist (deleted/moved).
        let live = Set(captures.map(\.id))
        selection.formIntersection(live)
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

    // MARK: - Multi-select

    /// The catches in the exact order they're laid out (groups flattened), so
    /// shift-range and select-all match what the eye sees.
    var visibleCaptures: [Capture] { groups.flatMap(\.captures) }

    var selectionActive: Bool { !selection.isEmpty }
    var selectedCount: Int { selection.count }

    /// The selected catches, in display order.
    var selectedCaptures: [Capture] { visibleCaptures.filter { selection.contains($0.id) } }

    func isSelected(_ capture: Capture) -> Bool { selection.contains(capture.id) }

    /// A click on a cell, with whatever modifier keys are down right now:
    /// - ⌘ toggles that one in/out of the selection
    /// - ⇧ extends a range from the last plain pick
    /// - no modifier, with a selection active, clears it (back to browsing)
    /// - no modifier, nothing selected, does nothing (double-click opens it)
    func handleTap(on capture: Capture) {
        let flags = NSEvent.modifierFlags
        if flags.contains(.command) {
            toggle(capture)
        } else if flags.contains(.shift) {
            selectRange(to: capture)
        } else if selectionActive {
            clearSelection()
        }
    }

    func toggle(_ capture: Capture) {
        if selection.contains(capture.id) {
            selection.remove(capture.id)
        } else {
            selection.insert(capture.id)
            selectionAnchor = capture.id
        }
    }

    /// Select everything between the anchor and `capture`, inclusive.
    func selectRange(to capture: Capture) {
        let ordered = visibleCaptures.map(\.id)
        guard let anchor = selectionAnchor ?? ordered.first,
              let a = ordered.firstIndex(of: anchor),
              let b = ordered.firstIndex(of: capture.id) else {
            toggle(capture)
            return
        }
        let range = a <= b ? a...b : b...a
        selection.formUnion(ordered[range])
    }

    func selectAll() {
        selection = Set(visibleCaptures.map(\.id))
    }

    func clearSelection() {
        selection.removeAll()
        selectionAnchor = nil
    }

    // MARK: - Bulk actions

    /// Throw away every selected catch (after the caller has confirmed).
    func deleteSelected() {
        for capture in selectedCaptures {
            do {
                try store.deleteWithFile(capture)
                thumbnails.forget(key: thumbnailKey(for: capture))
            } catch {
                NSLog("Lightscreen: bulk delete failed for \(capture.filename) — \(error.localizedDescription)")
            }
        }
        clearSelection()
        reload()
    }

    /// Move every selected catch out to a folder, the way single Move-to does.
    func moveSelected(to target: MoveTarget) {
        let folder: URL
        switch target {
        case .folder(let url):
            folder = url
        case .other:
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.allowsMultipleSelection = false
            panel.prompt = "Move Here"
            guard panel.runModal() == .OK, let picked = panel.url else { return }
            folder = picked
        }
        for capture in selectedCaptures {
            do {
                _ = try store.moveOut(capture, to: folder)
                thumbnails.forget(key: thumbnailKey(for: capture))
            } catch {
                NSLog("Lightscreen: bulk move failed for \(capture.filename) — \(error.localizedDescription)")
            }
        }
        recents.remember(folder)
        clearSelection()
        reload()
    }

    // MARK: - 60-day review

    /// Refresh the banner's visibility from the scheduler. Call on window open.
    func refreshReviewState() {
        showReviewBanner = reviewScheduler?.isReviewDue ?? false
    }

    /// "Release some" — select everything, ready for a batch delete, and tuck
    /// the banner away (the clock resets so it won't nag again for 60 days).
    func enterReviewMode() {
        selectAll()
        reviewScheduler?.markPromptedNow()
        showReviewBanner = false
    }

    /// Banner close button — quiet it and reset the 60-day clock.
    func dismissReviewBanner() {
        reviewScheduler?.markPromptedNow()
        showReviewBanner = false
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

    /// Open a past shot in the Beautify editor (double-click / "Open in editor").
    func openInEditor(_ capture: Capture) {
        if let onOpenEditor {
            onOpenEditor(capture)
        } else {
            NSLog("Lightscreen: editor handler not wired.")
        }
    }
}

/// Owns the single Library window and keeps it in sync. Reopening just brings
/// the existing window forward and refreshes it.
@MainActor
final class LibraryWindowController: NSObject, NSWindowDelegate {
    private let model: LibraryModel
    private let settings: SettingsStore
    private var window: NSWindow?

    /// Set by the app to route "Open in editor" / double-click to the editor.
    var onOpenEditor: ((Capture) -> Void)? {
        didSet { model.onOpenEditor = onOpenEditor }
    }

    init(store: LibraryStore, recents: RecentDestinationsStore, settings: SettingsStore, reviewScheduler: ReviewScheduler? = nil) {
        self.model = LibraryModel(store: store, recents: recents)
        self.model.reviewScheduler = reviewScheduler
        self.settings = settings
    }

    /// Re-read the library (e.g. after the editor saved a new shot).
    func refresh() {
        model.reload()
    }

    /// Open the window straight into review mode: everything selected, ready for
    /// a batch delete. Used when the user taps the 60-day notification.
    func showInReviewMode() {
        show()
        model.enterReviewMode()
    }

    func show() {
        model.reload()
        model.refreshReviewState()
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
        win.contentView = NSHostingView(rootView: AccentRoot(settings: settings) { LibraryView(model: model) })
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
