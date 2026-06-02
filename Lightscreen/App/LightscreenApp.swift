import SwiftUI

@main
struct LightscreenApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Stage 0 is intentionally minimal: no windows, just a menu bar icon.
        Settings { EmptyView() }
    }
}

