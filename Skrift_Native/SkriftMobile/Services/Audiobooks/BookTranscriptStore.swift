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
        }
    }
}
