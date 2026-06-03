import AppKit
import SwiftUI

/// Looks at an image and picks the two colours that best capture its mood — the
/// ones we paint the gradient backdrop with. It shrinks the image to a postage
/// stamp, tallies which colours cover the most area, and leans toward the
/// punchy, saturated ones over flat greys so the frame feels alive.
enum ColorSampler {

    /// The top `count` standout colours, most prominent first. Always returns at
    /// least two (it invents a gentle partner if the image is nearly one colour).
    static func dominantColors(_ image: NSImage, count: Int = 2) -> [Color] {
        guard let cg = image.bestCGImageForSampling() else {
            return [Color(.sRGB, red: 0.18, green: 0.22, blue: 0.34, opacity: 1),
                    Color(.sRGB, red: 0.30, green: 0.20, blue: 0.40, opacity: 1)]
        }

        // Shrink to a small grid — we only care about overall colour, not detail.
        let maxDim = 48
        let ratio = min(CGFloat(maxDim) / CGFloat(cg.width), CGFloat(maxDim) / CGFloat(cg.height))
        let w = max(1, Int((CGFloat(cg.width) * ratio).rounded()))
        let h = max(1, Int((CGFloat(cg.height) * ratio).rounded()))

        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        let space = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return [Color.blue, Color.purple]
        }
        ctx.interpolationQuality = .medium
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))

        // Tally colours into coarse buckets (3 bits per channel = 512 bins), and
        // keep the running average of the real pixels in each bin so the colour
        // we hand back is true to the image, not the bin's blocky centre.
        struct Bin { var count = 0; var r = 0.0; var g = 0.0; var b = 0.0 }
        var bins: [Int: Bin] = [:]

        for i in stride(from: 0, to: pixels.count, by: 4) {
            let a = pixels[i + 3]
            if a < 128 { continue } // ignore transparent areas
            let r = Int(pixels[i]), g = Int(pixels[i + 1]), b = Int(pixels[i + 2])
            let key = (r >> 5) << 6 | (g >> 5) << 3 | (b >> 5)
            var bin = bins[key] ?? Bin()
            bin.count += 1
            bin.r += Double(r); bin.g += Double(g); bin.b += Double(b)
            bins[key] = bin
        }

        // Score each bucket by how much area it covers, boosted by how vivid it
        // is — a small splash of colour can beat a big wash of grey.
        let ranked = bins.values
            .map { bin -> (color: (Double, Double, Double), score: Double) in
                let n = Double(bin.count)
                let rgb = (bin.r / n / 255, bin.g / n / 255, bin.b / n / 255)
                let sat = saturation(rgb)
                return (rgb, n * (1 + sat * 1.5))
            }
            .sorted { $0.score > $1.score }

        // Walk the ranking, skipping colours too close to ones we already took.
        var chosen: [(Double, Double, Double)] = []
        for entry in ranked {
            if chosen.allSatisfy({ distance($0, entry.color) > 0.18 }) {
                chosen.append(entry.color)
                if chosen.count == count { break }
            }
        }

        // Too monochrome to find a partner? Derive one by nudging brightness so
        // the gradient still has somewhere to travel.
        if chosen.isEmpty { chosen = [(0.2, 0.24, 0.36)] }
        while chosen.count < count {
            chosen.append(shiftedBrightness(chosen[0]))
        }

        return chosen.prefix(count).map { Color(.sRGB, red: $0.0, green: $0.1, blue: $0.2, opacity: 1) }
    }

    // MARK: - Small colour helpers

    private static func saturation(_ rgb: (Double, Double, Double)) -> Double {
        let mx = max(rgb.0, rgb.1, rgb.2), mn = min(rgb.0, rgb.1, rgb.2)
        return mx <= 0 ? 0 : (mx - mn) / mx
    }

    private static func distance(_ a: (Double, Double, Double), _ b: (Double, Double, Double)) -> Double {
        let dr = a.0 - b.0, dg = a.1 - b.1, db = a.2 - b.2
        return (dr * dr + dg * dg + db * db).squareRoot()
    }

    /// A companion colour: darken a light original, lighten a dark one, so the
    /// pair always reads as a gradient rather than a flat block.
    private static func shiftedBrightness(_ c: (Double, Double, Double)) -> (Double, Double, Double) {
        let lum = 0.299 * c.0 + 0.587 * c.1 + 0.114 * c.2
        let f = lum > 0.5 ? 0.65 : 1.45
        return (min(1, c.0 * f), min(1, c.1 * f), min(1, c.2 * f))
    }
}

extension NSImage {
    /// The sharpest underlying bitmap we can get, for reading pixels or
    /// re-rendering. Prefers a real bitmap rep (full pixel count) and falls back
    /// to a rasterised snapshot for images that don't carry one.
    func bestCGImageForSampling() -> CGImage? {
        if let rep = representations
            .compactMap({ $0 as? NSBitmapImageRep })
            .max(by: { $0.pixelsWide < $1.pixelsWide }),
           let cg = rep.cgImage {
            return cg
        }
        var rect = CGRect(origin: .zero, size: size)
        return cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }
}
