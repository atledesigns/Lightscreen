import AppKit
import CoreText

/// The chrome we can wrap a screenshot in. All generic and privacy-safe by
/// default — no app icons, no real titles, blank tabs — so a shared shot never
/// leaks more than the picture itself.
enum DeviceFrame: String, CaseIterable, Identifiable {
    case none, mac, iphone, browser
    var id: String { rawValue }

    var label: String {
        switch self {
        case .none:    return "None"
        case .mac:     return "Mac window"
        case .iphone:  return "iPhone"
        case .browser: return "Browser"
        }
    }
}

/// Draws generic device chrome around a screenshot. Pure Core Graphics: a
/// screenshot in, a larger framed image out, with transparent rounded corners so
/// the beautify shadow later hugs the real silhouette.
enum DeviceFrameRenderer {

    /// Wrap `source` in the chosen chrome. Returns nil only for `.none` (nothing
    /// to add) or if a drawing context can't be made.
    static func render(_ source: CGImage, frame: DeviceFrame, urlText: String) -> CGImage? {
        switch frame {
        case .none:    return nil
        case .mac:     return macWindow(source)
        case .iphone:  return iPhone(source)
        case .browser: return browser(source, urlText: urlText)
        }
    }

    // MARK: - Mac window

    private static func macWindow(_ source: CGImage) -> CGImage? {
        let w = CGFloat(source.width)
        let barH = max(w * 0.045, 28)
        let radius = max(w * 0.014, 10)
        let canvasW = w
        let canvasH = CGFloat(source.height) + barH

        return draw(width: canvasW, height: canvasH) { ctx in
            let outer = CGRect(x: 0, y: 0, width: canvasW, height: canvasH)
            clipRoundedAllCorners(ctx, rect: outer, radius: radius)

            // Title bar across the top (CG is y-up, so "top" is the high y band).
            let barRect = CGRect(x: 0, y: canvasH - barH, width: canvasW, height: barH)
            ctx.setFillColor(gray(0.93))
            ctx.fill(barRect)

            // The screenshot fills everything below the bar.
            ctx.draw(source, in: CGRect(x: 0, y: 0, width: w, height: CGFloat(source.height)))

            // Three traffic-light dots at the left of the bar.
            trafficLights(ctx, barRect: barRect)
        }
    }

    // MARK: - Browser

    private static func browser(_ source: CGImage, urlText: String) -> CGImage? {
        let w = CGFloat(source.width)
        let barH = max(w * 0.07, 40)
        let radius = max(w * 0.012, 9)
        let canvasW = w
        let canvasH = CGFloat(source.height) + barH

        return draw(width: canvasW, height: canvasH) { ctx in
            let outer = CGRect(x: 0, y: 0, width: canvasW, height: canvasH)
            clipRoundedAllCorners(ctx, rect: outer, radius: radius)

            let barRect = CGRect(x: 0, y: canvasH - barH, width: canvasW, height: barH)
            ctx.setFillColor(gray(0.95))
            ctx.fill(barRect)

            ctx.draw(source, in: CGRect(x: 0, y: 0, width: w, height: CGFloat(source.height)))

            trafficLights(ctx, barRect: barRect)

            // A faux URL pill — white, rounded, holding the (optional) typed URL.
            // Tabs stay blank on purpose.
            let dotsWidth = barH * 1.1
            let pillH = barH * 0.5
            let pillRect = CGRect(
                x: barRect.minX + dotsWidth,
                y: barRect.midY - pillH / 2,
                width: barRect.width - dotsWidth - barH * 0.4,
                height: pillH
            )
            ctx.setFillColor(gray(1.0))
            ctx.addPath(CGPath(roundedRect: pillRect, cornerWidth: pillH / 2, cornerHeight: pillH / 2, transform: nil))
            ctx.fillPath()

            if !urlText.isEmpty {
                drawText(urlText, in: ctx,
                         at: CGPoint(x: pillRect.minX + pillH * 0.6, y: pillRect.midY - pillH * 0.18),
                         fontSize: pillH * 0.52, color: gray(0.4))
            }
        }
    }

    // MARK: - iPhone

    private static func iPhone(_ source: CGImage) -> CGImage? {
        let w = CGFloat(source.width)
        let bezel = max(w * 0.035, 16)
        let canvasW = w + bezel * 2
        let canvasH = CGFloat(source.height) + bezel * 2
        let radius = max(w * 0.13, 44)

        return draw(width: canvasW, height: canvasH) { ctx in
            let outer = CGRect(x: 0, y: 0, width: canvasW, height: canvasH)
            // Black phone body.
            ctx.addPath(CGPath(roundedRect: outer, cornerWidth: radius, cornerHeight: radius, transform: nil))
            ctx.setFillColor(gray(0.05))
            ctx.fillPath()

            // The screen, inset by the bezel, with its own gentle rounding.
            let screenRect = CGRect(x: bezel, y: bezel, width: w, height: CGFloat(source.height))
            ctx.saveGState()
            ctx.addPath(CGPath(roundedRect: screenRect, cornerWidth: radius * 0.7, cornerHeight: radius * 0.7, transform: nil))
            ctx.clip()
            ctx.draw(source, in: screenRect)
            ctx.restoreGState()

            // Dynamic Island — a black pill near the top centre.
            let islandW = w * 0.32
            let islandH = bezel * 1.25
            let islandRect = CGRect(
                x: canvasW / 2 - islandW / 2,
                y: canvasH - bezel - islandH * 1.1,
                width: islandW, height: islandH
            )
            ctx.addPath(CGPath(roundedRect: islandRect, cornerWidth: islandH / 2, cornerHeight: islandH / 2, transform: nil))
            ctx.setFillColor(gray(0.0))
            ctx.fillPath()
        }
    }

    // MARK: - Shared drawing helpers

    private static func draw(width: CGFloat, height: CGFloat, _ body: (CGContext) -> Void) -> CGImage? {
        let space = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: Int(width.rounded()), height: Int(height.rounded()),
            bitsPerComponent: 8, bytesPerRow: 0, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.interpolationQuality = .high
        body(ctx)
        return ctx.makeImage()
    }

    private static func clipRoundedAllCorners(_ ctx: CGContext, rect: CGRect, radius: CGFloat) {
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
        ctx.clip()
    }

    private static func trafficLights(_ ctx: CGContext, barRect: CGRect) {
        let d = barRect.height * 0.3
        let gap = d * 0.6
        let startX = barRect.minX + barRect.height * 0.55
        let y = barRect.midY - d / 2
        let colors = [
            CGColor(red: 0.99, green: 0.38, blue: 0.35, alpha: 1),
            CGColor(red: 1.00, green: 0.74, blue: 0.18, alpha: 1),
            CGColor(red: 0.32, green: 0.79, blue: 0.30, alpha: 1),
        ]
        for (i, color) in colors.enumerated() {
            let x = startX + CGFloat(i) * (d + gap)
            ctx.setFillColor(color)
            ctx.fillEllipse(in: CGRect(x: x, y: y, width: d, height: d))
        }
    }

    private static func drawText(_ string: String, in ctx: CGContext, at point: CGPoint, fontSize: CGFloat, color: CGColor) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize),
            .foregroundColor: NSColor(cgColor: color) ?? .gray,
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: attrs))
        ctx.textPosition = point
        CTLineDraw(line, ctx)
    }

    private static func gray(_ v: CGFloat) -> CGColor {
        CGColor(red: v, green: v, blue: v, alpha: 1)
    }
}
