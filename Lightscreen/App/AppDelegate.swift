import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?

    // Stage 4: the dropdown under the menu bar icon, and the stub windows.
    private var menuPopover: NSPopover?
    private var placeholders: [String: NSWindow] = [:]

    // The session's sticky Beautified/Raw choice. Shared so every surface agrees.
    private let outputMode = OutputModeStore()
    private let hotkey = HotkeyListener()
    private lazy var picker = PickerWindowController(outputMode: outputMode)

    // Stage 2: real capture + storage.
    private let library = LibraryStore()
    private let captureEngine = CaptureEngine()
    private let regionSelector = RegionSelectorController()

    // Stage 6: hover-a-window-to-capture overlay.
    private let windowHighlighter = WindowHighlighterController()

    // Stage 3: post-capture floating preview (drag out / click to save / ignore).
    private let recents = RecentDestinationsStore()
    private lazy var preview = FloatingPreviewController(library: library, recents: recents)

    // Stage 5: the real Library window (date-grouped grid of every shot).
    private lazy var libraryWindow = LibraryWindowController(store: library)

    // Stage 7: the Beautify editor (gradient backdrop, padding, shadow, corners).
    private lazy var editor: EditorWindowController = {
        let controller = EditorWindowController(store: library, recents: recents)
        controller.onLibraryChanged = { [weak self] in self?.libraryWindow.refresh() }
        return controller
    }()

    // Whatever app was frontmost the instant ⌘⇧7 fired — recorded before we
    // steal focus, so we can credit the right source app on the saved shot.
    private var sourceAppBundleID: String?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()

        // ⌘⇧7 anywhere on the Mac opens (or closes) the capture picker.
        hotkey.onTrigger = { [weak self] in
            guard let self else { return }
            self.sourceAppBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            self.picker.toggle()
        }
        hotkey.start()

        picker.onCapture = { [weak self] mode in self?.handleCapture(mode) }

        // Double-click / "Open in editor" in the library opens the Beautify editor.
        libraryWindow.onOpenEditor = { [weak self] capture in self?.openInEditor(capture) }
    }

    /// Sends a fresh capture either to the editor (Beautified) or the floating
    /// preview (Raw). One door, so every capture mode behaves the same.
    private func route(_ pending: PendingCapture) {
        if pending.outputMode == .beautified {
            editor.open(from: pending)
        } else {
            preview.present(pending)
        }
    }

    /// Opens a previously saved shot in the editor with default beautification.
    private func openInEditor(_ capture: Capture) {
        let url = library.fileURL(for: capture)
        guard let image = NSImage(contentsOf: url) else {
            NSLog("Lightscreen: could not load \(url.lastPathComponent) for editing")
            return
        }
        editor.open(EditorInput(
            image: image,
            suggestedName: (capture.filename as NSString).deletingPathExtension,
            captureMode: capture.captureMode,
            sourceAppBundleID: capture.sourceAppBundleID,
            capturedAt: capture.capturedAt
        ))
    }

    /// Routes a chosen capture mode. Region is live in Stage 2; the others land
    /// in later stages.
    private func handleCapture(_ mode: CaptureMode) {
        switch mode {
        case .region:
            regionSelector.begin { [weak self] globalRect in
                guard let self, let rect = globalRect else { return } // nil = cancelled
                Task { await self.captureAndSave(rect: rect) }
            }
        case .window:
            windowHighlighter.begin { [weak self] window in
                guard let self, let window else { return } // nil = Esc / empty desktop
                Task { await self.captureWindowAndShow(window) }
            }
        case .fullPage:
            NSLog("Lightscreen: \(mode.label) capture arrives in a later stage.")
        }
    }

    private func captureWindowAndShow(_ window: OnScreenWindow) async {
        do {
            // A beat so the overlay is fully gone before we grab pixels.
            try await Task.sleep(for: .milliseconds(60))
            let png = try await captureEngine.captureWindow(windowID: window.id)

            // Credit the window's own app, not whatever was front at trigger time.
            let bundleID = NSRunningApplication(processIdentifier: window.ownerPID)?.bundleIdentifier

            let now = Date()
            let suggested = LibraryStore.suggestedFilename(for: now)
            let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(suggested)
            try? png.write(to: tempURL)

            let pending = PendingCapture(
                pngData: png,
                image: NSImage(data: png) ?? NSImage(),
                captureMode: .window,
                outputMode: outputMode.mode,
                sourceAppBundleID: bundleID,
                capturedAt: now,
                suggestedName: suggested,
                tempURL: tempURL
            )
            route(pending)
        } catch {
            NSLog("Lightscreen: window capture failed — \(error.localizedDescription)")
        }
    }

    private func captureAndSave(rect: CGRect) async {
        do {
            // A beat so the dimmed overlay is fully gone before we grab pixels.
            try await Task.sleep(for: .milliseconds(60))
            let png = try await captureEngine.captureRegion(rect)

            // Stash a throwaway copy so the preview can be dragged into other apps.
            let now = Date()
            let suggested = LibraryStore.suggestedFilename(for: now)
            let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(suggested)
            try? png.write(to: tempURL)

            let pending = PendingCapture(
                pngData: png,
                image: NSImage(data: png) ?? NSImage(),
                captureMode: .region,
                outputMode: outputMode.mode,
                sourceAppBundleID: sourceAppBundleID,
                capturedAt: now,
                suggestedName: suggested,
                tempURL: tempURL
            )
            // Beautified opens the editor; Raw drops into the floating preview
            // (ignore = auto-save, drag = ship it, click = save with options).
            route(pending)
        } catch {
            NSLog("Lightscreen: capture failed — \(error.localizedDescription)")
        }
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            let image = NSImage(systemSymbolName: "camera.fill", accessibilityDescription: "Lightscreen")
            image?.isTemplate = true
            button.image = image
            button.image?.size = NSSize(width: 18, height: 18)
            button.action = #selector(toggleMenu)
            button.target = self
        }
        statusItem = item
    }

    // MARK: - Menu bar dropdown

    @objc private func toggleMenu() {
        guard let button = statusItem?.button else { return }
        let popover = menuPopover ?? makeMenuPopover()

        if popover.isShown {
            popover.performClose(nil)
        } else {
            // Remember who was in front so a menu-triggered shot credits them too.
            sourceAppBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            NSApp.activate()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private func makeMenuPopover() -> NSPopover {
        let popover = NSPopover()
        popover.behavior = .transient
        let root = MenuBarView(
            onCapture: { [weak self] mode in self?.menuCapture(mode) },
            onShowLibrary: { [weak self] in self?.showLibrary() },
            onSettings: { [weak self] in self?.openPlaceholder(id: "settings", title: "Settings", message: "Settings will live here.\n(Coming in a later stage.)") },
            onQuit: { NSApp.terminate(nil) }
        )
        let host = NSHostingController(rootView: root)
        host.sizingOptions = [.preferredContentSize]
        popover.contentViewController = host
        menuPopover = popover
        return popover
    }

    private func menuCapture(_ mode: CaptureMode) {
        menuPopover?.performClose(nil)
        handleCapture(mode)
    }

    /// Opens (or re-focuses) the real Library window.
    private func showLibrary() {
        menuPopover?.performClose(nil)
        libraryWindow.show()
    }

    /// Opens (or re-focuses) a simple stand-in window for features not yet built.
    private func openPlaceholder(id: String, title: String, message: String) {
        menuPopover?.performClose(nil)
        if let existing = placeholders[id] {
            NSApp.activate()
            existing.makeKeyAndOrderFront(nil)
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 320),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.isReleasedWhenClosed = false
        window.center()
        window.contentView = NSHostingView(rootView: PlaceholderView(message: message))
        placeholders[id] = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }
}
