import AppKit
import ScreenCaptureKit

enum CaptureError: Error {
    case noDisplay
    case cropFailed
    case encodeFailed
}

/// Wraps macOS's screen-capture machinery. Give it a rectangle on screen,
/// get back PNG bytes. The first call triggers the system's one-time
/// "allow screen recording" prompt.
struct CaptureEngine {

    /// `globalRect` is in AppKit screen coordinates (origin at the bottom-left
    /// of the main display). Returns full-resolution PNG data of that region.
    func captureRegion(_ globalRect: CGRect) async throws -> Data {
        // Pick the display the selection's CENTRE sits on, so a rectangle that
        // grazes an edge still resolves to the screen you were actually on.
        let centre = CGPoint(x: globalRect.midX, y: globalRect.midY)
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(centre) })
            ?? NSScreen.screens.first(where: { $0.frame.intersects(globalRect) })
            ?? NSScreen.main else {
            throw CaptureError.noDisplay
        }
        let screenNumber = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value

        // Ask the system which displays it can see; match ours by id.
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard let scDisplay = content.displays.first(where: { $0.displayID == screenNumber }) ?? content.displays.first else {
            throw CaptureError.noDisplay
        }
        NSLog("Lightscreen: screen.frame=\(screen.frame.debugDescription) screenNumber=\(screenNumber ?? 0) scDisplay.id=\(scDisplay.displayID) scDisplay=\(scDisplay.width)x\(scDisplay.height)")

        // Capture the WHOLE display at full resolution. We deliberately avoid
        // ScreenCaptureKit's own cropping (`sourceRect`), because in scaled
        // Retina modes the pixels-per-point ratio isn't a clean number and the
        // crop drifts, leaving blank space. Instead we crop ourselves below,
        // using the true ratio measured from the returned image.
        let scale = screen.backingScaleFactor
        let config = SCStreamConfiguration()
        config.width = Int(screen.frame.width * scale)
        config.height = Int(screen.frame.height * scale)
        config.showsCursor = false
        config.scalesToFit = true

        let filter = SCContentFilter(display: scDisplay, excludingWindows: [])
        let fullImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)

        // Real pixels-per-point, straight from the image we got back.
        let pxPerPointX = CGFloat(fullImage.width) / screen.frame.width
        let pxPerPointY = CGFloat(fullImage.height) / screen.frame.height

        // Region in the display's own top-left pixel space.
        let localX = globalRect.minX - screen.frame.minX
        let localYFromTop = screen.frame.maxY - globalRect.maxY
        let cropRect = CGRect(
            x: localX * pxPerPointX,
            y: localYFromTop * pxPerPointY,
            width: globalRect.width * pxPerPointX,
            height: globalRect.height * pxPerPointY
        ).integral

        NSLog("Lightscreen: fullImage=\(fullImage.width)x\(fullImage.height) ppp=(\(pxPerPointX),\(pxPerPointY)) cropRect=\(cropRect.debugDescription)")

        guard let cropped = fullImage.cropping(to: cropRect) else {
            throw CaptureError.cropFailed
        }
        return try pngData(from: cropped)
    }

    /// Grabs a single on-screen window by its window id, cleanly — content plus
    /// the soft macOS drop shadow, nothing behind it. `windowID` is the same id
    /// the highlighter overlay reports for the window under the cursor.
    func captureWindow(windowID: CGWindowID) async throws -> Data {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
            throw CaptureError.noDisplay
        }

        // Filter to just this window, free of whatever sits behind it.
        let filter = SCContentFilter(desktopIndependentWindow: window)

        // Let the filter tell us the true size (it already accounts for the
        // shadow margin and the display's pixel density), so the shot is sharp
        // on Retina and the shadow isn't clipped.
        let config = SCStreamConfiguration()
        config.width = Int((filter.contentRect.width * CGFloat(filter.pointPixelScale)).rounded())
        config.height = Int((filter.contentRect.height * CGFloat(filter.pointPixelScale)).rounded())
        config.showsCursor = false
        config.ignoreShadowsSingleWindow = false // keep the shadow
        config.scalesToFit = true

        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        return try pngData(from: image)
    }

    private func pngData(from cgImage: CGImage) throws -> Data {
        let rep = NSBitmapImageRep(cgImage: cgImage)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw CaptureError.encodeFailed
        }
        return data
    }
}
