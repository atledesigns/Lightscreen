import AppKit
import Carbon.HIToolbox

/// Listens for ⌘⇧7 anywhere on the Mac — even while you're in another app —
/// and calls `onTrigger` when it's pressed.
///
/// macOS only lets you register a *system-wide* shortcut through an older
/// Apple toolbox (Carbon). SwiftUI can't reach this, so we wrap it here and
/// expose a single clean callback to the rest of the app.
final class HotkeyListener {
    /// Runs (on the main thread) every time the shortcut is pressed.
    var onTrigger: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    /// A private four-letter tag so the system knows this shortcut belongs to us.
    private let signature: OSType = 0x4C534352 // "LSCR"

    func start() {
        // Tell the system we care about "a registered shortcut was pressed" events.
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: OSType(kEventHotKeyPressed)
        )

        let selfPointer = Unmanaged.passUnretained(self).toOpaque()

        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return noErr }
                let listener = Unmanaged<HotkeyListener>.fromOpaque(userData).takeUnretainedValue()
                listener.onTrigger?()
                return noErr
            },
            1,
            &eventType,
            selfPointer,
            &handlerRef
        )

        // Register ⌘⇧7. (kVK_ANSI_7 is the "7" key; cmdKey + shiftKey are the modifiers.)
        let hotKeyID = EventHotKeyID(signature: signature, id: 1)
        RegisterEventHotKey(
            UInt32(kVK_ANSI_7),
            UInt32(cmdKey | shiftKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }

    func stop() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let handlerRef {
            RemoveEventHandler(handlerRef)
            self.handlerRef = nil
        }
    }

    deinit { stop() }
}
