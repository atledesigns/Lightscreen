import Foundation

/// The output shapes the editor can fit a shot into — sized for where it's
/// headed (Twitter, Instagram, Stories, and so on). The chosen one is sticky
/// across launches.
enum AspectRatioOption: String, CaseIterable, Identifiable {
    case r16x9   = "16:9"
    case r1x1    = "1:1"
    case r4x5    = "4:5"
    case r9x16   = "9:16"
    case r3x2    = "3:2"
    case r1_91x1 = "1.91:1"
    case original = "Original"
    case custom   = "Custom"

    var id: String { rawValue }

    /// A short hint of where each shape tends to go.
    var hint: String {
        switch self {
        case .r16x9:    return "Twitter"
        case .r1x1:     return "Instagram"
        case .r4x5:     return "Instagram portrait"
        case .r9x16:    return "Stories / Reels / TikTok"
        case .r3x2:     return "Dribbble"
        case .r1_91x1:  return "LinkedIn / OG"
        case .original: return "As captured"
        case .custom:   return "Your own size"
        }
    }

    /// Width ÷ height for the fixed shapes. Nil for Original (follow the image)
    /// and Custom (the editor supplies width × height fields instead).
    var fixedRatio: Double? {
        switch self {
        case .r16x9:    return 16.0 / 9.0
        case .r1x1:     return 1.0
        case .r4x5:     return 4.0 / 5.0
        case .r9x16:    return 9.0 / 16.0
        case .r3x2:     return 3.0 / 2.0
        case .r1_91x1:  return 1.91
        case .original, .custom: return nil
        }
    }
}
