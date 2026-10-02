import SwiftUI

#if DEBUG
/// `-showBookTileGallery`: the REAL `BookShelfTile` in every state it can show (plain,
/// uploading 38%, downloading before the first byte, re-align running, download-available,
/// finished, no author) — a deterministic screenshot without a live CloudKit transfer.
/// Debug-only render hook, like `-showTOCSheet`.
struct BookTileGallery: View {
    private struct Sample: Identifiable {
        let id = UUID()
        let book: Audiobook
        let state: AudiobookLibraryView.BookSyncState?
        let fraction: Double?
        let realign: String?
    }

    private static func make(_ title: String, _ author: String, position: Double = 1200) -> Audiobook {
        Audiobook(
            audioFilename: "x.m4a", title: title, author: author, duration: 36_000,
            chapters: [AudiobookChapter(title: "Chapter 1", start: 0, duration: 36_000)],
            lastPlayedAt: Date(), position: position)
    }

    private let samples: [Sample] = [
        Sample(book: make("The Long Way Round", "Frank Herbert"), state: nil, fraction: nil, realign: nil),
        Sample(book: make("Uploading Example", "Ursula K. Le Guin"), state: .uploading, fraction: 0.38, realign: nil),
        Sample(book: make("Downloading, no byte yet", "Octavia Butler"), state: .downloading, fraction: nil, realign: nil),
        Sample(book: make("Re-aligning the text", "Terry Pratchett"), state: .synced, fraction: nil, realign: "Matching the text…"),
        Sample(book: make("Freed on this device", "Iain M. Banks"), state: .downloadAvailable, fraction: nil, realign: nil),
        Sample(book: make("A title that runs long enough to truncate on the tile", ""), state: .synced, fraction: nil, realign: nil),
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 170, maximum: 220), spacing: 20)], spacing: 26) {
                ForEach(samples) { s in
                    BookShelfTile(book: s.book, isCurrent: false, syncState: s.state,
                                  transferFraction: s.fraction, realign: s.realign) {}
                }
            }
            .padding(Theme.Space.margin)
        }
        .background(Color.skBg.ignoresSafeArea())
    }
}
#endif
