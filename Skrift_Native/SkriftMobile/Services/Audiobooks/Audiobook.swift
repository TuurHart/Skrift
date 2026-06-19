import Foundation

/// One embedded chapter (from the file's m4b/m4a chapter track).
struct AudiobookChapter: Codable, Equatable, Sendable {
    var title: String
    var start: TimeInterval
    var duration: TimeInterval
}

/// An imported audiobook. The audio lives in `Documents/audiobooks/<id>/`
/// (cover art beside it as `cover.jpg`); this record + the playback progress
/// persist in the library's `library.json`. Book files NEVER sync to the Mac —
/// only capture memos do.
///
/// A book is one or more ORDERED audio files: a single .m4b, or a
/// file-per-chapter folder of mp3s imported together (Bound-style). Times are
/// GLOBAL across the whole book — `files`/`fileDurations` map a global time to
/// the file holding it. Legacy single-file records (pre-multi-file) decode
/// their `audioFilename` into a one-entry `files` list (see `init(from:)`).
struct Audiobook: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    /// Ordered audio filenames inside the book's folder (original extensions
    /// preserved). Exactly one entry for a single-file book.
    var files: [String]
    /// Per-file durations in seconds, same order as `files`; `duration` is
    /// their sum.
    var fileDurations: [TimeInterval]
    var title: String
    var author: String
    var duration: TimeInterval
    var chapters: [AudiobookChapter]
    var hasCover: Bool
    var importedAt: Date
    /// nil until first played — drives the "recently played" sort.
    var lastPlayedAt: Date?
    /// Per-book resume position (GLOBAL seconds across all files).
    var position: TimeInterval
    /// Per-book playback speed (Bound keeps speed per book too).
    var playbackRate: Double
    /// Last time ANY synced field changed (position, rate, …) — the cross-device LWW
    /// key. Distinct from `lastPlayedAt` (which is purely the "recently played" sort),
    /// so a speed change with no playback still syncs without reordering the library.
    var modifiedAt: Date

    /// Legacy convenience: the first (for single-file books, only) file.
    var audioFilename: String { files.first ?? "" }

    init(
        id: UUID = UUID(),
        files: [String],
        fileDurations: [TimeInterval],
        title: String,
        author: String,
        duration: TimeInterval = 0,
        chapters: [AudiobookChapter] = [],
        hasCover: Bool = false,
        importedAt: Date = Date(),
        lastPlayedAt: Date? = nil,
        position: TimeInterval = 0,
        playbackRate: Double = 1.0,
        modifiedAt: Date = Date()
    ) {
        self.id = id
        self.files = files
        self.fileDurations = fileDurations
        self.title = title
        self.author = author
        self.duration = duration
        self.chapters = chapters
        self.hasCover = hasCover
        self.importedAt = importedAt
        self.lastPlayedAt = lastPlayedAt
        self.position = position
        self.playbackRate = playbackRate
        self.modifiedAt = modifiedAt
    }

    /// Single-file convenience (the pre-multi-file shape; tests + the .m4b
    /// import path use it).
    init(
        id: UUID = UUID(),
        audioFilename: String,
        title: String,
        author: String,
        duration: TimeInterval = 0,
        chapters: [AudiobookChapter] = [],
        hasCover: Bool = false,
        importedAt: Date = Date(),
        lastPlayedAt: Date? = nil,
        position: TimeInterval = 0,
        playbackRate: Double = 1.0,
        modifiedAt: Date = Date()
    ) {
        self.init(
            id: id,
            files: audioFilename.isEmpty ? [] : [audioFilename],
            fileDurations: audioFilename.isEmpty ? [] : [duration],
            title: title,
            author: author,
            duration: duration,
            chapters: chapters,
            hasCover: hasCover,
            importedAt: importedAt,
            lastPlayedAt: lastPlayedAt,
            position: position,
            playbackRate: playbackRate,
            modifiedAt: modifiedAt
        )
    }

    // MARK: - Codable (additive migration)

    private enum CodingKeys: String, CodingKey {
        case id, files, fileDurations, audioFilename, title, author, duration
        case chapters, hasCover, importedAt, lastPlayedAt, position, playbackRate, modifiedAt
    }

    /// Decodes both shapes: new records carry `files` + `fileDurations`;
    /// legacy records carry a single `audioFilename` (migrated to a one-entry
    /// list with `[duration]`). A mismatched `fileDurations` (shouldn't
    /// happen) is repaired by spreading `duration` evenly.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        author = try c.decode(String.self, forKey: .author)
        duration = try c.decode(TimeInterval.self, forKey: .duration)
        chapters = try c.decode([AudiobookChapter].self, forKey: .chapters)
        hasCover = try c.decode(Bool.self, forKey: .hasCover)
        importedAt = try c.decode(Date.self, forKey: .importedAt)
        lastPlayedAt = try c.decodeIfPresent(Date.self, forKey: .lastPlayedAt)
        position = try c.decode(TimeInterval.self, forKey: .position)
        playbackRate = try c.decode(Double.self, forKey: .playbackRate)
        // Additive (pre-modifiedAt records): fall back to lastPlayedAt, else importedAt.
        modifiedAt = try c.decodeIfPresent(Date.self, forKey: .modifiedAt) ?? (lastPlayedAt ?? importedAt)

        if let multi = try c.decodeIfPresent([String].self, forKey: .files), !multi.isEmpty {
            files = multi
            let durations = try c.decodeIfPresent([TimeInterval].self, forKey: .fileDurations) ?? []
            fileDurations = durations.count == multi.count
                ? durations
                : Array(repeating: duration / Double(multi.count), count: multi.count)
        } else {
            // Pre-multi-file record: one file, the whole duration.
            let legacy = try c.decodeIfPresent(String.self, forKey: .audioFilename) ?? ""
            files = legacy.isEmpty ? [] : [legacy]
            fileDurations = legacy.isEmpty ? [] : [duration]
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(files, forKey: .files)
        try c.encode(fileDurations, forKey: .fileDurations)
        // Keep writing the legacy key so an older build reading this
        // library.json still finds (the first file of) the book.
        try c.encode(audioFilename, forKey: .audioFilename)
        try c.encode(title, forKey: .title)
        try c.encode(author, forKey: .author)
        try c.encode(duration, forKey: .duration)
        try c.encode(chapters, forKey: .chapters)
        try c.encode(hasCover, forKey: .hasCover)
        try c.encode(importedAt, forKey: .importedAt)
        try c.encodeIfPresent(lastPlayedAt, forKey: .lastPlayedAt)
        try c.encode(position, forKey: .position)
        try c.encode(playbackRate, forKey: .playbackRate)
        try c.encode(modifiedAt, forKey: .modifiedAt)
    }

    var timeLeft: TimeInterval { max(0, duration - position) }
    var progress: Double { duration > 0 ? min(1, max(0, position / duration)) : 0 }

    // MARK: - Global time ↔ file mapping

    /// True when the per-file duration table is usable for time mapping.
    private var hasFileTable: Bool { !files.isEmpty && fileDurations.count == files.count }

    /// Cumulative GLOBAL start time of each file (same order as `files`).
    var fileStartTimes: [TimeInterval] {
        var starts: [TimeInterval] = []
        var acc: TimeInterval = 0
        for d in fileDurations {
            starts.append(acc)
            acc += max(0, d)
        }
        return starts
    }

    /// Index of the file playing at global `time` (the last file starting at
    /// or before it). 0 for single-file books and degenerate tables.
    func fileIndex(at time: TimeInterval) -> Int {
        guard hasFileTable, files.count > 1 else { return 0 }
        var idx = 0
        for (i, start) in fileStartTimes.enumerated() where start <= time { idx = i }
        return idx
    }

    /// Global `time` → the file holding it + the offset INSIDE that file.
    func fileLocation(at time: TimeInterval) -> (index: Int, offset: TimeInterval) {
        let i = fileIndex(at: time)
        guard hasFileTable else { return (0, max(0, time)) }
        return (i, max(0, time - fileStartTimes[i]))
    }

    /// GLOBAL bounds of the file containing `time`. The capture flow confines
    /// the span + the pannable micro-scrubber window to ONE file (the quote
    /// audio is extracted from that file alone); single-file books get the
    /// whole book.
    func fileBounds(at time: TimeInterval) -> CaptureSpan.Span {
        guard hasFileTable, files.count > 1 else {
            return CaptureSpan.Span(start: 0, end: max(0, duration))
        }
        let i = fileIndex(at: time)
        let start = fileStartTimes[i]
        return CaptureSpan.Span(start: start, end: start + max(0, fileDurations[i]))
    }

    /// Index of the chapter playing at `time` (the last chapter starting at or
    /// before it). nil when the file has no chapter track.
    func chapterIndex(at time: TimeInterval) -> Int? {
        guard !chapters.isEmpty else { return nil }
        var idx = 0
        for (i, ch) in chapters.enumerated() {
            if ch.start <= time { idx = i } else { break }
        }
        return idx
    }

    func chapter(at time: TimeInterval) -> AudiobookChapter? {
        chapterIndex(at: time).map { chapters[$0] }
    }

    /// Reader-facing chapter titles, same order as `chapters`: synthesized
    /// multi-file chapter names (whole source filenames) get their common
    /// prefix stripped + numbered remainders prettified ("Chapter 1"); real
    /// m4b-embedded titles pass through unchanged. Render chapters with THESE
    /// everywhere (menu, chapter line, capture context) — the attribution
    /// NUMBER stays the index (`chapterNumberString`).
    var displayChapterTitles: [String] {
        ChapterDisplay.displayTitles(chapters.map(\.title))
    }

    /// "Chapter 4 of 18 — Creation" (nil without chapters). A display title
    /// that is itself just "Chapter 4" would repeat the index — dropped.
    func chapterLine(at time: TimeInterval) -> String? {
        guard let i = chapterIndex(at: time) else { return nil }
        let title = displayChapterTitles[i]
        let base = "Chapter \(i + 1) of \(chapters.count)"
        return (title.isEmpty || title == "Chapter \(i + 1)") ? base : base + " — " + title
    }

    /// The chapter NUMBER as a string ("4") for the C2 `bookChapter` metadata —
    /// the Mac composes the attribution "ch. N" from it. nil without chapters.
    func chapterNumberString(at time: TimeInterval) -> String? {
        chapterIndex(at: time).map { String($0 + 1) }
    }

    /// "ch. 4 — Creation" for in-app labels (nil without chapters). Numbered
    /// display titles ("Chapter 4") collapse to just "ch. 4".
    func shortChapterLabel(at time: TimeInterval) -> String? {
        guard let i = chapterIndex(at: time) else { return nil }
        let title = displayChapterTitles[i]
        return (title.isEmpty || title == "Chapter \(i + 1)") ? "ch. \(i + 1)" : "ch. \(i + 1) — " + title
    }
}

