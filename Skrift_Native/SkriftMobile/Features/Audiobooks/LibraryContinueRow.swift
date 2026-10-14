import SwiftUI

/// Q403 (D207, Q6 mock `.cont` / `.ccard`): the "Continue" row above the type chips. The last few
/// sources played or opened, any kind, most recent first; a finished source drops out. The same
/// one-line progress / time-left words the shelf tile shows, so the card and the tile never disagree.
enum LibraryContinue {
    /// How many cards the row holds.
    static let limit = 5

    /// Recently used first, finished and never-opened sources left out.
    static func items(from books: [Audiobook], limit: Int = LibraryContinue.limit) -> [Audiobook] {
        let used = books.filter { $0.lastPlayedAt != nil && !$0.isFinished }
        return Array(BookSort.recentlyPlayed.sorted(used).prefix(limit))
    }

    /// The card's grey line: the author, plus the release date for an episode ("NRC Het Uur · 26 Jun 2026").
    static func byline(_ book: Audiobook, calendar: Calendar = .current, locale: Locale = .current) -> String {
        var parts: [String] = []
        let author = book.author.trimmingCharacters(in: .whitespaces)
        if !author.isEmpty { parts.append(author) }
        if book.sourceKind == .episode, let published = book.publishedAt {
            let f = DateFormatter()
            f.calendar = calendar
            f.timeZone = calendar.timeZone
            f.locale = locale
            f.dateFormat = "d MMM yyyy"
            parts.append(f.string(from: published))
        }
        return parts.joined(separator: " \u{00B7} ")
    }

    /// The left-hand progress words: "p. 4 of 18", "31%", "ch 7 · 54%", an episode's "23:41".
    static func progressLine(_ book: Audiobook) -> String {
        switch book.sourceKind {
        case .pdf: return LibraryPDF.progressLine(book)
        case .article: return LibraryArticle.progressLine(book)
        case .episode: return book.isFinished ? "finished" : AudiobookTime.clock(book.position)
        case .book: return BookShelfTile.progressLabel(for: book)
        }
    }

    /// The right-hand words: "14 pages left", "28 min left", "2:41:10 left"; nil when there is nothing left to say.
    static func leftLine(_ book: Audiobook) -> String? {
        switch book.sourceKind {
        case .pdf: return LibraryPDF.leftLine(book)
        case .article: return book.position > 0 && !book.isFinished ? LibraryArticle.leftLine(book) : nil
        case .episode, .book: return book.isFinished ? nil : AudiobookTime.clock(book.timeLeft) + " left"
        }
    }
}

extension LibrarySourceKind {
    /// "Audiobook", "Episode", "PDF", "Article": the shared taxonomy's word for the source.
    var label: String { linkKind.sourceName ?? "" }

    /// The cover's type badge: the same word in capitals.
    var badge: String { label.uppercased() }
}

/// The type capsule on a cover's top-left corner (mock `.badge`): 8.5pt bold caps on 55% black.
struct LibraryTypeBadge: View {
    let kind: LibrarySourceKind

    var body: some View {
        Text(kind.badge)
            .font(.system(size: 8.5, weight: .bold))
            .tracking(0.34)
            .foregroundStyle(.white)
            .padding(.horizontal, 5).padding(.vertical, 4)
            .background(Color.black.opacity(0.55), in: .rect(cornerRadius: 5, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// The horizontally scrolling Continue row. Dumb: the caller owns what a tap does.
struct LibraryContinueRow: View {
    let books: [Audiobook]
    let currentID: UUID?
    let onOpen: (Audiobook) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 12) {
                ForEach(books) { book in
                    LibraryContinueCard(book: book, isCurrent: book.id == currentID) { onOpen(book) }
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollIndicators(.hidden)
        // A horizontal ScrollView is vertically greedy; without this it splits the screen's
        // spare height with the shelf below and leaves a gap above and below the cards.
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Continue")
        .accessibilityIdentifier("library-continue-row")
    }
}

/// One card (mock `.ccard`): 300pt wide, cover 84pt, kind label, two-line title, byline, bar, and
/// the progress / time-left pair.
struct LibraryContinueCard: View {
    let book: Audiobook
    let isCurrent: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                BookCoverView(book: book)
                    .frame(width: 84, height: 84)
                    .clipShape(.rect(cornerRadius: 10, style: .continuous))
                    .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
                    .overlay(
                        RoundedRectangle.sk(10)
                            .stroke(isCurrent ? Color.skAccent.opacity(0.6) : .clear, lineWidth: 2)
                    )
                VStack(alignment: .leading, spacing: 0) {
                    Text(book.sourceKind.label)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(Color.skAccentText)
                    Text(book.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.skText)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .padding(.top, 1)
                    let byline = LibraryContinue.byline(book)
                    if !byline.isEmpty {
                        Text(byline)
                            .font(.system(size: 11.5))
                            .foregroundStyle(Color.skTextDim)
                            .lineLimit(1)
                            .padding(.top, 2)
                    }
                    ThinProgressBar(fraction: book.progress, minFill: 2)
                        .padding(.top, 8)
                    HStack(spacing: 6) {
                        Text(LibraryContinue.progressLine(book))
                        Spacer(minLength: 4)
                        if let left = LibraryContinue.leftLine(book) { Text(left) }
                    }
                    .font(.system(size: 10))
                    .monospacedDigit()
                    .foregroundStyle(Color.skTextFaint)
                    .lineLimit(1)
                    .padding(.top, 4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
            .frame(width: 300)
            .background(Color.skSurface, in: .rect(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle.sk(16).stroke(Color.skBorder, lineWidth: 0.5))
            .contentShape(.rect(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(book.sourceKind.label), \(book.title), \(LibraryContinue.progressLine(book))"
                            + (LibraryContinue.leftLine(book).map { ", \($0)" } ?? ""))
        .accessibilityHint("Resumes it")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("library-continue-card")
    }
}
