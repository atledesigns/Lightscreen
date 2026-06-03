import CoreGraphics
import Foundation

/// Turns a stack of overlapping scroll frames into one tall image.
///
/// The trick: as the page scrolls, the middle slides but anything pinned in
/// place (a top nav bar, a bottom toolbar) stays put. So we (1) spot the
/// pinned header/footer and keep each only once, and (2) measure exactly how
/// far the page moved between each pair of frames, so the moving middle stacks
/// up seamlessly with no repeats and no gaps. Pure: same frames in, same tall
/// image out, no side effects.
enum ImageStitcher {

    /// Ordered, overlapping frames (top of page first) → one tall image.
    static func stitch(_ frames: [CGImage]) -> CGImage? {
        guard let first = frames.first else { return nil }
        guard frames.count > 1 else { return first }

        // The window mustn't have changed size mid-scroll, or the maths below
        // breaks. If it did, just stack the frames whole — ugly but lossless.
        let width = first.width
        let height = first.height
        guard frames.allSatisfy({ $0.width == width && $0.height == height }) else {
            return stackWhole(frames)
        }

        // Per-row fingerprints for every frame, indexed from the TOP.
        let rasters = frames.compactMap { RasterImage($0) }
        guard rasters.count == frames.count else { return stackWhole(frames) }
        let rows = rasters.map { $0.rowHashes() }

        // How tall is the pinned region at the top, and at the bottom? Measured
        // by how many rows stay byte-identical across consecutive frames.
        let headerH = stickyTop(rows, maxH: height * 45 / 100)
        let footerH = stickyBottom(rows, height: height, maxH: height * 45 / 100)

        let bodyTop = headerH
        let bodyBottom = height - footerH
        let bodyHeight = bodyBottom - bodyTop
        guard bodyHeight > 0 else { return stackWhole(frames) }

        // How far the page moved between each neighbouring pair (in rows).
        var deltas: [Int] = []
        for i in 1..<frames.count {
            let d = scrollDelta(
                rows[i - 1], rows[i],
                bodyTop: bodyTop, bodyBottom: bodyBottom
            )
            deltas.append(d)
        }

        // Lay out the slices top-to-bottom: header once, then the first frame's
        // whole body, then only the freshly-revealed strip from each later
        // frame, then the footer once.
        struct Slice { let source: CGImage; let srcTop: Int; let h: Int }
        var slices: [Slice] = []

        if headerH > 0 {
            slices.append(Slice(source: frames[0], srcTop: 0, h: headerH))
        }
        slices.append(Slice(source: frames[0], srcTop: bodyTop, h: bodyHeight))

        for i in 1..<frames.count {
            let d = min(max(deltas[i - 1], 0), bodyHeight)
            guard d > 0 else { continue } // no movement caught — nothing new
            // The newly-revealed content is the bottom `d` rows of this frame's body.
            slices.append(Slice(source: frames[i], srcTop: bodyBottom - d, h: d))
        }

        if footerH > 0, let last = frames.last {
            slices.append(Slice(source: last, srcTop: bodyBottom, h: footerH))
        }

        let totalHeight = slices.reduce(0) { $0 + $1.h }
        guard totalHeight > 0 else { return stackWhole(frames) }

        guard let ctx = CGContext(
            data: nil, width: width, height: totalHeight,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        // CGContext draws from the bottom up, but our slice list runs top-down,
        // so each slice's bottom edge sits at (total − itsTop − itsHeight).
        var destTop = 0
        for slice in slices {
            let cropRect = CGRect(x: 0, y: slice.srcTop, width: width, height: slice.h)
            guard let piece = slice.source.cropping(to: cropRect) else { destTop += slice.h; continue }
            let drawY = totalHeight - destTop - slice.h
            ctx.draw(piece, in: CGRect(x: 0, y: drawY, width: width, height: slice.h))
            destTop += slice.h
        }

        return ctx.makeImage()
    }

    // MARK: - Sticky region detection

    /// Tallest run of top rows that match across every consecutive pair.
    private static func stickyTop(_ rows: [[UInt64]], maxH: Int) -> Int {
        guard let height = rows.first?.count, height > 0 else { return 0 }
        var h = 0
        while h < min(maxH, height) {
            if rows.allPairsMatchRow(h) { h += 1 } else { break }
        }
        return h
    }

    /// Tallest run of bottom rows that match across every consecutive pair.
    private static func stickyBottom(_ rows: [[UInt64]], height: Int, maxH: Int) -> Int {
        var f = 0
        while f < min(maxH, height) {
            let y = height - 1 - f
            if rows.allPairsMatchRow(y) { f += 1 } else { break }
        }
        return f
    }

    // MARK: - Scroll-distance measurement

    /// How many rows the body slid between two frames. We try each possible
    /// shift and keep the one where the overlap lines up best.
    private static func scrollDelta(
        _ a: [UInt64], _ b: [UInt64], bodyTop: Int, bodyBottom: Int
    ) -> Int {
        let bodyHeight = bodyBottom - bodyTop
        guard bodyHeight > 1 else { return bodyHeight }

        // Sample every other row when scoring — plenty reliable, much faster.
        let stride = 2
        let minOverlap = max(20, bodyHeight / 6)

        var bestDelta = bodyHeight   // fallback: assume no usable overlap
        var bestScore = 0

        var d = 1
        while d < bodyHeight {
            let overlap = bodyHeight - d
            if overlap < minOverlap { break } // too little left to trust
            var matches = 0
            var compared = 0
            var k = 0
            while k < overlap {
                // frame a, shifted down by d, should equal frame b at the top.
                if a[bodyTop + k + d] == b[bodyTop + k] { matches += 1 }
                compared += 1
                k += stride
            }
            // A real alignment matches almost everything in the overlap.
            if compared > 0, matches * 100 >= compared * 80, matches > bestScore {
                bestScore = matches
                bestDelta = d
            }
            d += 1
        }
        return bestDelta
    }

    // MARK: - Fallback

    /// No dedup — just pile the frames on top of one another. Used only when the
    /// clever path can't run (mismatched sizes, raster failure).
    private static func stackWhole(_ frames: [CGImage]) -> CGImage? {
        let width = frames.map(\.width).max() ?? 0
        let totalHeight = frames.reduce(0) { $0 + $1.height }
        guard width > 0, totalHeight > 0 else { return frames.first }
        guard let ctx = CGContext(
            data: nil, width: width, height: totalHeight,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return frames.first }
        var top = 0
        for frame in frames {
            let drawY = totalHeight - top - frame.height
            ctx.draw(frame, in: CGRect(x: 0, y: drawY, width: frame.width, height: frame.height))
            top += frame.height
        }
        return ctx.makeImage()
    }
}

private extension Array where Element == [UInt64] {
    /// Does row `y` read the same in every consecutive frame? (Used to find the
    /// parts of the screen that never move.)
    func allPairsMatchRow(_ y: Int) -> Bool {
        guard count > 1 else { return false }
        for i in 1..<count {
            guard self[i - 1].indices.contains(y), self[i].indices.contains(y) else { return false }
            if self[i - 1][y] != self[i][y] { return false }
        }
        return true
    }
}

/// A frame decoded into plain RGBA bytes so we can fingerprint each row. Rows
/// are addressed from the TOP (row 0 = top edge), hiding CoreGraphics' upside-
/// down buffer.
struct RasterImage {
    let width: Int
    let height: Int
    private let bytesPerRow: Int
    private let pixels: [UInt8]

