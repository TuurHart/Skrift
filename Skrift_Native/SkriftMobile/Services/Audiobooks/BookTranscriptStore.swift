import Foundation

/// On-disk home for the per-book, per-file transcript sidecars (wave-2
/// text-capture). One JSON per audio file: `Documents/audiobooks/<id>/transcript_f<n>.json`.
///
/// A plain `Sendable` value doing SYNCHRONOUS, ATOMIC file I/O — no actor, so the
/// background transcribe job and the main-actor capture screen can both touch it
/// without hops. Atomicity (write-temp-then-replace) is the contract the design
/// leans on: a capture reading mid-job sees either the previous complete sidecar
/// or the new one, never a torn half-chunk (design §13).
struct BookTranscriptStore: Sendable {
    /// The audiobooks root (`Documents/audiobooks`), same as `AudiobookLibraryStore.directory`.
    let directory: URL

    init(directory: URL = AppPaths.documentsDirectory.appendingPathComponent("audiobooks", isDirectory: true)) {
        self.directory = directory
    }

    // MARK: - Paths

    func folder(forBookID id: UUID) -> URL {
        directory.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    func sidecarURL(bookID: UUID, fileIndex: Int) -> URL {
        folder(forBookID: bookID).appendingPathComponent("transcript_f\(fileIndex).json")
    }

    // MARK: - Staleness key

    /// `"<size>:<mtime>"` for the audio file — the staleness key stored in the
    /// sidecar. A re-import (new bytes → new size/mtime) invalidates the
    /// transcript so we never serve a stale one. Empty when the file is missing.
    func signature(forFileAt url: URL) -> String {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) else { return "" }
        let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        let mtime = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        return "\(size):\(Int(mtime))"
    }

    // MARK: - Frontier cache (cheap reads)

    /// Process-wide (signature, frontier, word count) per sidecar, primed by
    /// `load`/`save`. Lets the ~2Hz read-along tick and the per-chunk progress
    /// publish ask "how far is this file transcribed?" without decoding the
    /// whole word array every time. NSCache — thread-safe across the background
    /// job and the main-actor players.
    private final class Frontier: NSObject {
        let signature: String
        let covered: TimeInterval
        let wordCount: Int
        init(signature: String, covered: TimeInterval, wordCount: Int) {
            self.signature = signature; self.covered = covered; self.wordCount = wordCount
        }
    }
    private static let frontierCache = NSCache<NSString, Frontier>()
    private static func frontierKey(_ id: UUID, _ fileIndex: Int) -> NSString {
        "\(id.uuidString):\(fileIndex)" as NSString
    }
    private static func prime(_ ft: FileTranscript, bookID: UUID) {
        frontierCache.setObject(
            Frontier(signature: ft.signature, covered: ft.coveredUpTo, wordCount: ft.words.count),
            forKey: frontierKey(bookID, ft.fileIndex))
    }

    /// Covered-up-to seconds for one file (0 when absent/stale) — cache-served;
    /// one full decode primes a cold entry.
    func coveredUpTo(bookID: UUID, fileIndex: Int, expectedSignature: String) -> TimeInterval {
        frontier(bookID: bookID, fileIndex: fileIndex, expectedSignature: expectedSignature)?.covered ?? 0
    }

    /// Frontier + word count without the full decode on the cached path — the
    /// cloud-sync change signature reads exactly these two scalars.
    func frontierStats(bookID: UUID, fileIndex: Int,
                       expectedSignature: String) -> (covered: TimeInterval, wordCount: Int)? {
        guard let f = frontier(bookID: bookID, fileIndex: fileIndex,
                               expectedSignature: expectedSignature) else { return nil }
        return (f.covered, f.wordCount)
    }

    private func frontier(bookID: UUID, fileIndex: Int, expectedSignature: String) -> Frontier? {
        if let hit = Self.frontierCache.object(forKey: Self.frontierKey(bookID, fileIndex)),
           hit.signature == expectedSignature { return hit }
        guard let ft = load(bookID: bookID, fileIndex: fileIndex,
                            expectedSignature: expectedSignature) else { return nil }
        return Frontier(signature: ft.signature, covered: ft.coveredUpTo, wordCount: ft.words.count)
    }

    // MARK: - Load / save

    /// Load the sidecar for one file. Returns nil when missing, unreadable, of an
    /// old schema, or STALE (the audio's current signature differs from the one
    /// stored) — the caller then treats the file as un-transcribed.
    func load(bookID: UUID, fileIndex: Int, expectedSignature: String) -> FileTranscript? {
        let url = sidecarURL(bookID: bookID, fileIndex: fileIndex)
        guard let data = try? Data(contentsOf: url),
              let ft = try? JSONDecoder().decode(FileTranscript.self, from: data),
              ft.schema == FileTranscript.currentSchema,
              ft.signature == expectedSignature
        else { return nil }
        Self.prime(ft, bookID: bookID)
        return ft
    }

    /// Atomically persist one file's transcript (write temp → replace), creating
    /// the book folder if needed. Throwing so the job can react to a disk-full /
    /// permission failure rather than silently losing the frontier.
    func save(_ ft: FileTranscript, bookID: UUID) throws {
        let folder = folder(forBookID: bookID)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(ft)
        try data.write(to: sidecarURL(bookID: bookID, fileIndex: ft.fileIndex), options: .atomic)
        Self.prime(ft, bookID: bookID)
    }

    /// The freshest (staleness-checked) file transcript, or nil. Used by the
    /// player's read-along to query both coverage and the words around the playhead.
    func fileTranscript(bookID: UUID, fileIndex: Int, audioURL: URL) -> FileTranscript? {
        load(bookID: bookID, fileIndex: fileIndex, expectedSignature: signature(forFileAt: audioURL))
    }

    // MARK: - Capture read

    /// Words in `[start, end]` (FILE-LOCAL) IF the sidecar fully covers the window
    /// (`coveredUpTo ≥ end`), else nil → the caller falls back to a live window
    /// transcribe. Staleness-checked. This is the "instant capture" read — no
    /// engine, no contention.
    func coveredWindowWords(bookID: UUID, fileIndex: Int, audioURL: URL,
                            start: TimeInterval, end: TimeInterval) -> [WordTiming]? {
        let sig = signature(forFileAt: audioURL)
        guard let ft = load(bookID: bookID, fileIndex: fileIndex, expectedSignature: sig),
              ft.isCovered(upTo: end) else { return nil }
        return ft.words(inWindow: start, end: end)
    }

    // MARK: - Cleanup

    /// Remove every transcript sidecar for a book (called when the book is
    /// deleted, alongside `AudiobookLibraryStore.remove`). The per-file naming
    /// lets us sweep the folder without knowing the file count.
    func removeTranscripts(forBookID id: UUID) {
        let folder = folder(forBookID: id)
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: nil) else { return }
        for url in entries where url.lastPathComponent.hasPrefix("transcript_f") {
            try? FileManager.default.removeItem(at: url)
            // Drop the frontier entry too — the AUDIO signature is unchanged, so
            // a stale cache hit would otherwise keep answering "covered".
            if let n = Int(url.deletingPathExtension().lastPathComponent.dropFirst("transcript_f".count)) {
                Self.frontierCache.removeObject(forKey: Self.frontierKey(id, n))
            }
        }
    }
}
