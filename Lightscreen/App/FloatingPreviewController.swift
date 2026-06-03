import AppKit
import SwiftUI

/// Owns the post-capture floating preview: shows it bottom-right, runs the
/// 5-second "ignore = auto-save" timer, hands off drags, and drives the save
/// popover. One capture in flight at a time.
@MainActor
final class FloatingPreviewController: NSObject, NSPopoverDelegate {
    private let library: LibraryStore
    private let recents: RecentDestinationsStore

    private var window: NSWindow?
    private var popover: NSPopover?
    private var current: PendingCapture?
    private var dismissTimer: DispatchWorkItem?
    /// True once the shot has been dealt with (saved, dragged, or discarded),
    /// so close/teardown paths don't double up.
    private var consumed = false

    /// Transparent breathing room around the card inside its window — leaves
    /// space for the shadow and gives the popover a card edge to point at.
    private let margin: CGFloat = 24

    init(library: LibraryStore, recents: RecentDestinationsStore) {
        self.library = library
        self.recents = recents
    }

    // MARK: - Showing a capture

    func present(_ pending: PendingCapture) {
        // A new shot supersedes any preview still on screen.
        teardown()

        current = pending
        consumed = false

        let screen = NSScreen.screenWithPointer ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        // Window hugs the card (card size + a margin all round), so the popover
        // can anchor to the card itself rather than floating off the window edge.
        let card = cardSize(for: pending.image)
        let size = NSSize(width: card.width + margin * 2, height: card.height + margin * 2)
        let origin = NSPoint(x: visible.maxX - size.width, y: visible.minY)
        let frame = NSRect(origin: origin, size: size)

        let panel = PreviewWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isReleasedWhenClosed = false

        let root = FloatingPreviewView(
            image: pending.image,
            onTap: { [weak self] in self?.showSavePopover() },
            makeProvider: { [weak self] in self?.makeProvider() ?? NSItemProvider() },
            onDragStart: { [weak self] in self?.draggedOut() },
            onHover: { [weak self] inside in self?.hoverChanged(inside) }
        )
        let hosting = NSHostingView(rootView: root)
        hosting.frame = panel.contentLayoutRect
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting

        panel.orderFrontRegardless()
        window = panel

        startTimer()
    }

    // MARK: - The three outcomes

    /// Ignored (timer elapsed): quietly file it in the library, Raw-style.
    private func autoSaveAndDismiss() {
        if !consumed, let p = current {
            consumed = true
            try? library.save(
                pngData: p.pngData,
                captureMode: p.captureMode.rawValue,
                outputMode: p.outputMode.rawValue,
                sourceAppBundleID: p.sourceAppBundleID,
                capturedAt: p.capturedAt
            )
        }
        teardown()
    }

    /// Dragged out to another app: it's left the building, no library copy.
    private func draggedOut() {
        consumed = true
        cancelTimer()
        // Let the drag session take hold before the window vanishes.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.teardown()
        }
    }

    private func makeProvider() -> NSItemProvider {
        guard let p = current else { return NSItemProvider() }
        return NSItemProvider(contentsOf: p.tempURL) ?? NSItemProvider()
    }

    // MARK: - Save popover

    private func showSavePopover() {
        guard let window, let p = current, popover == nil else { return }
        cancelTimer() // engaged — stop the auto-save countdown

        let pop = NSPopover()
        pop.behavior = .transient
        pop.delegate = self
        let view = SavePopoverView(
            initialName: (p.suggestedName as NSString).deletingPathExtension,
            recents: recents.recents(),
            onSave: { [weak self] name, tags, choice in self?.commitSave(name: name, tags: tags, choice: choice) },
            onCancel: { [weak self] in self?.popover?.performClose(nil) }
        )
        pop.contentViewController = NSHostingController(rootView: view)
        popover = pop

        if let content = window.contentView {
            // Point at the card (content inset by the margin), not the window edge,
            // so the popover sits right against the thumbnail. The hosting view is
            // flipped (top-left origin), so the card's TOP edge is .minY — using
            // .maxY would anchor the bottom and shove the popover a card-height away.
            let cardRect = content.bounds.insetBy(dx: margin, dy: margin)
            pop.show(relativeTo: cardRect, of: content, preferredEdge: .minY)
        }
    }

    /// The card's on-screen size for a given image: the thumbnail fit into its
    /// max box, plus the 10pt padding inside the glass on each side.
    private func cardSize(for image: NSImage) -> NSSize {
        let maxW: CGFloat = 220, maxH: CGFloat = 150
        let s = image.size
        guard s.width > 0, s.height > 0 else {
            return NSSize(width: maxW + 20, height: maxH + 20)
        }
        let scale = min(maxW / s.width, maxH / s.height)
        return NSSize(width: s.width * scale + 20, height: s.height * scale + 20)
    }

    private func commitSave(name: String, tags: [String], choice: SaveChoice) {
        guard let p = current else { return }
        do {
            switch choice {
            case .library:
                try library.saveToLibrary(
                    data: p.pngData, name: name, tags: tags,
                    captureMode: p.captureMode.rawValue,
                    outputMode: p.outputMode.rawValue,
                    sourceAppBundleID: p.sourceAppBundleID,
                    capturedAt: p.capturedAt
                )
            case .folder(let folder):
                try library.saveToFolder(data: p.pngData, folder: folder, name: name, tags: tags)
                recents.remember(folder)
            case .other:
                guard let folder = pickFolder() else { return } // panel cancelled: keep popover open
                try library.saveToFolder(data: p.pngData, folder: folder, name: name, tags: tags)
                recents.remember(folder)
            }
            consumed = true
        } catch {
            NSLog("Lightscreen: save failed — \(error.localizedDescription)")
        }
        popover?.performClose(nil)
        teardown()
    }

    private func pickFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Save Here"
        return panel.runModal() == .OK ? panel.url : nil
    }

    /// Popover closed by Esc, Cancel, or an outside click without an explicit
    /// save: keep the shot anyway, filed in the library as normal — backing out
    /// of the dialog should never lose a capture.
    func popoverDidClose(_ notification: Notification) {
        popover = nil
        if !consumed { autoSaveAndDismiss() }
    }

    // MARK: - Timer + hover

    private func startTimer() {
        cancelTimer()
        let work = DispatchWorkItem { [weak self] in self?.autoSaveAndDismiss() }
        dismissTimer = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: work)
    }

    private func cancelTimer() {
        dismissTimer?.cancel()
        dismissTimer = nil
    }

    private func hoverChanged(_ inside: Bool) {
        guard popover == nil, !consumed else { return }
        if inside { cancelTimer() } else { startTimer() }
    }

    // MARK: - Teardown

    private func teardown() {
        cancelTimer()
        popover?.performClose(nil)
        popover = nil
        window?.orderOut(nil)
        window = nil
        current = nil
    }
}

/// A borderless window that can still take a click and host the save popover.
private final class PreviewWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

private extension NSScreen {
    static var screenWithPointer: NSScreen? {
        let location = NSEvent.mouseLocation
        return screens.first { $0.frame.contains(location) }
    }
}
