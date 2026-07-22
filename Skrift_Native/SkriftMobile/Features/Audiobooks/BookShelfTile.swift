import SwiftUI

/// One cell of the Books shelf (iPad wave, regular width — mock
/// `ipad-app.html` m6): the SAME row data the compact list shows (cover,
/// title, progress, sync glyph, time left), laid out as a square Bound-style
/// tile instead. Dumb + parent-driven (mirrors `BookCoverView`'s style): the
/// caller supplies `isCurrent`/`syncState` and owns tap + long-press (shared
/// with the list row via `AudiobookLibraryView.openOrPlay`/`contextMenuItems`
/// so the two surfaces can never diverge in behavior).
struct BookShelfTile: View {
    let book: Audiobook
    let isCurrent: Bool
    let syncState: AudiobookLibraryView.BookSyncState?
    let action: () -> Void

    /// Mirrors `BookStatusFilter.finished` — a book within the tail is "done"
    /// even if `progress` hasn't rounded to a literal 1.0 (the no-bad-info
    /// rule: never show a stalled 99% when it's functionally finished).
    private var isFinished: Bool {
        book.duration > 0 && book.timeLeft <= BookStatusFilter.finishedTail
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .topTrailing) {
                    BookCoverView(book: book)
                        .aspectRatio(1, contentMode: .fit)
                        .clipShape(.rect(cornerRadius: 12, style: .continuous))
                        .shadow(color: .black.opacity(0.3), radius: 6, y: 3)
                        .overlay(
                            RoundedRectangle.sk(12)
                                .stroke(isCurrent ? Color.skAccent.opacity(0.6) : .clear, lineWidth: 2)
                        )
                    if let syncGlyph {
                        Image(systemName: syncGlyph)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.85))
                            .padding(6)
                            .shadow(color: .black.opacity(0.5), radius: 3)
                            .accessibilityHidden(true)
                    }
                }
                .frame(maxWidth: .infinity)

                Text(book.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.skText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)

                progressBar
                    .frame(height: 3)
                    .padding(.top, 6)

                statusLine
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ipad-library-book-tile")
        .accessibilityLabel("\(book.title) by \(book.author), \(AudiobookTime.clock(book.timeLeft)) left")
    }

    private var syncGlyph: String? {
        switch syncState {
        case .synced: return "checkmark.icloud"
        case .downloadAvailable: return "icloud.and.arrow.down"
        case .uploading, .downloading, .none: return nil
        }
    }

    @ViewBuilder
    private var progressBar: some View {
        if syncState == .uploading || syncState == .downloading {
            ProgressView()
                .progressViewStyle(.linear)
                .tint(Color.skAccent)
                .scaleEffect(x: 1, y: 0.7, anchor: .center)
        } else {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.skBorder).frame(height: 3)
                    Capsule()
                        .fill(isFinished ? Color.skGreen : Color.skAccent)
                        .frame(width: max(2, geo.size.width * (isFinished ? 1 : book.progress)), height: 3)
                }
            }
        }
    }

    private var statusLine: some View {
        HStack {
            Text(Self.progressLabel(for: book))
            Spacer(minLength: 4)
            if !isFinished {
                Text(AudiobookTime.clock(book.timeLeft) + " left")
            }
        }
        .font(.system(size: 10))
        .monospacedDigit()
        .foregroundStyle(Color.skTextFaint)
        .lineLimit(1)
    }

    /// "ch N · P%" once there's a chapter to name, else a bare percentage;
    /// "finished" past the tail threshold (same rule as `BookStatusFilter`).
    /// Pure — unit-tested in `IPadBooksLogicTests`.
    static func progressLabel(for book: Audiobook) -> String {
        guard !(book.duration > 0 && book.timeLeft <= BookStatusFilter.finishedTail) else { return "finished" }
        let pct = Int((book.progress * 100).rounded())
        if let chapter = book.chapterIndex(at: book.position) {
            return "ch \(chapter + 1) · \(pct)%"
        }
        return "\(pct)%"
    }
}
