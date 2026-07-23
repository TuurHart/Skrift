import Foundation

/// A lightweight position bookmark in an audiobook (player redesign 2026-06-13).
/// Deliberately MINIMAL — just a spot to jump back to. Anything richer (the
/// quote text + your voice) is what `Capture` is for; bookmarks don't duplicate
/// that. Stored per book in the book's folder (`bookmarks.json`).
struct AudiobookBookmark: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    /// GLOBAL book time (across all files), seconds.
    var position: TimeInterval
    /// Display chapter label at that spot ("ch. 3 — Beginning"), nil without chapters.
    var chapterLabel: String?
    var createdAt: Date

    init(id: UUID = UUID(), position: TimeInterval, chapterLabel: String? = nil, createdAt: Date = Date()) {
        self.id = id
        self.position = max(0, position)
        self.chapterLabel = chapterLabel
        self.createdAt = createdAt
    }
}

/// On-disk store for per-book bookmarks. A plain `Sendable` value doing
/// synchronous atomic file I/O, same shape as `BookTranscriptStore` — the player
/// adds one (and shows a toast); the chapters/bookmarks sheet reads the list on
/// open. One JSON per book: `Documents/audiobooks/<id>/bookmarks.json`.
struct BookmarkStore: Sendable {
    /// Two bookmarks closer than this (seconds) are treated as the same spot —
    /// guards an accidental double-tap on the Bookmark button.
    static let dedupeWindow: TimeInterval = 2

    let directory: URL

    init(directory: URL = AppPaths.documentsDirectory.appendingPathComponent("audiobooks", isDirectory: true)) {
        self.directory = directory
    }

    private func folder(forBookID id: UUID) -> URL {
        directory.appendingPathComponent(id.uuidString, isDirectory: true)
    }
    func fileURL(bookID: UUID) -> URL {
        folder(forBookID: bookID).appendingPathComponent("bookmarks.json")
    }

    /// All bookmarks for a book, sorted by position. Empty when none / unreadable.
    func load(bookID: UUID) -> [AudiobookBookmark] {
        guard let data = try? Data(contentsOf: fileURL(bookID: bookID)),
              let list = try? JSONDecoder().decode([AudiobookBookmark].self, from: data) else { return [] }
        return list.sorted { $0.position < $1.position }
    }

    /// Add `bookmark` unless one already sits within `dedupeWindow` of it; returns
    /// the new sorted list. Pure-ish (one read + one atomic write). A real change
    /// stamps the LWW clock (bookmark sync).
    @discardableResult
    func add(_ bookmark: AudiobookBookmark, bookID: UUID) -> [AudiobookBookmark] {
        var list = load(bookID: bookID)
        guard !list.contains(where: { abs($0.position - bookmark.position) < Self.dedupeWindow }) else {
            return list
        }
        list.append(bookmark)
        list.sort { $0.position < $1.position }
        try? save(list, bookID: bookID)
        markEdited(bookID: bookID)
        return list
    }

    @discardableResult
    func remove(id: UUID, bookID: UUID) -> [AudiobookBookmark] {
        let before = load(bookID: bookID)
        let list = before.filter { $0.id != id }
        try? save(list, bookID: bookID)
        if list.count != before.count { markEdited(bookID: bookID) }
        return list
    }

    func save(_ list: [AudiobookBookmark], bookID: UUID) throws {
        let folder = folder(forBookID: bookID)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(list)
        try data.write(to: fileURL(bookID: bookID), options: .atomic)
    }

    // ── LWW stamp (bookmark sync, 2026-07-23): a sidecar date, NOT file mtime —
    //    adopting a synced list must copy the carrier's stamp verbatim, never
    //    mint "now" (mtime-as-stamp ping-pongs two devices forever). ──

    func stampURL(bookID: UUID) -> URL {
        folder(forBookID: bookID).appendingPathComponent("bookmarks.stamp")
    }

    /// `.distantPast` = never edited on this device (the sync core's fresh-device guard).
    func modifiedAt(bookID: UUID) -> Date {
        guard let text = try? String(contentsOf: stampURL(bookID: bookID), encoding: .utf8),
              let interval = TimeInterval(text.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return .distantPast
        }
        return Date(timeIntervalSince1970: interval)
    }

    /// A USER edit happened now.
    func markEdited(bookID: UUID, now: Date = Date()) {
        try? FileManager.default.createDirectory(at: folder(forBookID: bookID), withIntermediateDirectories: true)
        try? "\(now.timeIntervalSince1970)".write(to: stampURL(bookID: bookID), atomically: true, encoding: .utf8)
    }

    /// Adopt a synced list + its carrier stamp (LWW discipline — no new stamp).
    func adoptSynced(_ list: [AudiobookBookmark], stamp: Date, bookID: UUID) {
        try? save(list, bookID: bookID)
        try? "\(stamp.timeIntervalSince1970)".write(to: stampURL(bookID: bookID), atomically: true, encoding: .utf8)
    }
}
