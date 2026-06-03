import SwiftUI

/// What happens to a capture after you take it.
/// - `beautified`: opens the editor to dress it up (gradient, shadow, padding).
/// - `raw`: keeps the screenshot exactly as captured.
enum OutputMode: String {
    case beautified
    case raw

    var label: String {
        switch self {
        case .beautified: return "Beautified"
        case .raw: return "Raw"
        }
    }

    var symbolName: String {
        switch self {
        case .beautified: return "wand.and.stars"
        case .raw: return "photo"
        }
    }

    /// A small voiced line under the toggle so the choice explains itself.
    var caption: String {
        switch self {
        case .beautified: return "Opens the editor to dress it up."
        case .raw: return "Keeps the shot exactly as caught."
        }
    }
}

/// Remembers the Beautified ↔ Raw choice across launches.
/// The picker reads and writes this; the value survives quitting the app.
final class OutputModeStore: ObservableObject {
    private static let key = "default_output_mode"

    @Published var mode: OutputMode {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: Self.key) }
    }

    init() {
        let saved = UserDefaults.standard.string(forKey: Self.key)
        // First launch (or anything unexpected) defaults to Beautified — the flagship path.
        self.mode = saved.flatMap(OutputMode.init(rawValue:)) ?? .beautified
    }
}
