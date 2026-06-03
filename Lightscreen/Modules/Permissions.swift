import AppKit
import CoreGraphics
import ApplicationServices

/// Tiny read-only window onto the two macOS permissions Lightscreen relies on:
/// Screen Recording (to grab pixels) and Accessibility (to drive a window's
/// scroll for full-page catches). The Settings → Permissions section shows these
/// as green/red badges with a jump-to-Settings button.
enum Permissions {
    /// True when macOS has granted screen capture. `CGPreflight…` checks without
    /// triggering the system prompt.
    static var screenRecordingGranted: Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// True when the app is trusted to control other apps (synthetic scroll).
    static var accessibilityGranted: Bool {
        AXIsProcessTrusted()
    }

    static func openScreenRecordingSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
    }

    static func openAccessibilitySettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    private static func open(_ string: String) {
        guard let url = URL(string: string) else { return }
        NSWorkspace.shared.open(url)
    }
}
