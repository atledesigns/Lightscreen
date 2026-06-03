import AppKit
import SwiftUI

/// A backdrop mood you can drop a screenshot into with one click. Built-in vibes
/// carry a fixed gradient (or, for Auto, a rule to sample from the image itself);
/// custom vibes are ones you've saved from your own tweaks.
struct Vibe: Identifiable, Equatable {
    enum Kind: Equatable { case auto, builtin, custom }

    let id: String
    var name: String
    let kind: Kind
    /// The colour that frames the thumbnail when this vibe is the active one.
    var accent: Color
    /// A small glyph tucked in the thumbnail corner (temporary art until Stage 13).
    var symbol: String
    /// Fixed gradient stops, or nil for Auto (which samples the live image).
    var color1: Color?
    var color2: Color?
    var angle: Double

    /// The two colours this vibe lands on for a given image. Auto samples; the
    /// rest just hand back their fixed stops.
    func resolvedColors(for image: NSImage) -> (Color, Color, Double) {
        if let c1 = color1, let c2 = color2 {
            return (c1, c2, angle)
        }
        let sampled = ColorSampler.dominantColors(image, count: 2)
        return (sampled.first ?? .blue, sampled.count > 1 ? sampled[1] : .purple, 135)
    }
}

/// The on-disk shape of a saved custom vibe. Colours are stored as plain numbers
/// because SwiftUI's `Color` isn't directly codable.
struct CustomVibe: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var c1: RGBA
    var c2: RGBA
    var angle: Double

    var asVibe: Vibe {
        Vibe(id: id, name: name, kind: .custom, accent: Color(.sRGB, red: 0.98, green: 0.62, blue: 0.20, opacity: 1),
             symbol: "star.fill", color1: c1.color, color2: c2.color, angle: angle)
    }
}

/// A colour as three sRGB numbers, 0–1. Just enough to round-trip a vibe.
struct RGBA: Codable, Equatable {
    var r: Double, g: Double, b: Double
    var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: 1) }
}

extension Color {
    /// This colour broken into sRGB components for saving.
    var rgbaComponents: RGBA {
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? NSColor(self)
        return RGBA(r: Double(ns.redComponent), g: Double(ns.greenComponent), b: Double(ns.blueComponent))
    }
}

/// Owns the vibe list: the locked built-ins plus whatever custom vibes you've
/// saved. Custom ones live in a small JSON file under Application Support and
/// survive quitting. Publishes changes so the editor strip updates live.
@MainActor
final class VibeStore: ObservableObject {
    @Published private(set) var custom: [CustomVibe] = []

    private let fileURL: URL

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let folder = support.appendingPathComponent("Lightscreen", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        fileURL = folder.appendingPathComponent("vibes.json")
        load()
    }

    /// The locked built-in vibes, in strip order (Auto first).
    let builtins: [Vibe] = [
        Vibe(id: "auto", name: "Auto", kind: .auto,
             accent: .accentColor, symbol: "sparkles",
             color1: nil, color2: nil, angle: 135),
        Vibe(id: "grass", name: "Grass", kind: .builtin,
             accent: .green, symbol: "leaf.fill",
             color1: Color(.sRGB, red: 0.18, green: 0.49, blue: 0.20, opacity: 1),
             color2: Color(.sRGB, red: 0.66, green: 0.84, blue: 0.55, opacity: 1), angle: 135),
        Vibe(id: "electric", name: "Electric", kind: .builtin,
             accent: .yellow, symbol: "bolt.fill",
             color1: Color(.sRGB, red: 0.98, green: 0.85, blue: 0.10, opacity: 1),
             color2: Color(.sRGB, red: 0.05, green: 0.08, blue: 0.22, opacity: 1), angle: 120),
        Vibe(id: "psychic", name: "Psychic", kind: .builtin,
             accent: .purple, symbol: "moon.stars.fill",
             color1: Color(.sRGB, red: 0.55, green: 0.25, blue: 0.85, opacity: 1),
             color2: Color(.sRGB, red: 0.96, green: 0.46, blue: 0.80, opacity: 1), angle: 135),
        Vibe(id: "fairy", name: "Fairy", kind: .builtin,
             accent: .pink, symbol: "wand.and.stars",
             color1: Color(.sRGB, red: 0.98, green: 0.78, blue: 0.86, opacity: 1),
             color2: Color(.sRGB, red: 0.99, green: 0.95, blue: 0.86, opacity: 1), angle: 110),
        Vibe(id: "steel", name: "Steel", kind: .builtin,
             accent: Color(white: 0.72), symbol: "gearshape.fill",
             color1: Color(.sRGB, red: 0.45, green: 0.48, blue: 0.52, opacity: 1),
             color2: Color(.sRGB, red: 0.80, green: 0.84, blue: 0.88, opacity: 1), angle: 145),
    ]

    /// Built-ins followed by your saved custom vibes — the full strip.
    var all: [Vibe] { builtins + custom.map(\.asVibe) }

    // MARK: - Editing custom vibes

    /// Save the current background as a new custom vibe.
    func add(name: String, color1: Color, color2: Color, angle: Double) {
        let clean = name.trimmingCharacters(in: .whitespaces)
        let vibe = CustomVibe(
            id: "custom-\(UUID().uuidString)",
            name: clean.isEmpty ? "My vibe" : clean,
            c1: color1.rgbaComponents, c2: color2.rgbaComponents, angle: angle
        )
        custom.append(vibe)
        save()
    }

    func rename(id: String, to newName: String) {
        guard let index = custom.firstIndex(where: { $0.id == id }) else { return }
        let clean = newName.trimmingCharacters(in: .whitespaces)
        guard !clean.isEmpty else { return }
        custom[index].name = clean
        save()
    }

    func delete(id: String) {
        custom.removeAll { $0.id == id }
        save()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([CustomVibe].self, from: data) else { return }
        custom = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(custom) else { return }
        try? data.write(to: fileURL)
    }
}
