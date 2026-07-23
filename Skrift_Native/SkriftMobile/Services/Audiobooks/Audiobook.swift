import Foundation

/// One embedded chapter (from the file's m4b/m4a chapter track).
struct AudiobookChapter: Codable, Equatable, Sendable {
    var title: String
    var start: TimeInterval
    var duration: TimeInterval
    /// Display-only divider between WORKS in a multi-book import ("Book 2",
    /// inserted by `ChapterDetector` at number resets). Rendered as a section
    /// header in the chapters sheet; excluded from chapter counting, the
    /// `Ch N/M` pill, navigation, and attribution. nil/absent = a real chapter
    /// (synthesized Codable keeps old records decoding unchanged).
    var isSeparator: Bool? = nil
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
    /// Chapters from IMPORT: the embedded m4b track, or one-per-file synthesis.
    var chapters: [AudiobookChapter]
    /// Chapters DETECTED from the transcript (`ChapterDetector`) once the book
    /// was fully transcribed — the standard source when non-empty UNLESS an
    /// ePub is attached (`epubChapters` wins — Q1 lock 2026-07-21): file splits
    /// and rip metadata aren't reliably chapter boundaries, the narration is.
    /// nil = detection never ran; [] = ran, found nothing confident (don't
    /// re-run). Local-only — derived from the local sidecar, never synced.
    var detectedChapters: [AudiobookChapter]? = nil
    /// 📖 The attached ePub's filename inside the book's folder (nil = none).
    /// The file itself stays LOCAL to the attaching device in v1; alignment
    /// sidecars (which carry chapter marks) are what sync.
    /// LEGACY single slot (pre-multi-text) — kept written with the FIRST
    /// attached text so older decoders keep working; read via
    /// `attachedTextFilenames`, never directly.
    var epubFilename: String? = nil
    /// 📖 ALL attached text files (multi-text, 2026-07-22 — one omnibus
    /// audiobook holds several books' texts; mock `mocks/book-text-sheet.html`
    /// variant B signed off). Additive; nil on records written before
    /// multi-text existed — `attachedTextFilenames` falls back to the legacy slot.
    var epubFilenames: [String]? = nil
    /// Chapters from the ATTACHED ePub's real TOC, timed via the alignment
    /// sidecars — the WINNING source when non-empty (ePub TOC > transcript-
    /// detected > embedded; Tuur 2026-07-21). Local-only — derived from the
    /// local alignment sidecars, re-derived per device, never synced.
    var epubChapters: [AudiobookChapter]? = nil
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

    /// 📖 THE read accessor for attached texts: the multi-text array when present,
    /// else the legacy single slot. Order = attach order (stable; the sheet renders it).
    var attachedTextFilenames: [String] {
        if let list = epubFilenames { return list }
        return epubFilename.map { [$0] } ?? []
    }

    /// LOCAL-ONLY fields (device finding 2026-07-22: the attach fields VANISHED —
    /// a whole-blob LWW write from any device running an older build re-encodes the
    /// record without additive fields and erases them; SECOND cause found on the
    /// Odyssey chapter-discrepancy report: the custom Codable below simply never
    /// carried these keys, so a plain library.json persist→relaunch on ONE device
    /// erased them too — they ARE encoded now). The attached text FILES exist
    /// only on this device, and both chapter lists derive from LOCAL sidecars — so
    /// these fields never ride the sync blob, and an adopted remote record always
    /// keeps THIS device's values. Belt and braces: strip on send, preserve on adopt.
    func sanitizedForSync() -> Audiobook {
        var copy = self
        copy.epubFilename = nil
        copy.epubFilenames = nil
        copy.epubChapters = nil
        copy.detectedChapters = nil
        return copy
    }

