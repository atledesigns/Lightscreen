import AppKit
import SwiftUI

/// Takes a screenshot and a style and paints the finished, dressed-up image:
/// backdrop, padding, rounded corners, and the soft shadow underneath. Pure —
/// same image and style in, same pixels out, no side effects. Built on Core
/// Graphics so it stays fast even on big Retina captures.
enum BeautifyRenderer {

    /// The styled image as raw pixels. Returns nil only if the source can't be
    /// read at all.
    static func renderCGImage(_ image: NSImage, style: BeautifyStyle) -> CGImage? {
        guard let raw = image.bestCGImageForSampling() else { return nil }

        // 1. Generic device chrome, unless it's off or we're keeping the captured
        //    chrome. This grows the picture before anything else measures it.
        let chromeAdded = style.deviceFrame != .none && !style.keepOriginalChrome
        let content = chromeAdded
            ? (DeviceFrameRenderer.render(raw, frame: style.deviceFrame, urlText: style.urlText) ?? raw)
            : raw

        let contentW = CGFloat(content.width)
        let contentH = CGFloat(content.height)
        guard contentW > 0, contentH > 0 else { return nil }

        // Padding is a share of the long side, added on every edge.
        let reference = max(contentW, contentH)
        let pad = CGFloat(style.paddingPercent) / 100 * reference
        let innerW = contentW + pad * 2
        let innerH = contentH + pad * 2

        // 2. Canvas size. With a target ratio, grow whichever side is needed so
        //    the padded content fits inside that shape; otherwise the canvas is
        //    just the padded content (Original).
        let canvasW: CGFloat, canvasH: CGFloat
        if let ratio = style.aspectRatio, ratio > 0 {
            if ratio >= innerW / innerH {
                canvasH = innerH
                canvasW = innerH * ratio
            } else {
                canvasW = innerW
                canvasH = innerW / ratio
            }
        } else {
            canvasW = innerW
            canvasH = innerH
        }
        let cw = canvasW.rounded()
        let ch = canvasH.rounded()

        // Pixels-per-point, so point-based knobs (corners, shadow) scale with the
        // capture's resolution and look the same as they do on screen.
        let scale = contentW / max(image.size.width, 1)

        let space = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: Int(cw), height: Int(ch),
            bitsPerComponent: 8, bytesPerRow: 0, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.interpolationQuality = .high
        let canvas = CGRect(x: 0, y: 0, width: cw, height: ch)

        // 3. Backdrop.
        drawBackground(style.background, in: canvas, ctx: ctx)

        // 4. The content, centred in the canvas. Skip extra corner rounding when
        //    a device frame is on — the frame already shapes its own corners.
        let contentRect = CGRect(x: (cw - contentW) / 2, y: (ch - contentH) / 2, width: contentW, height: contentH)
        let radius = chromeAdded ? 0 : min(CGFloat(style.cornerRadius) * scale, min(contentW, contentH) / 2)

        // Clip the content to rounded corners on its own transparent layer. This
        // is the key to a clean shadow: window shots (and device frames) carry
        // transparent corners, so the shadow must be cast from the real
        // silhouette — never from an opaque card that would show through white.
        let rounded = roundedContent(content, width: contentW, height: contentH, radius: radius, space: space)

        if let rounded {
            ctx.saveGState()
            if style.shadow.enabled {
                let shadowColor = CGColor(red: 0, green: 0, blue: 0, alpha: CGFloat(style.shadow.opacity))
                // Screen "down" is negative-y in Core Graphics, hence the flip.
                ctx.setShadow(
                    offset: CGSize(width: 0, height: -CGFloat(style.shadow.yOffset) * scale),
                    blur: CGFloat(style.shadow.blur) * scale,
                    color: shadowColor
                )
            }
            ctx.draw(rounded, in: contentRect)
            ctx.restoreGState()
        }

        return ctx.makeImage()
    }

    /// The styled image as an `NSImage`, for live preview in the editor.
    static func render(_ image: NSImage, style: BeautifyStyle) -> NSImage? {
        guard let cg = renderCGImage(image, style: style) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }

    /// The styled image as PNG bytes, for saving. Carries real transparency when
    /// the background is set to transparent.
    static func pngData(_ image: NSImage, style: BeautifyStyle) -> Data? {
        guard let cg = renderCGImage(image, style: style) else { return nil }
        return NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])
    }

    /// The screenshot drawn onto a transparent canvas, clipped to rounded
    /// corners. Anything outside the rounded shape (and any transparency the
    /// screenshot already has) stays clear — so the shadow we cast from this
    /// later traces the real silhouette, with no opaque fill leaking through.
    private static func roundedContent(_ source: CGImage, width: CGFloat, height: CGFloat, radius: CGFloat, space: CGColorSpace) -> CGImage? {
        guard let ctx = CGContext(
            data: nil, width: source.width, height: source.height,
            bitsPerComponent: 8, bytesPerRow: 0, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.interpolationQuality = .high
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        if radius > 0 {
            ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
            ctx.clip()
        }
        ctx.draw(source, in: rect)
        return ctx.makeImage()
    }

    // MARK: - Backdrop

    private static func drawBackground(_ background: BeautifyStyle.Background, in rect: CGRect, ctx: CGContext) {
        switch background {
        case .transparent:
            return // leave the canvas clear so the PNG keeps its transparency

        case .solid(let color):
            ctx.setFillColor(cgColor(color))
            ctx.fill(rect)

        case .gradient(let c1, let c2, let angle):
            let space = CGColorSpaceCreateDeviceRGB()
            guard let gradient = CGGradient(
                colorsSpace: space,
                colors: [cgColor(c1), cgColor(c2)] as CFArray,
                locations: [0, 1]
            ) else { return }

            // Aim the gradient along the chosen angle, running corner-to-corner
            // so the colours always span the whole frame.
            let radians = angle * .pi / 180
            let dx = cos(radians), dy = sin(radians)
            let half = max(rect.width, rect.height)
            let center = CGPoint(x: rect.midX, y: rect.midY)
            let start = CGPoint(x: center.x - dx * half / 2, y: center.y - dy * half / 2)
            let end = CGPoint(x: center.x + dx * half / 2, y: center.y + dy * half / 2)
            ctx.drawLinearGradient(gradient, start: start, end: end,
                                   options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        }
    }

    private static func cgColor(_ color: Color) -> CGColor {
        let ns = NSColor(color)
        return (ns.usingColorSpace(.sRGB) ?? ns).cgColor
    }
}

extension NSImage {
    /// A smaller copy capped to `maxPixel` on its long side, for snappy live
    /// re-rendering while sliders move. Returns self if it's already small enough.
    func downscaled(maxPixel: CGFloat) -> NSImage {
        guard let cg = bestCGImageForSampling() else { return self }
        let w = CGFloat(cg.width), h = CGFloat(cg.height)
        let longSide = max(w, h)
        guard longSide > maxPixel else { return self }

        let ratio = maxPixel / longSide
        let nw = Int((w * ratio).rounded()), nh = Int((h * ratio).rounded())
        let space = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: max(1, nw), height: max(1, nh),
            bitsPerComponent: 8, bytesPerRow: 0, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return self }
        ctx.interpolationQuality = .high
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: nw, height: nh))
        guard let out = ctx.makeImage() else { return self }
        return NSImage(cgImage: out, size: NSSize(width: nw, height: nh))
    }
}
