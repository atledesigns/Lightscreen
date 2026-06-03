import CoreGraphics
import Foundation

/// Drives a window from top to bottom on its own, grabbing a frame at each
/// step. It sends real scroll-wheel events (the same kind a trackpad would),
/// waits for the page to settle, snaps the window, and stops the moment a
/// fresh snap comes back identical to the last — that's the bottom.
///
/// Sending synthetic scrolls to another app needs Accessibility permission;
/// the caller checks that before starting.
@MainActor
final class AutoScrollDriver {
    private let engine: CaptureEngine

    /// Plenty of headroom for a long article, but a hard stop so a page that
    /// never settles can't scroll forever.
    private let maxFrames = 60

    init(engine: CaptureEngine) {
        self.engine = engine
    }

    /// Scrolls `windowID` from the top down. `windowCenterCG` aims the scroll
    /// wheel at the window's middle (window-server coordinates, top-left origin).
    /// `pointHeight` is the window's height in points, to size each scroll step.
    /// Returns the captured frames in order (top of page first).
    func run(
        windowID: CGWindowID,
        windowCenterCG: CGPoint,
        pointHeight: CGFloat,
        progress: @escaping (Double) -> Void,
        shouldStop: @escaping () -> Bool
    ) async -> [CGImage] {

        // Send the page firmly back to the very top, so every capture starts
        // from the same place no matter where the user left it.
        for _ in 0..<8 {
            postScroll(at: windowCenterCG, deltaY: 800) // positive = toward the top
            try? await Task.sleep(for: .milliseconds(35))
        }
        try? await Task.sleep(for: .milliseconds(300))

        // Each step travels most of a screenful, leaving an overlap band for the
        // stitcher to lock onto. (Sign note: negative scrolls the page DOWN.
        // If a future page scrolls the wrong way, this single sign is the knob.)
        let step = Int(max(120, pointHeight * 0.82))

        var frames: [CGImage] = []
        var lastHash: UInt64?

        for i in 0..<maxFrames {
            if shouldStop() { break }

            try? await Task.sleep(for: .milliseconds(230)) // let the page redraw
            guard let frame = try? await engine.captureWindowCGImage(windowID: windowID) else { break }

            let hash = RasterImage(frame)?.quickHash() ?? 0
            if let last = lastHash, hash == last {
                break // nothing changed — we've hit the bottom
            }
            frames.append(frame)
            lastHash = hash

            // We can't know the page length up front, so ease the bar toward
            // 95% and let completion snap it to full.
            progress(min(0.95, Double(i + 1) / 14.0))

            postScroll(at: windowCenterCG, deltaY: -step)
        }

        progress(1.0)
        return frames
    }

    /// One pixel-precise scroll-wheel tick aimed at `point`. Positive `deltaY`
    /// pushes the page toward the top; negative pushes it down.
    private func postScroll(at point: CGPoint, deltaY: Int) {
        guard let event = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 1,
            wheel1: Int32(deltaY),
            wheel2: 0,
            wheel3: 0
        ) else { return }
        event.location = point
        event.post(tap: .cghidEventTap)
    }
}
