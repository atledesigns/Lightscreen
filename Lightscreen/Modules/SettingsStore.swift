import SwiftUI
import Carbon.HIToolbox

/// A global shortcut as the system understands it: a key plus modifier flags.
/// Stored as two plain numbers so it survives quitting, and able to draw itself
/// as a friendly "⌘⇧7" for the settings field.
struct HotKeyCombo: Equatable {
    var keyCode: UInt32
    var carbonModifiers: UInt32 // cmdKey | shiftKey | optionKey | controlKey

    static let `default` = HotKeyCombo(
        keyCode: UInt32(kVK_ANSI_7),
        carbonModifiers: UInt32(cmdKey | shiftKey)
    )

    /// "⌘⇧7" — the way Atle reads it.
    var display: String {
        var s = ""
        if carbonModifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if carbonModifiers & UInt32(optionKey)  != 0 { s += "⌥" }
        if carbonModifiers & UInt32(shiftKey)   != 0 { s += "⇧" }
        if carbonModifiers & UInt32(cmdKey)     != 0 { s += "⌘" }
        s += Self.keyName(keyCode)
        return s
    }

    /// AppKit's modifier flags, for translating a recorded key-press back into
    /// the Carbon mask the hotkey API wants.
    static func carbonFlags(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var mask: UInt32 = 0
        if flags.contains(.command) { mask |= UInt32(cmdKey) }
        if flags.contains(.shift)   { mask |= UInt32(shiftKey) }
        if flags.contains(.option)  { mask |= UInt32(optionKey) }
        if flags.contains(.control) { mask |= UInt32(controlKey) }
        return mask
    }

    /// A readable label for the common keys we expect (letters, digits, etc.).
    static func keyName(_ code: UInt32) -> String {
        let map: [UInt32: String] = [
            UInt32(kVK_ANSI_0): "0", UInt32(kVK_ANSI_1): "1", UInt32(kVK_ANSI_2): "2",
            UInt32(kVK_ANSI_3): "3", UInt32(kVK_ANSI_4): "4", UInt32(kVK_ANSI_5): "5",
            UInt32(kVK_ANSI_6): "6", UInt32(kVK_ANSI_7): "7", UInt32(kVK_ANSI_8): "8",
            UInt32(kVK_ANSI_9): "9",
            UInt32(kVK_Space): "Space", UInt32(kVK_Return): "↩",
        ]
        if let name = map[code] { return name }
        // Fall back to the character the key produces, upper-cased.
        if let s = Self.character(for: code) { return s.uppercased() }
        return "Key \(code)"
    }

    private static func character(for keyCode: UInt32) -> String? {
        guard let layout = TISGetInputSourceProperty(
            TISCopyCurrentKeyboardLayoutInputSource().takeRetainedValue(),
            kTISPropertyUnicodeKeyLayoutData
        ) else { return nil }
        let data = unsafeBitCast(layout, to: CFData.self)
        let keyLayout = unsafeBitCast(CFDataGetBytePtr(data), to: UnsafePointer<UCKeyboardLayout>.self)
        var deadKeys: UInt32 = 0
        var length = 0
        var chars = [UniChar](repeating: 0, count: 4)
        let status = UCKeyTranslate(
            keyLayout, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0,
            UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit),
            &deadKeys, chars.count, &length, &chars
        )
        guard status == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: chars, count: length)
    }
}

/// The accent palette, drawn from the Pokémon energy types. "System" keeps
/// macOS's own accent; the rest paint the app one mood.
enum AppAccent: String, CaseIterable, Identifiable {
    case system, water, fire, fairy, electric, grass, psychic, steel
    var id: String { rawValue }

    var label: String {
        switch self {
        case .system:   return "System"
        case .water:    return "Water (blue)"
        case .fire:     return "Fire (orange)"
        case .fairy:    return "Fairy (pink)"
        case .electric: return "Electric (yellow)"
        case .grass:    return "Grass (green)"
        case .psychic:  return "Psychic (purple)"
        case .steel:    return "Steel (silver)"
        }
    }

    /// The colour, or nil for System (fall back to the OS accent).
    var color: Color? {
        switch self {
        case .system:   return nil
        case .water:    return Color(.sRGB, red: 0.16, green: 0.52, blue: 0.92, opacity: 1)
        case .fire:     return Color(.sRGB, red: 0.95, green: 0.45, blue: 0.16, opacity: 1)
        case .fairy:    return Color(.sRGB, red: 0.96, green: 0.46, blue: 0.74, opacity: 1)
        case .electric: return Color(.sRGB, red: 0.97, green: 0.80, blue: 0.10, opacity: 1)
        case .grass:    return Color(.sRGB, red: 0.30, green: 0.72, blue: 0.36, opacity: 1)
        case .psychic:  return Color(.sRGB, red: 0.60, green: 0.32, blue: 0.86, opacity: 1)
        case .steel:    return Color(.sRGB, red: 0.55, green: 0.60, blue: 0.66, opacity: 1)
        }
    }
}

