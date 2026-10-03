import SwiftUI

#if DEBUG
/// `-showBookTileGallery`: the REAL `BookShelfTile` in every state it can show (plain,
/// uploading 38%, downloading before the first byte, re-align running, download-available,
/// finished, no author, and the D127 "❝ N" notes pill) — a deterministic screenshot without
/// a live CloudKit transfer. `-showBookNotesSheet` also presents the REAL `BookNotesSheet`
/// over sample capture notes. Debug-only render hooks, like `-showTOCSheet`.
struct BookTileGallery: View {
    private struct Sample: Identifiable {
        let id = UUID()
        let book: Audiobook
        let state: AudiobookLibraryView.BookSyncState?
        let fraction: Double?
        let realign: String?
        var notes = 0
    }

    private static func make(_ title: String, _ author: String, position: Double = 1200) -> Audiobook {
        Audiobook(
            audioFilename: "x.m4a", title: title, author: author, duration: 36_000,
            chapters: [AudiobookChapter(title: "Chapter 1", start: 0, duration: 36_000)],
            lastPlayedAt: Date(), position: position)
    }

    private let samples: [Sample] = [
        Sample(book: make("The Long Way Round", "Frank Herbert"), state: nil, fraction: nil, realign: nil, notes: 5),
        Sample(book: make("Uploading Example", "Ursula K. Le Guin"), state: .uploading, fraction: 0.38, realign: nil),
        Sample(book: make("Downloading, no byte yet", "Octavia Butler"), state: .downloading, fraction: nil, realign: nil),
        Sample(book: make("Re-aligning the text", "Terry Pratchett"), state: .synced, fraction: nil, realign: "Matching the text…", notes: 12),
        Sample(book: make("Freed on this device", "Iain M. Banks"), state: .downloadAvailable, fraction: nil, realign: nil, notes: 1),
        Sample(book: make("A title that runs long enough to truncate on the tile", ""), state: .synced, fraction: nil, realign: nil, notes: 3),
    ]

    @State private var showNotes = LaunchFlags.showBookNotesSheet

    private var sampleNotes: [Memo] {
        func note(_ title: String, _ quote: String, _ ramble: String, chapter: String, pos: Double, day: Double) -> Memo {
            var meta = MemoMetadata()
            meta.bookTitle = "The Long Way Round"; meta.bookChapter = chapter
            meta.bookID = UUID(); meta.bookPosition = pos
            return Memo.make(recordedAt: Date(timeIntervalSince1970: 1_758_412_800 - day * 86_400),
                             title: title, transcript: "> \(quote)\n\n\(ramble)", metadata: meta)
        }
        return [
            note("Pick the three", "You will never clear the list, so choose what to neglect on purpose.",
                 "Finite time, so pick the three. Ask Hendri what his three are.", chapter: "7", pos: 4325, day: 0),
            note("Patience as a skill", "Staying on the bus a little longer is where the work turns original.",
                 "This is the robot arm project. Year two is where it stops looking like everyone else’s.", chapter: "11", pos: 10_960, day: 1),
            note("The convenience trap", "The easy path removes the friction that made the thing worth doing.",
                 "Same with the transcription UI.", chapter: "4", pos: 2892, day: 7),
        ]
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 170, maximum: 220), spacing: 20)], spacing: 26) {
                ForEach(samples) { s in
                    BookShelfTile(book: s.book, isCurrent: false, syncState: s.state,
                                  transferFraction: s.fraction, realign: s.realign,
                                  noteCount: s.notes, onNotes: { showNotes = true }) {}
                }
            }
            .padding(Theme.Space.margin)
        }
        .background(Color.skBg.ignoresSafeArea())
        .sheet(isPresented: $showNotes) {
            BookNotesSheet(book: Self.make("The Long Way Round", "Frank Herbert"), notes: sampleNotes, onOpen: { _ in })
                .presentationDetents([.medium, .large])
        }
    }
}
#endif
