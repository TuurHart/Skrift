#if DEBUG
import AVFoundation
import Foundation

/// `-seedAudiobook`: fabricate a small silent audiobook and open it as a PAUSED
/// session, so the global mini-player capsule (and the player) exist in the
/// Simulator. Screenshot/UITest-only — the sim can't import a real book, which
/// is how the build-40 FAB/capsule overlap shipped unseen.
@MainActor
enum AudiobookSeeder {
    /// Idempotent per launch: seeds one book into the (temp-directory) library
    /// and arms the session. 60 s of silence is enough for every layout state.
    static func seedAndOpen(store: AudiobookLibraryStore = .shared,
                            session: AudiobookSession = .shared) {
        guard !session.isActive else { return }
        guard let book = ensureBook(store: store) else { return }
        session.open(book)   // paused session — the V2a pill state
    }

    /// `-seedLibraryShelf` (Q352): four books with different progress, two of them with capture
    /// notes, so the Library shelf and its "❝ N" pills render in the Simulator. Screenshot-only.
    static func seedShelf(store: AudiobookLibraryStore = .shared, repo: NotesRepository = .shared) {
        guard store.books.isEmpty else { return }
        let shelf: [(String, String, Double, Double, Int)] = [
            ("The Long Way Round", "Frank Herbert", 36_000, 14_400, 5),
            ("Het Uur: Ik zit in een rouwproces", "NRC", 3_600, 3_400, 0),
            ("A Pattern Language", "Christopher Alexander", 72_000, 0, 2),
            ("Walking", "Henry David Thoreau", 18_000, 9_000, 0),
        ]
        for (index, entry) in shelf.enumerated() {
            let (title, author, duration, position, notes) = entry
            let book = Audiobook(
                audioFilename: "book.wav", title: title, author: author, duration: duration,
                chapters: [AudiobookChapter(title: "Chapter 1", start: 0, duration: duration)],
                lastPlayedAt: Date(timeIntervalSinceNow: -Double(index) * 3_600), position: position)
            store.add(book)
            for n in 0..<notes {
                var meta = MemoMetadata()
                meta.bookTitle = title; meta.bookChapter = "\(n + 1)"
                meta.bookID = book.id; meta.bookPosition = position
                repo.insert(Memo.make(recordedAt: Date(timeIntervalSinceNow: -Double(n) * 86_400),
                                      title: "Note \(n + 1)", transcript: "> A sentence from the book.\n\nMy thought.",
                                      metadata: meta))
            }
        }
    }

    private static func ensureBook(store: AudiobookLibraryStore) -> Audiobook? {
        store.books.first { $0.title == Self.title } ?? makeBook(store: store)
    }

    private static let title = "Seeded Audiobook"

    private static func makeBook(store: AudiobookLibraryStore) -> Audiobook? {
        var book = Audiobook(
            audioFilename: "book.wav",
            title: title,
            author: "Simulator",
            duration: 60,
            chapters: [AudiobookChapter(title: "Chapter 1", start: 0, duration: 60)],
            lastPlayedAt: Date(),       // restore/recents treat it as "yesterday's book"
            position: 12
        )
        // `-seedDetectedChapters`: the multi-work detected list (trilogy shape) —
        // Opening + chapters + a "Book 2" separator — for sheet screenshots.
        if LaunchFlags.seedDetectedChapters {
            book.detectedChapters = [
                AudiobookChapter(title: "Opening", start: 0, duration: 8),
                AudiobookChapter(title: "Chapter 2", start: 8, duration: 10),
                AudiobookChapter(title: "Chapter 3", start: 18, duration: 8),
                AudiobookChapter(title: "Chapter 7", start: 26, duration: 8),
                AudiobookChapter(title: "Book 2", start: 34, duration: 0, isSeparator: true),
                AudiobookChapter(title: "Chapter 1", start: 34, duration: 14),
                AudiobookChapter(title: "Chapter 8", start: 48, duration: 12),
            ]
        }
        let folder = store.folder(for: book.id)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try writeSilence(to: folder.appendingPathComponent("book.wav"), seconds: 60)
        } catch {
            print("[Skrift] seedAudiobook failed: \(error)")
            return nil
        }
        store.add(book)
        return book
    }

    /// A real PCM file (not an empty stub) so AVPlayer/AVAudioFile treat it as
    /// ordinary audio everywhere (player, read-along probes, capture math).
    private static func writeSilence(to url: URL, seconds: Double) throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 22_050, channels: 1)!
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let frames = AVAudioFrameCount(seconds * format.sampleRate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return }
        buffer.frameLength = frames   // zero-filled = silence
        try file.write(from: buffer)
    }
}
#endif