    init?(_ cg: CGImage) {
        let w = cg.width
        let h = cg.height
        guard w > 0, h > 0 else { return nil }
        let bpr = w * 4
        var buffer = [UInt8](repeating: 0, count: bpr * h)
        let ok: Bool = buffer.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(
                data: raw.baseAddress, width: w, height: h,
                bitsPerComponent: 8, bytesPerRow: bpr,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard ok else { return nil }
        self.width = w
        self.height = h
        self.bytesPerRow = bpr
        self.pixels = buffer
    }

    /// One 64-bit fingerprint per row, top to bottom. Samples ~64 columns —
    /// enough to tell rows apart, cheap enough to run on every frame.
    func rowHashes() -> [UInt64] {
        let columns = 64
        let step = Swift.max(1, width / columns)
        var hashes = [UInt64](repeating: 0, count: height)
        pixels.withUnsafeBufferPointer { buf in
            for topY in 0..<height {
                // The buffer is bottom-up; flip so topY counts from the top edge.
                let bufferRow = height - 1 - topY
                let base = bufferRow * bytesPerRow
                var hash: UInt64 = 0xcbf29ce484222325
                var x = 0
                while x < width {
                    let p = base + x * 4
                    for c in 0..<4 {
                        hash = (hash ^ UInt64(buf[p + c])) &* 0x100000001b3
                    }
                    x += step
                }
                hashes[topY] = hash
            }
        }
        return hashes
    }

    /// A coarse whole-image fingerprint — used to tell "the page didn't move"
    /// from "it did" while scrolling.
    func quickHash() -> UInt64 {
        let rowStep = Swift.max(1, height / 80)
        let colStep = Swift.max(1, width / 40)
        var hash: UInt64 = 0xcbf29ce484222325
        pixels.withUnsafeBufferPointer { buf in
            var topY = 0
            while topY < height {
                let bufferRow = height - 1 - topY
                let base = bufferRow * bytesPerRow
                var x = 0
                while x < width {
                    let p = base + x * 4
                    hash = (hash ^ UInt64(buf[p])) &* 0x100000001b3
                    hash = (hash ^ UInt64(buf[p + 1])) &* 0x100000001b3
                    hash = (hash ^ UInt64(buf[p + 2])) &* 0x100000001b3
                    x += colStep
                }
                topY += rowStep
            }
        }
        return hash
    }
}
