import AppKit
import ImageIO

/// Makes and remembers small preview images for the library grid.
///
/// Loading a full-size PNG for every cell would make scrolling stutter, so we
/// shrink each shot down to roughly cell-size once, keep that copy in memory,
/// and hand the same small image back next time it's asked for. Think of it as
/// a contact sheet built lazily, one cell at a time.
@MainActor
final class ThumbnailCache: ObservableObject {
    private var cache: [String: NSImage] = [:]

    /// Returns the cached thumbnail, or builds one off the main thread. `key`
    /// should change whenever the file behind it changes (we fold in the byte
    /// size) so a replaced shot doesn't keep showing its old preview.
    func thumbnail(for url: URL, key: String, maxPixel: CGFloat) async -> NSImage? {
        if let hit = cache[key] { return hit }
        let image = await Task.detached(priority: .userInitiated) {
            Self.downsample(url: url, maxPixel: maxPixel)
        }.value
        if let image { cache[key] = image }
        return image
    }

    /// Drop a single entry — used after a shot is deleted or moved out.
    func forget(key: String) {
        cache[key] = nil
    }

    /// Reads just enough of the file to produce a shrunk-down image, never
    /// inflating the full thing into memory.
    nonisolated static func downsample(url: URL, maxPixel: CGFloat) -> NSImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else { return nil }

        let thumbOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ] as CFDictionary

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
}
