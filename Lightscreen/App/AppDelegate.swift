import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item?.button {
            let image = NSImage(systemSymbolName: "camera.fill", accessibilityDescription: "Lightscreen")
            image?.isTemplate = true
            button.image = image
            button.image?.size = NSSize(width: 18, height: 18)
        }
        statusItem = item
    }
}

