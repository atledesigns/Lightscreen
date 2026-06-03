import Foundation
import SQLite3

/// One saved shot: the image file on disk plus the facts we remember about it.
struct Capture: Identifiable, Equatable {
    var id: Int64
    var filename: String          // display name, user-editable
    var relativePath: String      // under the captures folder
    var capturedAt: Date
    var captureMode: String       // region | window | scrolling
    var outputMode: String        // raw | beautified
    var sourceAppBundleID: String?
    var fileSizeBytes: Int64
}

/// How the library buckets shots in the grid. Computed fresh each time we read,
/// so a shot slides from "Today" to "Yesterday" on its own as time passes.
enum DateGroup: String, CaseIterable {
    case today = "Today"
    case yesterday = "Yesterday"
    case earlierThisWeek = "Earlier this week"
    case lastWeek = "Last week"
    case earlier = "Earlier"
}

/// Owns the on-disk capture library: the image files and the little index that
/// lists them. Everything lives under Application Support and never leaves the Mac.
final class LibraryStore {
    /// `~/Library/Application Support/Lightscreen/`
    let baseURL: URL
    /// `…/Lightscreen/captures/` — where the PNGs live.
    let capturesURL: URL

    private var db: OpaquePointer?
    // SQLite needs this when handing it text it must copy rather than borrow.
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        baseURL = support.appendingPathComponent("Lightscreen", isDirectory: true)
        capturesURL = baseURL.appendingPathComponent("captures", isDirectory: true)

