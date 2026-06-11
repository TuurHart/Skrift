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
struct Audiobook: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    /// Filename inside the book's folder (original extension preserved).
    var audioFilename: String
    var title: String
    var author: String
    var duration: TimeInterval
    var chapters: [AudiobookChapter]
    var hasCover: Bool
    var importedAt: Date
    /// nil until first played — drives the "recently played" sort.
    var lastPlayedAt: Date?
    /// Per-book resume position (seconds).
    var position: TimeInterval
    /// Per-book playback speed (Bound keeps speed per book too).
    var playbackRate: Double

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
        playbackRate: Double = 1.0
    ) {
        self.id = id
        self.audioFilename = audioFilename
        self.title = title
        self.author = author
        self.duration = duration
        self.chapters = chapters
        self.hasCover = hasCover
        self.importedAt = importedAt
        self.lastPlayedAt = lastPlayedAt
        self.position = position
        self.playbackRate = playbackRate
    }

    var timeLeft: TimeInterval { max(0, duration - position) }
    var progress: Double { duration > 0 ? min(1, max(0, position / duration)) : 0 }

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

    /// "Chapter 4 of 18 — Creation" (nil without chapters).
    func chapterLine(at time: TimeInterval) -> String? {
        guard let i = chapterIndex(at: time) else { return nil }
        let title = chapters[i].title.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = "Chapter \(i + 1) of \(chapters.count)"
        return title.isEmpty ? base : base + " — " + title
    }

    /// The chapter NUMBER as a string ("4") for the C2 `bookChapter` metadata —
    /// the Mac composes the attribution "ch. N" from it. nil without chapters.
    func chapterNumberString(at time: TimeInterval) -> String? {
        chapterIndex(at: time).map { String($0 + 1) }
    }

    /// "ch. 4 — Creation" for in-app labels (nil without chapters).
    func shortChapterLabel(at time: TimeInterval) -> String? {
        guard let i = chapterIndex(at: time) else { return nil }
        let title = chapters[i].title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "ch. \(i + 1)" : "ch. \(i + 1) — " + title
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

    func audioURL(of book: Audiobook) -> URL {
        folder(for: book.id).appendingPathComponent(book.audioFilename)
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
        persist()
    }

    func updateRate(id: UUID, rate: Double) {
        guard let i = books.firstIndex(where: { $0.id == id }) else { return }
        books[i].playbackRate = rate
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
