import AppKit

/// The window-capture overlay. Lays one clear, click-through-proof window over
/// every display, swaps the cursor for a camera, and draws a soft holographic
/// outline around whatever window the pointer is over. Click captures it; Esc
/// quietly backs out (back to nothing — you re-press ⌘⇧7 to retry).
@MainActor
final class WindowHighlighterController {
    private var windows: [NSWindow] = []
    private var views: [WindowHighlightView] = []
    private var onComplete: ((OnScreenWindow?) -> Void)?

    /// The window the cursor is over right now, in AppKit global coordinates.
    private var hovered: OnScreenWindow?
    /// 0→1 progress of the foil-card sweep that plays when hover lands on a new
    /// window. Drives the moving band of light along the outline.
    private var sweepPhase: CGFloat = 0
    private var sweepTimer: Timer?
    private var sweepStart: CFTimeInterval = 0
    private let sweepDuration: CFTimeInterval = 0.25

    private let ownPID = ProcessInfo.processInfo.processIdentifier

    /// Opens the overlay. `completion` fires with the chosen window, or nil if
    /// the user pressed Esc / clicked empty desktop.
    func begin(_ completion: @escaping (OnScreenWindow?) -> Void) {
        guard windows.isEmpty else { return }
        onComplete = completion

        NSApp.activate()
        for screen in NSScreen.screens {
            let panel = HighlighterWindow(
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
            panel.acceptsMouseMovedEvents = true
            panel.ignoresMouseEvents = false
            panel.setFrame(screen.frame, display: false)

            let view = WindowHighlightView(frame: NSRect(origin: .zero, size: screen.frame.size))
            view.screenFrame = screen.frame
            view.controller = self
            panel.contentView = view

            panel.orderFrontRegardless()
            panel.makeFirstResponder(view)
            windows.append(panel)
            views.append(view)
        }
        windows.first?.makeKey()
    }

    // MARK: - Called by the per-screen views

    /// Pointer moved to a global AppKit point. Work out which window it's over
    /// and, if that changed, restart the sweep shimmer.
    func pointerMoved(to global: CGPoint) {
        let found = WindowEnumerator.frontmostWindow(atAppKitPoint: global, excludingPID: ownPID)
        if found?.id != hovered?.id {
            hovered = found
            if found != nil { startSweep() } else { stopSweep() }
            refresh()
        }
    }

    /// A click: capture the hovered window, or treat a click on bare desktop as
    /// a cancel.
    func click() {
        finish(hovered)
    }

    func cancel() {
        finish(nil)
    }

    // MARK: - Sweep animation

    private func startSweep() {
        sweepPhase = 0
        sweepStart = CACurrentMediaTime()
        sweepTimer?.invalidate()
        sweepTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self else { timer.invalidate(); return }
                let t = (CACurrentMediaTime() - self.sweepStart) / self.sweepDuration
                self.sweepPhase = min(1, CGFloat(t))
                self.refresh()
                if t >= 1 { timer.invalidate(); self.sweepTimer = nil }
            }
        }
    }

    private func stopSweep() {
        sweepTimer?.invalidate()
        sweepTimer = nil
    }

    // MARK: - Internals

    private func refresh() {
        for view in views {
            view.hovered = hovered
            view.sweepPhase = sweepPhase
            view.needsDisplay = true
        }
    }

    private func finish(_ window: OnScreenWindow?) {
        stopSweep()
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        views.removeAll()
        hovered = nil
        let completion = onComplete
        onComplete = nil
        completion?(window)
    }
}

/// Borderless windows can't normally take keystrokes; flip that on so Esc lands.
private final class HighlighterWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// One display's slice of the overlay: a transparent surface that reports
/// pointer moves and clicks, and draws the holographic outline for whatever
/// part of the hovered window falls on this screen.
private final class WindowHighlightView: NSView {
    weak var controller: WindowHighlighterController?
    var screenFrame: CGRect = .zero
    var hovered: OnScreenWindow?
    var sweepPhase: CGFloat = 0

    private lazy var cameraCursor: NSCursor = Self.makeCameraCursor()

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: cameraCursor)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // A tracking area so pointer moves arrive even without a button held.
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseMoved, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    override func draw(_ dirtyRect: NSRect) {
        // Fully transparent — no dimming, the outline does all the work.
        NSColor.clear.set()
        bounds.fill(using: .copy)

        guard let hovered, hovered.appKitFrame.intersects(screenFrame) else { return }

        // Hovered window, translated into this screen's local coordinates.
        let local = CGRect(
            x: hovered.appKitFrame.minX - screenFrame.minX,
            y: hovered.appKitFrame.minY - screenFrame.minY,
            width: hovered.appKitFrame.width,
            height: hovered.appKitFrame.height
        )

        let radius: CGFloat = 10
        let inset = local.insetBy(dx: 1.5, dy: 1.5) // keep the 3pt stroke inside the edge
        let outline = NSBezierPath(roundedRect: inset, xRadius: radius, yRadius: radius)
        outline.lineWidth = 3

        // Base: the system accent, a touch translucent so it reads as a glow.
        NSColor.controlAccentColor.withAlphaComponent(0.9).setStroke()
        outline.stroke()

        drawSweep(on: outline, in: inset)
    }

    /// The foil-card highlight: a diagonal band of white light that slides once
    /// across the outline, clipped to the stroke so only the border glints.
    private func drawSweep(on outline: NSBezierPath, in rect: CGRect) {
        guard sweepPhase < 1 else { return }
        guard let ctx = NSGraphicsContext.current else { return }

        ctx.saveGraphicsState()
        outline.lineWidth = 3
        outline.setClip()

        let bandWidth = rect.width * 0.4
        let travel = rect.width + bandWidth
        let x = rect.minX - bandWidth + travel * sweepPhase

        let gradient = NSGradient(colors: [
            .clear,
            NSColor.white.withAlphaComponent(0.85),
            .clear,
        ])
        let bandRect = NSRect(x: x, y: rect.minY - 4, width: bandWidth, height: rect.height + 8)
        gradient?.draw(in: bandRect, angle: 30)
        ctx.restoreGraphicsState()
    }

    override func mouseMoved(with event: NSEvent) {
        controller?.pointerMoved(to: NSEvent.mouseLocation)
    }

    override func mouseDown(with event: NSEvent) {
        controller?.click()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            controller?.cancel()
        } else {
            super.keyDown(with: event)
        }
    }

    /// A small camera glyph rendered into a cursor image. Temporary — the final
    /// art lands in Stage 13.
    private static func makeCameraCursor() -> NSCursor {
        let config = NSImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
        let base = NSImage(systemSymbolName: "camera.fill", accessibilityDescription: "Capture window")?
            .withSymbolConfiguration(config)
        guard let symbol = base else { return .crosshair }

        let size = symbol.size
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.white.set()
        symbol.draw(in: NSRect(origin: .zero, size: size))
        image.unlockFocus()

        return NSCursor(image: image, hotSpot: NSPoint(x: size.width / 2, y: size.height / 2))
    }
}