    /// The adopt-side half: a remote record about to overwrite `local` inherits every
    /// local-only field from it (remote values for these are meaningless off-device).
    func keepingLocalTextFields(from local: Audiobook) -> Audiobook {
        var copy = self
        copy.epubFilename = local.epubFilename
        copy.epubFilenames = local.epubFilenames
        copy.epubChapters = local.epubChapters
        copy.detectedChapters = local.detectedChapters
        return copy
    }

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
        case chapters, detectedChapters, hasCover, importedAt, lastPlayedAt
        case position, playbackRate, modifiedAt
        // 📖 attach fields (2026-07-22 fix): these were MISSING from this hand-written
        // Codable, so library.json never carried them — every relaunch silently lost the
        // attachment and epubChapters reverted the sheet to detected/embedded chapters
        // (the Odyssey device report). The sync blob still never carries them: every
        // send path encodes `sanitizedForSync()`, which nils all of them first.
        case epubFilename, epubFilenames, epubChapters
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
        detectedChapters = try c.decodeIfPresent([AudiobookChapter].self, forKey: .detectedChapters)
        epubFilename = try c.decodeIfPresent(String.self, forKey: .epubFilename)
        epubFilenames = try c.decodeIfPresent([String].self, forKey: .epubFilenames)
        epubChapters = try c.decodeIfPresent([AudiobookChapter].self, forKey: .epubChapters)
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
        try c.encodeIfPresent(detectedChapters, forKey: .detectedChapters)
        try c.encodeIfPresent(epubFilename, forKey: .epubFilename)
        try c.encodeIfPresent(epubFilenames, forKey: .epubFilenames)
        try c.encodeIfPresent(epubChapters, forKey: .epubChapters)
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

    /// True when transcript-detected chapters exist and win over `chapters`.
    private var usesDetected: Bool { detectedChapters?.isEmpty == false }

    /// True when the attached ePub's TOC chapters exist — the top of the precedence.
    private var usesEpub: Bool { epubChapters?.isEmpty == false }

    /// True when `effectiveChapters` already carries display-ready titles (ePub TOC
    /// entries or detector output). Only the embedded/import-synthesized `chapters`
    /// need `ChapterDisplay` prettification. Every title accessor below MUST key off
    /// this (not `usesDetected` alone): with an ePub attached and detection never
    /// run, keying off `usesDetected` rendered EMBEDDED titles against ePub rows —
    /// wrong titles, and an index crash when the ePub list was longer (2026-07-22).
    private var titlesAreDisplayReady: Bool { usesEpub || usesDetected }

    /// The chapter list the sheet renders — INCLUDING display-only "Book N"
    /// separators. Never read `chapters` directly for display.
    /// Precedence (Q1 lock 2026-07-21): ePub TOC > transcript-detected > embedded.
    var effectiveChapters: [AudiobookChapter] {
        if let epub = epubChapters, !epub.isEmpty { return epub }
        return usesDetected ? detectedChapters! : chapters
    }

    /// The chapters you can BE in: `effectiveChapters` minus separators. All
    /// index-based semantics (current chapter, `Ch N/M` pill, sleep timer,
    /// attribution, prev/next) run on THIS list, so a divider never counts.
    var playableChapters: [AudiobookChapter] {
        effectiveChapters.filter { $0.isSeparator != true }
    }

    /// Index (into `playableChapters`) of the chapter playing at `time` — the
    /// last chapter starting at or before it. nil when the book has no
    /// chapters from any source.
    func chapterIndex(at time: TimeInterval) -> Int? {
        let list = playableChapters
        guard !list.isEmpty else { return nil }
        var idx = 0
        for (i, ch) in list.enumerated() {
            if ch.start <= time { idx = i } else { break }
        }
        return idx
    }

    func chapter(at time: TimeInterval) -> AudiobookChapter? {
        chapterIndex(at: time).map { playableChapters[$0] }
    }

    /// Reader-facing titles, same order/count as `effectiveChapters` (the
    /// sheet indexes it row-for-row, separators included). ePub-TOC and
    /// detected titles are already display-ready ("Book 1: The Boy and the
    /// Goddess", "Chapter 7 — The Iron Duke", "Prologue", "Book 2") and pass
    /// through; import-synthesized (filename) chapter names get their common
    /// prefix stripped + numbered remainders prettified ("Chapter 1"); real
    /// m4b-embedded titles pass through unchanged.
    var displayChapterTitles: [String] {
        titlesAreDisplayReady
            ? effectiveChapters.map(\.title)
            : ChapterDisplay.displayTitles(chapters.map(\.title))
    }

    /// Titles aligned to `playableChapters` — what the index-based labels use.
    private var playableDisplayTitles: [String] {
        titlesAreDisplayReady
            ? playableChapters.map(\.title)
            : ChapterDisplay.displayTitles(chapters.map(\.title))
    }