/// Time formatting for the audiobook UI: "12:10:33" past the hour mark,
/// "21:13" under it.
enum AudiobookTime {
    static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds).rounded())
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }
}

/// The on-disk audiobook library: `Documents/audiobooks/library.json` + one
/// folder per book. A small JSON store (not SwiftData) — the library is tiny,
/// the shape is private to the phone, and tests inject a temp directory.
@MainActor
final class AudiobookLibraryStore: ObservableObject {
    static let shared = AudiobookLibraryStore()

    @Published private(set) var books: [Audiobook] = []

    let directory: URL

    init(directory: URL = AppPaths.documentsDirectory.appendingPathComponent("audiobooks", isDirectory: true)) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let indexURL = directory.appendingPathComponent("library.json")
        if let data = try? Data(contentsOf: indexURL),
           let decoded = try? JSONDecoder().decode([Audiobook].self, from: data) {
            books = decoded
        }
    }

    private var indexURL: URL { directory.appendingPathComponent("library.json") }

    // MARK: - Paths

    func folder(for id: UUID) -> URL {
        directory.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    /// The book's first (for single-file books, only) audio file.
    func audioURL(of book: Audiobook) -> URL {
        audioURL(of: book, fileIndex: 0)
    }

    /// One part of a multi-file book (out-of-range indices clamp to the first
    /// file so a degenerate record still points somewhere sensible).
    func audioURL(of book: Audiobook, fileIndex: Int) -> URL {
        let name = book.files.indices.contains(fileIndex)
            ? book.files[fileIndex]
            : (book.files.first ?? "")
        return folder(for: book.id).appendingPathComponent(name)
    }

    /// The imported cover art (nil when the file had none).
    func coverURL(of book: Audiobook) -> URL? {
        guard book.hasCover else { return nil }
        return folder(for: book.id).appendingPathComponent("cover.jpg")
    }

    // MARK: - Queries

    /// Library order: most recently played first, never-played books after
    /// (newest import first).
    var sortedByRecent: [Audiobook] {
        books.sorted { a, b in
            switch (a.lastPlayedAt, b.lastPlayedAt) {
            case let (pa?, pb?): return pa > pb
            case (.some, .none): return true
            case (.none, .some): return false
            case (.none, .none): return a.importedAt > b.importedAt
            }
        }
    }

    func book(id: UUID) -> Audiobook? {
        books.first { $0.id == id }
    }

    // MARK: - Mutations

    func add(_ book: Audiobook) {
        books.removeAll { $0.id == book.id }
        books.append(book)
        persist()
    }

    func update(_ book: Audiobook) {
        guard let i = books.firstIndex(where: { $0.id == book.id }) else { return }
        books[i] = book
        persist()
    }

    /// Persist the resume position (and mark the book played). Called from the
    /// player's periodic tick + on pause/close.
    func updateProgress(id: UUID, position: TimeInterval, playedAt: Date = Date()) {
        guard let i = books.firstIndex(where: { $0.id == id }) else { return }
        books[i].position = max(0, position)
        books[i].lastPlayedAt = playedAt
        books[i].modifiedAt = playedAt   // sync LWW key
        persist()
    }

    func updateRate(id: UUID, rate: Double) {
        guard let i = books.firstIndex(where: { $0.id == id }) else { return }
        books[i].playbackRate = rate
        books[i].modifiedAt = Date()      // a speed change syncs without bumping the recents sort
        persist()
    }

    /// Remove a book + its folder (audio + cover). Capture memos made from it
    /// are ordinary memos with their own extracted audio — they survive.
    func remove(_ book: Audiobook) {
        books.removeAll { $0.id == book.id }
        try? FileManager.default.removeItem(at: folder(for: book.id))
        persist()
    }

    private func persist() {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(books) else { return }
        do {
            try data.write(to: indexURL, options: .atomic)
        } catch {
            print("[Skrift] Audiobook library persist failed: \(error)")
        }
    }
}
