import SwiftUI

/// Everything that turns a bare screenshot into a dressed-up image: the backdrop
/// behind it, how much breathing room around it, its drop shadow, how round its
/// corners are, any device chrome, and the output shape. Pure data — the
/// renderer reads this and paints accordingly.
struct BeautifyStyle: Equatable {

    /// What sits behind the screenshot.
    /// - `gradient`: two colours blended across an angle (the default look).
    /// - `solid`: one flat colour.
    /// - `transparent`: nothing — the saved PNG keeps real see-through edges.
    enum Background: Equatable {
        case gradient(Color, Color, angle: Double)
        case solid(Color)
        case transparent
    }

    /// The soft drop shadow under the screenshot.
    struct Shadow: Equatable {
        var enabled: Bool
        var blur: Double      // softness, in points
        var yOffset: Double   // how far it falls downward, in points
        var opacity: Double   // 0–1

        /// The gentle default — present but never heavy.
        static let soft = Shadow(enabled: true, blur: 40, yOffset: 10, opacity: 0.2)
    }

    var background: Background
    var paddingPercent: Double   // 0–25, room around the image as % of its long side
    var shadow: Shadow
    var cornerRadius: Double     // 0–32, in points

    // Stage 9 additions.
    var deviceFrame: DeviceFrame
    var keepOriginalChrome: Bool // when true, skip generic chrome and show as captured
    var urlText: String          // faux URL for the browser frame
    var aspectRatio: Double?     // output width ÷ height; nil = follow the image
}

/// The editable form of a style: every knob is a plain value so SwiftUI controls
/// can bind straight to it. The editor edits the draft; `toStyle()` folds it back
/// into the shape the renderer wants.
struct BeautifyDraft: Equatable {
    enum BackgroundKind: String, CaseIterable, Identifiable {
        case gradient, solid, transparent
        var id: String { rawValue }
        var label: String {
            switch self {
            case .gradient: return "Gradient"
            case .solid: return "Solid"
            case .transparent: return "Transparent"
            }
        }
    }

    var backgroundKind: BackgroundKind
    var color1: Color
    var color2: Color
    var angle: Double

    var paddingPercent: Double
    var shadowEnabled: Bool
    var shadowBlur: Double
    var shadowY: Double
    var shadowOpacity: Double
    var cornerRadius: Double

    // Stage 9 additions.
    var deviceFrame: DeviceFrame
    var keepOriginalChrome: Bool
    var urlText: String
    var ratioOption: AspectRatioOption
    var customWidth: Double
    var customHeight: Double

    /// The output ratio implied by the current choice (nil = follow the image).
    var resolvedAspectRatio: Double? {
        switch ratioOption {
        case .original:
            return nil
        case .custom:
            return customHeight > 0 ? customWidth / customHeight : nil
        default:
            return ratioOption.fixedRatio
        }
    }

    func toStyle() -> BeautifyStyle {
        let background: BeautifyStyle.Background
        switch backgroundKind {
        case .gradient:    background = .gradient(color1, color2, angle: angle)
        case .solid:       background = .solid(color1)
        case .transparent: background = .transparent
        }
        return BeautifyStyle(
            background: background,
            paddingPercent: paddingPercent,
            shadow: .init(enabled: shadowEnabled, blur: shadowBlur, yOffset: shadowY, opacity: shadowOpacity),
            cornerRadius: cornerRadius,
            deviceFrame: deviceFrame,
            keepOriginalChrome: keepOriginalChrome,
            urlText: urlText,
            aspectRatio: resolvedAspectRatio
        )
    }

    /// The opening look for a freshly captured image: a gradient sampled from the
    /// image itself, 10% padding, a soft shadow, lightly rounded corners, no
    /// device frame, and a 16:9 output (overridden by the sticky ratio).
    static func makeDefault(from image: NSImage) -> BeautifyDraft {
        let colors = ColorSampler.dominantColors(image, count: 2)
        let c1 = colors.first ?? Color.blue
        let c2 = colors.count > 1 ? colors[1] : Color.purple
        return BeautifyDraft(
            backgroundKind: .gradient,
            color1: c1,
            color2: c2,
            angle: 135,
            paddingPercent: 10,
            shadowEnabled: true,
            shadowBlur: 40,
            shadowY: 10,
            shadowOpacity: 0.2,
            cornerRadius: 12,
            deviceFrame: .none,
            keepOriginalChrome: false,
            urlText: "",
            ratioOption: .r16x9,
            customWidth: 1600,
            customHeight: 900
        )
    }
}