    /// "Chapter 4 of 18 — Creation" (nil without chapters). A display title
    /// that is itself just "Chapter 4" would repeat the index — dropped.
    /// ePub-TOC and detected titles carry their own heading ("Book 1: X",
    /// "Chapter 7 — X", "Prologue"), so they get the position appended
    /// instead of a second "Chapter n".
    func chapterLine(at time: TimeInterval) -> String? {
        guard let i = chapterIndex(at: time) else { return nil }
        let title = playableDisplayTitles[i]
        let count = playableChapters.count
        if titlesAreDisplayReady, !title.isEmpty {
            return title + "  ·  \(i + 1) of \(count)"
        }
        let base = "Chapter \(i + 1) of \(count)"
        return (title.isEmpty || title == "Chapter \(i + 1)") ? base : base + " — " + title
    }

    /// The chapter NUMBER as a string ("4") for the C2 `bookChapter` metadata —
    /// the Mac composes the attribution "ch. N" from it. nil without chapters.
    /// For ePub-TOC/detected chapters this is the STATED number (the "7" of
    /// "Chapter 7 — X"), not the list index — Opening/Prologue/front-matter
    /// entries shift the index, and a prologue quote should carry no chapter
    /// number at all.
    func chapterNumberString(at time: TimeInterval) -> String? {
        guard let i = chapterIndex(at: time) else { return nil }
        guard titlesAreDisplayReady else { return String(i + 1) }
        let title = playableChapters[i].title
        guard let match = title.firstMatch(of: #/(?i)^chapter (\d+)/#) else { return nil }
        return String(match.1)
    }

    /// "ch. 4 — Creation" for in-app labels (nil without chapters). Numbered
    /// display titles ("Chapter 4") collapse to just "ch. 4"; ePub-TOC/detected
    /// titles compact their own heading ("Chapter 7 — X" → "ch. 7 — X").
    func shortChapterLabel(at time: TimeInterval) -> String? {
        guard let i = chapterIndex(at: time) else { return nil }
        let title = playableDisplayTitles[i]
        if titlesAreDisplayReady {
            guard !title.isEmpty else { return "ch. \(i + 1)" }
            return title.hasPrefix("Chapter ") ? "ch. " + title.dropFirst("Chapter ".count) : title
        }
        return (title.isEmpty || title == "Chapter \(i + 1)") ? "ch. \(i + 1)" : "ch. \(i + 1) — " + title
    }
}

/// Books-tab sort orders (the header chip; persisted via its rawValue).
/// Default = recently played — the "continue where I was" library.
enum BookSort: String, CaseIterable, Sendable {
    case recentlyPlayed
    case title
    case author
    case recentlyAdded

    var label: String {
        switch self {
        case .recentlyPlayed: return "Recently played"
        case .title: return "Title"
        case .author: return "Author"
        case .recentlyAdded: return "Recently added"
        }
    }

    func sorted(_ books: [Audiobook]) -> [Audiobook] {
        switch self {
        case .recentlyPlayed:
            // Most recently played first; never-played after, newest import first.
            return books.sorted { a, b in
                switch (a.lastPlayedAt, b.lastPlayedAt) {
                case let (pa?, pb?): return pa > pb
                case (.some, .none): return true
                case (.none, .some): return false
                case (.none, .none): return a.importedAt > b.importedAt
                }
            }
        case .title:
            return books.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .author:
            return books.sorted { $0.author.localizedStandardCompare($1.author) == .orderedAscending }
        case .recentlyAdded:
            return books.sorted { $0.importedAt > $1.importedAt }
        }
    }
}

/// Books-tab status filter (transient). Finished = within 30 s of the end;
/// in progress = started and not finished; not started = never past the top.
enum BookStatusFilter: CaseIterable, Sendable {
    case inProgress, notStarted, finished

    static let finishedTail: TimeInterval = 30

    var label: String {
        switch self {
        case .inProgress: return "In progress"
        case .notStarted: return "Not started"
        case .finished: return "Finished"
        }
    }

    func matches(_ book: Audiobook) -> Bool {
        let finished = book.duration > 0 && book.timeLeft <= Self.finishedTail
        switch self {
        case .finished: return finished
        case .inProgress: return !finished && book.position > 1
        case .notStarted: return !finished && book.position <= 1
        }
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