/// One home for every preference the Settings window edits. Backed by
/// `UserDefaults`, so every change is remembered the instant it's made (no Apply
/// button). Other parts of the app read these to decide defaults, sounds, and
/// the accent everything is tinted with.
@MainActor
final class SettingsStore: ObservableObject {
    // Keys (some shared with older stores so nothing fights over the truth).
    private enum K {
        static let hotKeyCode = "hotkey_keycode"
        static let hotKeyMods = "hotkey_modifiers"
        static let defaultCapture = "default_capture_mode"
        static let defaultRatio = "last_aspect_ratio" // shared with the editor
        static let pinned = "pinned_folders"
        static let defaultVibe = "default_vibe_id"
        static let captureSound = "capture_sound"
        static let sparkle = "sparkle_on_capture"
        static let saveDelight = "save_delight"
        static let accent = "accent_option"
    }

    private let defaults = UserDefaults.standard

    /// Fired when the shortcut changes, so the listener can re-register it live.
    var onHotkeyChanged: ((HotKeyCombo) -> Void)?

    @Published var hotkey: HotKeyCombo {
        didSet {
            defaults.set(Int(hotkey.keyCode), forKey: K.hotKeyCode)
            defaults.set(Int(hotkey.carbonModifiers), forKey: K.hotKeyMods)
            onHotkeyChanged?(hotkey)
        }
    }

    @Published var defaultCaptureMode: CaptureMode {
        didSet { defaults.set(defaultCaptureMode.rawValue, forKey: K.defaultCapture) }
    }

    @Published var defaultRatioRaw: String {
        didSet { defaults.set(defaultRatioRaw, forKey: K.defaultRatio) }
    }

    @Published var pinnedFolders: [URL] {
        didSet { defaults.set(pinnedFolders.map(\.path), forKey: K.pinned) }
    }

    @Published var defaultVibeID: String? {
        didSet { defaults.set(defaultVibeID, forKey: K.defaultVibe) }
    }

    @Published var captureSound: Bool {
        didSet { defaults.set(captureSound, forKey: K.captureSound) }
    }

    @Published var sparkle: Bool {
        didSet { defaults.set(sparkle, forKey: K.sparkle) }
    }

    @Published var saveDelight: Bool {
        didSet { defaults.set(saveDelight, forKey: K.saveDelight) }
    }

    @Published var accent: AppAccent {
        didSet { defaults.set(accent.rawValue, forKey: K.accent) }
    }

    init() {
        let code = defaults.object(forKey: K.hotKeyCode) as? Int
        let mods = defaults.object(forKey: K.hotKeyMods) as? Int
        if let code, let mods {
            hotkey = HotKeyCombo(keyCode: UInt32(code), carbonModifiers: UInt32(mods))
        } else {
            hotkey = .default
        }
        defaultCaptureMode = (defaults.string(forKey: K.defaultCapture).flatMap(CaptureMode.init(rawValue:))) ?? .region
        defaultRatioRaw = defaults.string(forKey: K.defaultRatio) ?? "Original"
        let paths = defaults.array(forKey: K.pinned) as? [String] ?? []
        pinnedFolders = paths.map { URL(fileURLWithPath: $0) }
        defaultVibeID = defaults.string(forKey: K.defaultVibe)
        // Sound defaults OFF; sparkle and save-delight default ON.
        captureSound = defaults.object(forKey: K.captureSound) as? Bool ?? false
        sparkle = defaults.object(forKey: K.sparkle) as? Bool ?? true
        saveDelight = defaults.object(forKey: K.saveDelight) as? Bool ?? true
        accent = (defaults.string(forKey: K.accent).flatMap(AppAccent.init(rawValue:))) ?? .system
    }

    /// The colour to tint accent surfaces with — the chosen accent, or the OS
    /// accent when set to System.
    var accentColor: Color { accent.color ?? .accentColor }

    // MARK: - Pinned folders

    func pin(_ folder: URL) {
        guard !pinnedFolders.contains(folder) else { return }
        pinnedFolders.append(folder)
    }

    func unpin(_ folder: URL) {
        pinnedFolders.removeAll { $0 == folder }
    }
}

// MARK: - App accent, available anywhere in the view tree

private struct AppAccentKey: EnvironmentKey {
    static let defaultValue: Color = .accentColor
}

extension EnvironmentValues {
    /// The app's chosen accent colour, threaded down so custom surfaces (the
    /// selection ring, the active-vibe frame) follow the Appearance setting.
    var appAccent: Color {
        get { self[AppAccentKey.self] }
        set { self[AppAccentKey.self] = newValue }
    }
}

/// Wraps any window's root so the whole view tree picks up the chosen accent —
/// both SwiftUI's own `.tint` (buttons, toggles) and our `appAccent` environment
/// (custom rings and frames). Re-renders when the accent changes.
struct AccentRoot<Content: View>: View {
    @ObservedObject var settings: SettingsStore
    @ViewBuilder var content: Content

    var body: some View {
        content
            .tint(settings.accentColor)
            .environment(\.appAccent, settings.accentColor)
    }
}
