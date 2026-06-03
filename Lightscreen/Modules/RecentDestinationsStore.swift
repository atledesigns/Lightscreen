import Foundation

/// Remembers the last few folders the user saved a shot into, so the "Where"
/// dropdown can offer them as quick picks. Most-recent first, capped at five.
final class RecentDestinationsStore {
    private static let key = "recent_destinations"
    private static let limit = 5

    func recents() -> [URL] {
        let paths = UserDefaults.standard.array(forKey: Self.key) as? [String] ?? []
        return paths.map { URL(fileURLWithPath: $0) }
    }

    func remember(_ folder: URL) {
        var paths = UserDefaults.standard.array(forKey: Self.key) as? [String] ?? []
        paths.removeAll { $0 == folder.path }
        paths.insert(folder.path, at: 0)
        if paths.count > Self.limit { paths = Array(paths.prefix(Self.limit)) }
        UserDefaults.standard.set(paths, forKey: Self.key)
    }
}
