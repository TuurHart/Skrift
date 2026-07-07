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
        let existing = store.books.first { $0.title == Self.title }
        let book = existing ?? makeBook(store: store)
        guard let book else { return }
        session.open(book)   // paused — the cold-launch-restore shape
    }

    private static let title = "Seeded Audiobook"

    private static func makeBook(store: AudiobookLibraryStore) -> Audiobook? {
        let book = Audiobook(
            audioFilename: "book.wav",
            title: title,
            author: "Simulator",
            duration: 60,
            chapters: [AudiobookChapter(title: "Chapter 1", start: 0, duration: 60)],
            lastPlayedAt: Date(),       // restore/recents treat it as "yesterday's book"
            position: 12
        )
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
