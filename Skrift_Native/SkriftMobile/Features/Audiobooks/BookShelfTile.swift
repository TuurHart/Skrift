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
    /// Live transfer fraction (nil before the first byte, or when not transferring).
    var transferFraction: Double? = nil
    /// The live re-align line for this book (nil when none runs). Same text as the row.
    var realign: String? = nil
    /// D127 (Q6 mock): capture notes made from this book. 0 = no pill. The pill is its own
    /// button (opens the book's notes), apart from the tile's tap-to-play.
    var noteCount: Int = 0
    var onNotes: (() -> Void)? = nil
    let action: () -> Void

    private var transferring: Bool { syncState == .uploading || syncState == .downloading }

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

                if !book.author.isEmpty {
                    Text(book.author)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.skTextDim)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 1)
                }

                progressBar
                    .frame(height: 3)
                    .padding(.top, 6)

                statusLine
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        // The ❝ N pill sits on the cover's bottom-right corner (mock: right 6, bottom 6). It is
        // an overlay of the tile, not inside the tile's Button label, so it taps on its own.
        // The cover is square and full width, so a square clear spacer finds its bottom edge.
        .overlay(alignment: .top) {
            if noteCount > 0, let onNotes {
                VStack(spacing: 0) {
                    Color.clear
                        .aspectRatio(1, contentMode: .fit)
                        .allowsHitTesting(false)
                        .overlay(alignment: .bottomTrailing) {
                            BookNotesPill(count: noteCount, action: onNotes).padding(6)
                        }
                    Spacer(minLength: 0).allowsHitTesting(false)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ipad-library-book-tile")
        .accessibilityLabel(BookTileState.accessibilityLabel(
            title: book.title, author: book.author, timeLeft: AudiobookTime.clock(book.timeLeft),
            syncState: syncState, transferFraction: transferFraction, realign: realign))
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
        if transferring {
            // Determinate once the transport reports a fraction, like the row.
            Group {
                if let transferFraction { ProgressView(value: transferFraction) } else { ProgressView() }
            }
            .progressViewStyle(.linear)
            .tint(Color.skAccent)
            .scaleEffect(x: 1, y: 0.7, anchor: .center)
        } else {
            ThinProgressBar(fraction: book.isFinished ? 1 : book.progress,
                            fill: book.isFinished ? Color.skGreen : Color.skAccent, minFill: 2)
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        if transferring {
            Text(BookTileState.transferLabel(uploading: syncState == .uploading, fraction: transferFraction))
                .font(.system(size: 10))
                .monospacedDigit()
                .foregroundStyle(Color.skAccentText)
                .lineLimit(1)
        } else if let realign {
            HStack(spacing: 5) {
                ProgressView().controlSize(.mini)
                Text(realign)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.skAccentText)
                    .lineLimit(1)
            }
        } else {
            progressStatusLine
        }
    }

    private var progressStatusLine: some View {
        HStack {
            Text(Self.progressLabel(for: book))
            Spacer(minLength: 4)
            if !book.isFinished {
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
        guard !book.isFinished else { return "finished" }
        let pct = Int((book.progress * 100).rounded())
        if let chapter = book.chapterIndex(at: book.position) {
            return "ch \(chapter + 1) · \(pct)%"
        }
        return "\(pct)%"
    }
}
