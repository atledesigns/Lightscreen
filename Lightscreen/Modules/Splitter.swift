import CoreGraphics

/// Cuts a tall image into stacked panels — the way you'd break a long scrolling
/// screenshot into a few square-ish cards for a thread. Pure: an image and where
/// to cut it in, an array of pieces out (top to bottom).
enum Splitter {

    /// Even cut positions for `count` panels, as fractions down from the top.
    /// Three panels → cuts at 1/3 and 2/3.
    static func evenFractions(_ count: Int) -> [Double] {
        guard count > 1 else { return [] }
        return (1..<count).map { Double($0) / Double(count) }
    }

    /// Slice `image` at the given fractions (each 0–1, measured from the top).
    /// Returns the panels in order. Fractions are sorted and clamped, and any
    /// zero-height sliver is skipped.
    static func split(_ image: CGImage, atFractions fractions: [Double]) -> [CGImage] {
        let height = image.height
        let width = image.width
        guard height > 0, width > 0 else { return [] }

        // Boundaries: top edge, the interior cuts, bottom edge — in pixel rows.
        let interior = fractions
            .map { min(max($0, 0), 1) }
            .sorted()
            .map { Int((Double(height) * $0).rounded()) }
        let bounds = [0] + interior + [height]

        var panels: [CGImage] = []
        for i in 0..<(bounds.count - 1) {
            let y0 = bounds[i]
            let y1 = bounds[i + 1]
            let h = y1 - y0
            guard h > 0 else { continue }
            // CGImage cropping measures y from the top, which is exactly how our
            // fractions are defined, so no flip is needed here.
            if let panel = image.cropping(to: CGRect(x: 0, y: y0, width: width, height: h)) {
                panels.append(panel)
            }
        }
        return panels
    }
}
