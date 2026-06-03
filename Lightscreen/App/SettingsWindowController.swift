import AppKit
import SwiftUI

/// Owns the single Settings window. Reopening just brings the existing one
/// forward, so we never stack duplicates.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let settings: SettingsStore
    private let outputMode: OutputModeStore
    private let vibes: VibeStore
    private let store: LibraryStore
    private var window: NSWindow?

    /// Set by the app: the "Review now…" button opens the library in review mode.
    var onReviewNow: (() -> Void)?

    init(settings: SettingsStore, outputMode: OutputModeStore, vibes: VibeStore, store: LibraryStore) {
        self.settings = settings
        self.outputMode = outputMode
        self.vibes = vibes
        self.store = store
    }

    func show() {
        if let window {
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
            return
        }

        let root = SettingsView(
            settings: settings,
            outputMode: outputMode,
            vibes: vibes,
            store: store,
            onReviewNow: { [weak self] in self?.onReviewNow?() }
        )

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 430),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        win.title = "Settings"
        win.isReleasedWhenClosed = false
        win.delegate = self
        win.center()
        win.contentView = NSHostingView(rootView: root)
        window = win

        NSApp.activate()
        win.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}
