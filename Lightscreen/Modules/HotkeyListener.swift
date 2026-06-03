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

    /// The shortcut currently registered, so a rebind can be applied live.
    private var combo: HotKeyCombo = .default

    /// A private four-letter tag so the system knows this shortcut belongs to us.
    private let signature: OSType = 0x4C534352 // "LSCR"

    /// Begin listening. Pass the user's saved shortcut, or default to ⌘⇧7.
    func start(combo: HotKeyCombo = .default) {
        self.combo = combo

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

        registerHotKey()
    }

    /// Swap in a new shortcut without restarting the listener — used when the
    /// user rebinds it in Settings.
    func rebind(to combo: HotKeyCombo) {
        self.combo = combo
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        registerHotKey()
    }

    private func registerHotKey() {
        let hotKeyID = EventHotKeyID(signature: signature, id: 1)
        RegisterEventHotKey(
            combo.keyCode,
            combo.carbonModifiers,
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