        try? FileManager.default.createDirectory(at: capturesURL, withIntermediateDirectories: true)
        openDatabase()
        createSchema()
    }

    deinit {
        if let db { sqlite3_close(db) }
    }

    // MARK: - Saving a fresh capture

    /// Writes PNG bytes to disk under a Finder-style name and records the row.
    /// Returns the stored capture (with its new id) so callers can preview it.
    @discardableResult
    func save(
        pngData: Data,
        captureMode: String,
        outputMode: String,
        sourceAppBundleID: String?,
        capturedAt: Date = Date()
    ) throws -> Capture {
        let filename = uniqueFilename(for: capturedAt)
        let fileURL = capturesURL.appendingPathComponent(filename)
        try pngData.write(to: fileURL)

        let relativePath = "captures/\(filename)"
        let capture = Capture(
            id: 0,
            filename: filename,
            relativePath: relativePath,
            capturedAt: capturedAt,
            captureMode: captureMode,
            outputMode: outputMode,
            sourceAppBundleID: sourceAppBundleID,
            fileSizeBytes: Int64(pngData.count)
        )
        let id = try insert(capture)
        return capture.with(id: id)
    }

    /// Save into the library under a chosen display name, with optional Finder
    /// tags. Used by the save popover (the silent auto-save uses `save` above).
    @discardableResult
    func saveToLibrary(
        data: Data,
        name: String,
        tags: [String],
        captureMode: String,
        outputMode: String,
        sourceAppBundleID: String?,
        capturedAt: Date = Date()
    ) throws -> Capture {
        let url = uniqueURL(in: capturesURL, baseName: name)
        try data.write(to: url)
        applyTags(tags, to: url)

        let filename = url.lastPathComponent
        let capture = Capture(
            id: 0,
            filename: filename,
            relativePath: "captures/\(filename)",
            capturedAt: capturedAt,
            captureMode: captureMode,
            outputMode: outputMode,
            sourceAppBundleID: sourceAppBundleID,
            fileSizeBytes: Int64(data.count)
        )
        let id = try insert(capture)
        return capture.with(id: id)
    }

    /// Save to a folder anywhere on disk (a "Where" pick that isn't the library).
    /// The shot leaves the library, so no index row is written.
    @discardableResult
    func saveToFolder(data: Data, folder: URL, name: String, tags: [String]) throws -> URL {
        let url = uniqueURL(in: folder, baseName: name)
        try data.write(to: url)
        applyTags(tags, to: url)
        return url
    }

    /// The default display name for a shot taken now, e.g.
    /// "Screenshot 2026-06-02 at 19.00.06.png". Uniqueness is settled at save time.
    static func suggestedFilename(for date: Date = Date()) -> String {
        "Screenshot \(fileStamp.string(from: date)).png"
    }

    // MARK: - CRUD

    @discardableResult
    func insert(_ capture: Capture) throws -> Int64 {
        let sql = """
        INSERT INTO captures
        (filename, relative_path, captured_at, capture_mode, output_mode, source_app_bundle_id, file_size_bytes)
        VALUES (?, ?, ?, ?, ?, ?, ?);
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { throw error("prepare insert") }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, capture.filename, -1, transient)
        sqlite3_bind_text(stmt, 2, capture.relativePath, -1, transient)
        sqlite3_bind_text(stmt, 3, Self.iso.string(from: capture.capturedAt), -1, transient)
        sqlite3_bind_text(stmt, 4, capture.captureMode, -1, transient)
        sqlite3_bind_text(stmt, 5, capture.outputMode, -1, transient)
        if let bundle = capture.sourceAppBundleID {
            sqlite3_bind_text(stmt, 6, bundle, -1, transient)
        } else {
            sqlite3_bind_null(stmt, 6)
        }
        sqlite3_bind_int64(stmt, 7, capture.fileSizeBytes)

        guard sqlite3_step(stmt) == SQLITE_DONE else { throw error("insert") }
        return sqlite3_last_insert_rowid(db)
    }

    func fetchAll() -> [Capture] {
        let sql = "SELECT id, filename, relative_path, captured_at, capture_mode, output_mode, source_app_bundle_id, file_size_bytes FROM captures ORDER BY captured_at DESC;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        var result: [Capture] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            result.append(row(from: stmt))
        }
        return result
    }

    /// All shots, bucketed into ordered date groups for the library grid.
    func fetchByDateGroup(now: Date = Date()) -> [(group: DateGroup, captures: [Capture])] {
        let all = fetchAll()
        var buckets: [DateGroup: [Capture]] = [:]
        for capture in all {
            buckets[Self.group(for: capture.capturedAt, now: now), default: []].append(capture)
        }
        return DateGroup.allCases.compactMap { group in
            guard let captures = buckets[group], !captures.isEmpty else { return nil }
            return (group, captures)
        }
    }

    func delete(id: Int64) throws {
        let sql = "DELETE FROM captures WHERE id = ?;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { throw error("prepare delete") }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, id)
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw error("delete") }
    }

    /// Moves a capture's file to a new location and updates its recorded path.
    func move(id: Int64, toPath newRelativePath: String) throws {
        let sql = "UPDATE captures SET relative_path = ?, filename = ? WHERE id = ?;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { throw error("prepare move") }
        defer { sqlite3_finalize(stmt) }
        let filename = (newRelativePath as NSString).lastPathComponent
        sqlite3_bind_text(stmt, 1, newRelativePath, -1, transient)
        sqlite3_bind_text(stmt, 2, filename, -1, transient)
        sqlite3_bind_int64(stmt, 3, id)
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw error("move") }
    }

    // MARK: - Library window helpers

    /// Where a capture's PNG actually lives on disk. `relativePath` already
    /// carries the `captures/…` prefix, so this hangs off the base folder.
    func fileURL(for capture: Capture) -> URL {
        baseURL.appendingPathComponent(capture.relativePath)
    }

    /// Throws the shot away for good: removes the PNG from disk and forgets the
    /// row. Used by the library's Delete action (no undo in v1).
    func deleteWithFile(_ capture: Capture) throws {
        try? FileManager.default.removeItem(at: fileURL(for: capture))
        try delete(id: capture.id)
    }

    /// Moves a shot out to a folder somewhere else on the Mac. It leaves the
    /// library (the index row is dropped), mirroring "Save to a folder". Returns
    /// where it landed.
    @discardableResult
    func moveOut(_ capture: Capture, to folder: URL) throws -> URL {
        let destination = uniqueURL(in: folder, baseName: (capture.filename as NSString).deletingPathExtension)
        try FileManager.default.moveItem(at: fileURL(for: capture), to: destination)
        try delete(id: capture.id)
        return destination
    }

    // MARK: - Setup

    private func openDatabase() {
        let dbURL = baseURL.appendingPathComponent("captures.db")
        if sqlite3_open(dbURL.path, &db) != SQLITE_OK {
            NSLog("Lightscreen: could not open library index at \(dbURL.path)")
        }
    }

    private func createSchema() {
        let sql = """
        CREATE TABLE IF NOT EXISTS captures (
            id                    INTEGER PRIMARY KEY,
            filename              TEXT NOT NULL,
            relative_path         TEXT NOT NULL UNIQUE,
            captured_at           TEXT NOT NULL,
            capture_mode          TEXT NOT NULL,
            output_mode           TEXT NOT NULL,
            source_app_bundle_id  TEXT,
            file_size_bytes       INTEGER NOT NULL
        );
        CREATE TABLE IF NOT EXISTS settings (
            key   TEXT PRIMARY KEY,
            value TEXT NOT NULL
        );
        """
        if sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK {
            NSLog("Lightscreen: could not create library schema — \(lastMessage)")
        }
    }

    // MARK: - Helpers

    private func row(from stmt: OpaquePointer?) -> Capture {
        func text(_ col: Int32) -> String {
            guard let c = sqlite3_column_text(stmt, col) else { return "" }
            return String(cString: c)
        }
        func optionalText(_ col: Int32) -> String? {
            guard sqlite3_column_type(stmt, col) != SQLITE_NULL,
                  let c = sqlite3_column_text(stmt, col) else { return nil }
            return String(cString: c)
        }
        return Capture(
            id: sqlite3_column_int64(stmt, 0),
            filename: text(1),
            relativePath: text(2),
            capturedAt: Self.iso.date(from: text(3)) ?? Date(),
            captureMode: text(4),
            outputMode: text(5),
            sourceAppBundleID: optionalText(6),
            fileSizeBytes: sqlite3_column_int64(stmt, 7)
        )
    }

    /// `Screenshot 2026-06-02 at 14.30.05.png`, nudged with a counter if that
    /// exact second already produced a file.
    private func uniqueFilename(for date: Date) -> String {
        let base = "Screenshot \(Self.fileStamp.string(from: date))"
        var candidate = "\(base).png"
        var n = 2
        while FileManager.default.fileExists(atPath: capturesURL.appendingPathComponent(candidate).path) {
            candidate = "\(base) (\(n)).png"
            n += 1
        }
        return candidate
    }

    /// Picks a `.png` URL in `dir` based on `baseName`, adding a counter only if
    /// something with that exact name is already there.
    private func uniqueURL(in dir: URL, baseName: String) -> URL {
        var name = baseName.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { name = "Screenshot" }
        let base = (name as NSString).pathExtension.lowercased() == "png"
            ? (name as NSString).deletingPathExtension
            : name
        var candidate = "\(base).png"
        var n = 2
        while FileManager.default.fileExists(atPath: dir.appendingPathComponent(candidate).path) {
            candidate = "\(base) (\(n)).png"
            n += 1
        }
        return dir.appendingPathComponent(candidate)
    }

    /// Attaches Finder colour/label tags to a file (the same tags you'd set in
    /// Finder's Get Info). Empty entries are ignored.
    private func applyTags(_ tags: [String], to url: URL) {
        let clean = tags
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !clean.isEmpty else { return }
        try? (url as NSURL).setResourceValue(clean, forKey: .tagNamesKey)
    }

    private var lastMessage: String {
        guard let db, let msg = sqlite3_errmsg(db) else { return "unknown error" }
        return String(cString: msg)
    }

    private func error(_ stage: String) -> NSError {
        NSError(domain: "Lightscreen.LibraryStore", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "\(stage) failed: \(lastMessage)"])
    }

    /// Which date bucket a shot falls into right now. Exposed so the library
    /// window can re-group its own filtered/sorted list without re-reading disk.
    static func group(for date: Date, now: Date = Date()) -> DateGroup {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return .today }
        if cal.isDateInYesterday(date) { return .yesterday }
        let startOfThisWeek = cal.dateInterval(of: .weekOfYear, for: now)?.start
        if let start = startOfThisWeek, date >= start { return .earlierThisWeek }
        if let start = startOfThisWeek,
           let lastWeekStart = cal.date(byAdding: .weekOfYear, value: -1, to: start),
           date >= lastWeekStart { return .lastWeek }
        return .earlier
    }

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let fileStamp: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return f
    }()
}

private extension Capture {
    func with(id newID: Int64) -> Capture {
        var copy = self
        copy.id = newID
        return copy
    }
}
