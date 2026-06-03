import AppKit

/// A shot that's been captured but not yet committed anywhere. It lives in the
/// floating preview while the user decides: ignore it (auto-saves to library),
/// drag it out (goes straight to a destination), or click to save with options.
struct PendingCapture {
    let pngData: Data
    let image: NSImage
    let captureMode: CaptureMode
    let outputMode: OutputMode
    let sourceAppBundleID: String?
    let capturedAt: Date
    /// Display name including `.png`, e.g. "Screenshot 2026-06-02 at 19.00.06.png".
    let suggestedName: String
    /// A throwaway copy on disk so the shot can be dragged into other apps.
    let tempURL: URL
}
