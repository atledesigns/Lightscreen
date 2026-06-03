import AppKit

/// One real, on-screen app window the highlighter can point at: its id (for
/// capture), where it sits in AppKit screen coordinates (for drawing the
/// outline), and which app owns it (so the saved shot credits the right app).
struct OnScreenWindow: Equatable {
    let id: CGWindowID
    let appKitFrame: CGRect
    let ownerPID: pid_t
}

/// Figures out which window the cursor is over. Reads the live window list the
/// window server keeps, front-to-back, and skips everything that isn't a normal
/// app window — menu bars, the Dock, tooltips, our own overlay — so the user
/// only ever highlights something real.
enum WindowEnumerator {

    /// The frontmost normal window under an AppKit screen point, or nil over
    /// empty desktop. `excludingPID` drops our own windows (the overlay itself).
    static func frontmostWindow(atAppKitPoint point: CGPoint, excludingPID pid: pid_t) -> OnScreenWindow? {
        let cgPoint = appKitToCG(point)
        let options: CGWindowListOption = [.optionOnScreenOnly]
        guard let infoList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        // The list is ordered front-to-back, so the first hit is the topmost.
        for info in infoList {
            // Layer 0 = ordinary app windows. Menu bar, Dock, popovers, and
            // tooltips live on higher layers and drop out here.
            guard (info[kCGWindowLayer as String] as? Int) == 0 else { continue }

            guard let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t, ownerPID != pid else { continue }

            // Skip fully transparent helper windows.
            if let alpha = info[kCGWindowAlpha as String] as? Double, alpha < 0.05 { continue }

            guard let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let cgRect = CGRect(dictionaryRepresentation: boundsDict) else { continue }

            // Ignore slivers (stray 1px helper windows, thin shadow strips).
            if cgRect.width < 40 || cgRect.height < 40 { continue }

            if cgRect.contains(cgPoint) {
                guard let id = info[kCGWindowNumber as String] as? CGWindowID else { continue }
                return OnScreenWindow(id: id, appKitFrame: cgToAppKit(cgRect), ownerPID: ownerPID)
            }
        }
        return nil
    }

    // MARK: - Coordinate bridging

    // The window server measures from the TOP-LEFT of the primary display, y
    // going down. AppKit measures from its BOTTOM-LEFT, y going up. Both share
    // that corner as the pivot, so one flip about the primary screen's height
    // converts either way — and it stays correct for displays stacked above or
    // beside the primary.
    private static var primaryHeight: CGFloat {
        (NSScreen.screens.first { $0.frame.origin == .zero } ?? NSScreen.main)?.frame.height ?? 0
    }

    private static func appKitToCG(_ p: CGPoint) -> CGPoint {
        CGPoint(x: p.x, y: primaryHeight - p.y)
    }

    private static func cgToAppKit(_ r: CGRect) -> CGRect {
        CGRect(x: r.origin.x, y: primaryHeight - r.origin.y - r.height, width: r.width, height: r.height)
    }
}
