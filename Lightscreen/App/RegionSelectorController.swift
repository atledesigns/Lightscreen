import AppKit

/// The drag-to-select overlay. Puts one dimmed, crosshair window on *every*
/// display (a single window spanning them all gets clamped by macOS and only
/// covers part of an extended desktop). You draw a rectangle that can cross
/// monitors; release captures it, Esc cancels.
@MainActor
final class RegionSelectorController {
    private var windows: [NSWindow] = []
    private var views: [RegionSelectionView] = []
    private var onComplete: ((CGRect?) -> Void)?

    // The drag, tracked in true global screen coordinates so it's identical
    // across every monitor regardless of scale or arrangement.
    private var globalStart: CGPoint?
    private var globalSelection: CGRect?

    /// Opens the overlay. `completion` fires with the chosen rectangle in global
    /// screen coordinates, or `nil` if the user cancelled.
    func begin(_ completion: @escaping (CGRect?) -> Void) {
        guard windows.isEmpty else { return }
        onComplete = completion

        NSApp.activate()
        for screen in NSScreen.screens {
            let panel = SelectorWindow(
                contentRect: screen.frame,
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
            panel.setFrame(screen.frame, display: false)

            let view = RegionSelectionView(frame: NSRect(origin: .zero, size: screen.frame.size))
            view.screenFrame = screen.frame
            view.controller = self
            panel.contentView = view

            panel.orderFrontRegardless()
            panel.makeFirstResponder(view)
            windows.append(panel)
            views.append(view)
        }
        // One window holds keyboard focus so Esc is heard; clicking any screen
        // hands focus to that screen's window anyway.
        windows.first?.makeKey()
    }

    // MARK: - Called by the per-screen views as the drag happens

    func dragBegan(at global: CGPoint) {
        globalStart = global
        globalSelection = nil
        refresh()
    }

    func dragMoved(to global: CGPoint) {
        guard let start = globalStart else { return }
        globalSelection = rect(from: start, to: global)
        refresh()
    }

    func dragEnded() {
        guard let selection = globalSelection, selection.width >= 3, selection.height >= 3 else {
            finish(nil)
            return
        }
        NSLog("Lightscreen: selection (global) = \(selection.debugDescription)")
        finish(selection)
    }

    func cancel() {
        finish(nil)
    }

    // MARK: - Internals

    private func refresh() {
        for view in views {
            view.currentSelection = globalSelection
            view.needsDisplay = true
        }
    }

    private func finish(_ globalRect: CGRect?) {
        // Drop every overlay before reporting back, so none appear in the shot.
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        views.removeAll()
        globalStart = nil
        globalSelection = nil
        let completion = onComplete
        onComplete = nil
        completion?(globalRect)
    }

    private func rect(from a: CGPoint, to b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }
}

/// A borderless window normally can't take keystrokes; flip that on so Esc lands.
private final class SelectorWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// One screen's worth of the overlay: dims its display, shows the crosshair,
/// and draws whatever part of the selection falls on this screen.
private final class RegionSelectionView: NSView {
    weak var controller: RegionSelectorController?
    /// This view's display, in global screen coordinates. Its bottom-left is
    /// the view's local origin (0,0).
    var screenFrame: CGRect = .zero
    /// The whole selection in global coordinates (may span several screens).
    var currentSelection: CGRect?

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.22).setFill()
        bounds.fill()

        guard let global = currentSelection, global.width > 0, global.height > 0,
              global.intersects(screenFrame) else { return }

        // Selection translated into this screen's local coordinates.
        let local = CGRect(
            x: global.minX - screenFrame.minX,
            y: global.minY - screenFrame.minY,
            width: global.width,
            height: global.height
        )

        // Clear only the part that lands on this screen.
        let visible = local.intersection(bounds)
        NSColor.clear.setFill()
        visible.fill(using: .copy)

        let border = NSBezierPath(rect: local)
        border.lineWidth = 1
        NSColor.controlAccentColor.setStroke()
        border.stroke()

        drawDimensions(for: global, local: local)
    }

    private func drawDimensions(for global: CGRect, local: CGRect) {
        // Only the screen holding the selection's top-left draws the readout,
        // so it appears once even when the box straddles two monitors.
        guard screenFrame.contains(CGPoint(x: global.minX, y: global.maxY)) else { return }

        let label = "\(Int(global.width.rounded())) × \(Int(global.height.rounded()))"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let textSize = (label as NSString).size(withAttributes: attrs)
        let padX: CGFloat = 8
        let padY: CGFloat = 4
        let pillW = textSize.width + padX * 2
        let pillH = textSize.height + padY * 2

        var pillY = local.maxY + 6
        if pillY + pillH > bounds.maxY { pillY = local.minY - pillH - 6 }
        let pillX = min(max(local.minX, bounds.minX), bounds.maxX - pillW)
        let pill = NSRect(x: pillX, y: pillY, width: pillW, height: pillH)

        NSColor.black.withAlphaComponent(0.72).setFill()
        NSBezierPath(roundedRect: pill, xRadius: 6, yRadius: 6).fill()
        (label as NSString).draw(
            at: NSPoint(x: pill.minX + padX, y: pill.minY + padY),
            withAttributes: attrs
        )
    }

    override func mouseDown(with event: NSEvent) {
        controller?.dragBegan(at: NSEvent.mouseLocation)
    }

    override func mouseDragged(with event: NSEvent) {
        controller?.dragMoved(to: NSEvent.mouseLocation)
    }

    override func mouseUp(with event: NSEvent) {
        controller?.dragEnded()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            controller?.cancel()
        } else {
            super.keyDown(with: event)
        }
    }
}
