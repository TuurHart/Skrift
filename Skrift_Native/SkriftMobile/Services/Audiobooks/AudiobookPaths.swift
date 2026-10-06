import Foundation

/// The ONE owner of where audiobook files live and of the two file reads every audiobook store
/// shares. Layout: `Documents/audiobooks/<bookID>/…` (audio, `cover.jpg`, `transcript_f<n>.json`,
/// `alignment_f<n>.json`, `bookmarks.json`, attached texts). The stores keep an injectable root
/// (tests pass a temp directory) and take this as their default.
enum AudiobookPaths {
    /// `Documents/audiobooks`.
    static var root: URL {
        AppPaths.documentsDirectory.appendingPathComponent("audiobooks", isDirectory: true)
    }

    /// One book's folder under `root` (or an injected root).
    static func folder(for id: UUID, in root: URL = AudiobookPaths.root) -> URL {
        root.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    /// Byte size of the file at `url`; nil when it is missing or unreadable.
    static func fileSize(at url: URL) -> Int64? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) else { return nil }
        return (attrs[.size] as? NSNumber)?.int64Value ?? 0
    }

    /// `"<size>:<mtime>"` of the file at `url` — the staleness/cache key for audio files and
    /// sidecars alike. Empty when the file is missing.
    static func signature(forFileAt url: URL) -> String {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) else { return "" }
        let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        let mtime = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        return "\(size):\(Int(mtime))"
    }
}
