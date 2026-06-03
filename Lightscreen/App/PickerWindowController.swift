import AppKit
import SwiftUI

/// Owns the picker's floating window: shows it, centers it on the right screen,
/// and tears it down on Esc, on an outside click, or when a button is pressed.
@MainActor
final class PickerWindowController {
    private let outputMode: OutputModeStore
    private var window: NSWindow?
    private var escMonitor: Any?

    /// Called when the user picks a capture mode. The picker has already closed.
    var onCapture: ((CaptureMode) -> Void)?

    init(outputMode: OutputModeStore) {
        self.outputMode = outputMode
    }

    /// ⌘⇧7 calls this. Press once to open, again to close.
    func toggle() {
        if window == nil { show() } else { hide() }
    }

    func show() {
        guard window == nil else { return }

        // Cover the whole screen the pointer is currently on, so the picker
        // appears where you're looking and outside-clicks are caught everywhere.
        let screen = NSScreen.screenWithPointer ?? NSScreen.main
        let frame = screen?.frame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)

        let panel = KeyableWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isReleasedWhenClosed = false

        let root = PickerView(
            outputMode: outputMode,
            onCapture: { [weak self] mode in
                // Close first so the picker is never part of the capture, then act.
                self?.hide()
                self?.onCapture?(mode)
            },
            onDismiss: { [weak self] in self?.hide() }
        )

        let hosting = NSHostingView(rootView: root)
        hosting.frame = panel.contentLayoutRect
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting

        // Esc dismisses, reliably, regardless of which view has focus.
        escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // 53 = Escape
                self?.hide()
                return nil
            }
            return event
        }

        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        window = panel
    }

    func hide() {
        if let escMonitor {
            NSEvent.removeMonitor(escMonitor)
            self.escMonitor = nil
        }
        window?.orderOut(nil)
        window = nil
    }
}

/// A borderless window can't normally become "key" (the one receiving keystrokes).
/// We flip that on so Esc and clicks land on the picker instead of the app behind it.
private final class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private extension NSScreen {
    /// The screen the mouse pointer is on right now (so the picker follows your gaze).
    static var screenWithPointer: NSScreen? {
        let location = NSEvent.mouseLocation
        return screens.first { $0.frame.contains(location) }
    }
}
