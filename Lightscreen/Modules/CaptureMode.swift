import Foundation

/// The three ways Lightscreen can grab something off the screen.
/// (None of these actually capture yet — that starts in Stage 2.)
enum CaptureMode: String, CaseIterable {
    case region
    case window
    case fullPage

    /// Human-friendly name used in the picker and in console logs for now.
    var label: String {
        switch self {
        case .region: return "Region"
        case .window: return "Window"
        case .fullPage: return "Full Page"
        }
    }

    /// Placeholder SF Symbol for each mode (final glyphs land in Stage 13).
    var symbolName: String {
        switch self {
        case .region: return "rectangle.dashed"
        case .window: return "macwindow"
        case .fullPage: return "arrow.down.doc.fill"
        }
    }
}
