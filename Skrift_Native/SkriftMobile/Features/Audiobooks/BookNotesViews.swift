import SwiftUI
import SwiftData

/// D127 / Q6 mock (`mocks/Q6-library-tab.html`, `.npill` + `notesSheet`): the per-book
/// "❝ N" pill and the sheet it opens. The pill is its own button, separate from the tile's
/// tap-to-play. Dumb views; `BookNotesJoin` does the counting and the jump.

/// The "❝ 5" pill: white 11pt bold on a 60% black blur capsule, 28pt tall.
struct BookNotesPill: View {
    let count: Int
    /// The compact row sits on a 54pt cover's neighbour, so it uses the smaller capsule.
    var compact = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text("\u{275D}")
                    .font(.system(size: compact ? 11 : 12, weight: .black))
                Text("\(count)")
                    .font(.system(size: compact ? 10.5 : 11, weight: .bold))
                    .monospacedDigit()
            }
            .foregroundStyle(.white)
            .padding(.horizontal, compact ? 8 : 9)
            .padding(.vertical, compact ? 5 : 6)
            .frame(minHeight: compact ? 24 : 28)
            .background(.black.opacity(0.6), in: .capsule)
            .background(.ultraThinMaterial, in: .capsule)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(BookNotesJoin.accessibilityLabel(count: count))
        .accessibilityIdentifier("book-notes-pill")
    }
}

/// "5 notes from <title>" — the book's capture notes, newest first. A row opens the note in
/// Notes (they live there; the sheet is a door, not a second home).
struct BookNotesSheet: View {
    let book: Audiobook
    let notes: [Memo]
    let onOpen: (Memo) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            SheetGrabber(top: 10)
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(notes.count) note\(notes.count == 1 ? "" : "s") from \(book.title)")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Color.skText)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("They live in Notes. Tap one to open it there.")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.skTextDim)
                }
                Spacer(minLength: 0)
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.skTextDim)
                        .frame(width: 30, height: 30)
                        .background(Color.skElev, in: .circle)
                }
                .accessibilityLabel("Close")
            }
            .padding(.horizontal, 20).padding(.top, 2).padding(.bottom, 12)

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(notes, id: \.id) { memo in
                        Button { onOpen(memo) } label: { row(memo) }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("book-notes-row")
                    }
                }
                .padding(.horizontal, 16).padding(.bottom, 30)
            }
        }
        .background(Color.skBg.ignoresSafeArea())
        .accessibilityIdentifier("book-notes-sheet")
    }

    private func row(_ memo: Memo) -> some View {
        let split = CaptureQuote.split(memo.transcript)
        return VStack(alignment: .leading, spacing: 6) {
            Text(memo.displayTitle)
                .font(.system(size: 14.5, weight: .semibold))
                .foregroundStyle(Color.skText)
                .lineLimit(1)
            if let quote = split?.displayText, !quote.isEmpty {
                Text(quote)
                    .font(.system(size: 13)).italic()
                    .foregroundStyle(Color.skTextDim)
                    .lineLimit(2)
                    .padding(.leading, 9)
                    .overlay(alignment: .leading) {
                        Capsule().fill(Color.skAccent.opacity(0.65)).frame(width: 3)
                    }
            }
            if let ramble = split?.ramble.trimmingCharacters(in: .whitespacesAndNewlines), !ramble.isEmpty {
                Text(ramble)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.skText)
                    .lineLimit(1)
            }
            Text(BookNotesJoin.metaLine(for: memo))
                .font(.system(size: 11))
                .monospacedDigit()
                .foregroundStyle(Color.skTextFaint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.skSurface, in: .rect(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(Color.skBorder, lineWidth: 0.5))
    }
}

/// The note page's jump-back (mock `.back`): "▶ Back to it at 1:12:05 in Library", under the
/// quote's attribution. 12.5pt semibold, accent text on the accent wash, 32pt tall.
struct BookJumpBackButton: View {
    let position: TimeInterval
    /// Q354: set for a PDF source: the label names the page and the glyph is the mock's "↗".
    let page: Int?
    /// Q355: an article's label ("Back to it at 31% in Library"); nil for the other kinds.
    var readingLabel: String? = nil
    let action: () -> Void

    init(position: TimeInterval, action: @escaping () -> Void) {
        self.position = position; self.page = nil; self.action = action
    }

    init(page: Int, action: @escaping () -> Void) {
        self.position = TimeInterval(page); self.page = page; self.action = action
    }

    /// Q356: the label and glyph follow the route (a PDF's page, an episode's or book's time).
    init(route: BookNotesJoin.JumpRoute, action: @escaping () -> Void) {
        switch route {
        case .page(let p): self.init(page: p, action: action)
        case .time(let t): self.init(position: t, action: action)
        case .reading(let word, _):
            self.init(position: TimeInterval(word), action: action)
            readingLabel = BookNotesJoin.jumpLabel(for: route)
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: page == nil && readingLabel == nil ? "play.fill" : "arrow.up.right").font(.system(size: 10))
                Text(readingLabel ?? page.map { BookNotesJoin.jumpLabel(page: $0) } ?? BookNotesJoin.jumpLabel(position: position))
                    .font(.system(size: 12.5, weight: .semibold))
            }
            .foregroundStyle(Color.skAccentText)
            .padding(.horizontal, 11).padding(.vertical, 7)
            .frame(minHeight: 32)
            .background(Color.skAccentSoft, in: .capsule)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("book-jump-back")
    }
}

// MARK: - Q322: the live-memo query, kept off the Books tab body

/// Owns the live-memo `@Query` for the Books tab. It re-evaluates on every note save (cheap: a
/// zero-size clear view) and writes `counts` only when they actually changed, so the Books body
/// behind the note editor does not re-run per keystroke commit.
struct BookNoteCountsFeed: View {
    @Binding var counts: [UUID: Int]
    @Query(filter: #Predicate<Memo> { $0.deletedAt == nil },
           sort: \Memo.recordedAt, order: .reverse) private var liveMemos: [Memo]

    private var key: BookNotesCountCache.Key {
        .init(version: NotesRepository.shared.memoSetVersion, count: liveMemos.count)
    }

    var body: some View {
        Color.clear.frame(width: 0, height: 0)
            .task(id: key) {
                let fresh = await BookNotesCountCache.shared.counts(for: liveMemos, key: key)
                if fresh != counts { counts = fresh }
            }
    }
}

/// The notes sheet with its own live-memo query (see `BookNoteCountsFeed`).
struct BookNotesSheetHost: View {
    let book: Audiobook
    let onOpen: (Memo) -> Void
    @Query(filter: #Predicate<Memo> { $0.deletedAt == nil },
           sort: \Memo.recordedAt, order: .reverse) private var liveMemos: [Memo]

    var body: some View {
        BookNotesSheet(book: book, notes: BookNotesJoin.notes(forBook: book.id, in: liveMemos), onOpen: onOpen)
    }
}

// MARK: - Q356: the link card and the source's notes row

/// The card "Send to a note" / "Move to Library" leaves in the note (mock `.srccard`): a 56pt
/// cover, the title (14pt semibold, two lines) and "PDF · p. 4 of 18 · open in Library ›" in
/// accent. Tap = the jump-back.
struct SourceLinkCard: View {
    let book: Audiobook
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                BookCoverView(book: book)
                    .frame(width: 56, height: 56)
                    .clipShape(.rect(cornerRadius: 8, style: .continuous))
                    .shadow(color: .black.opacity(0.3), radius: 3, y: 2)
                VStack(alignment: .leading, spacing: 3) {
                    Text(book.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.skText)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(LibraryHatch.cardDetail(for: book))
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(Color.skAccentText)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.skSurface, in: .rect(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.skBorder, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("source-link-card")
    }
}

/// "❝ 3 notes from this episode · Newest: … ›" under the player and the reader (mock
/// `srcNotesRow`). With no notes it says so and is not a button.
struct SourceNotesRow: View {
    let book: Audiobook
    let onOpen: () -> Void
    @Query(filter: #Predicate<Memo> { $0.deletedAt == nil },
           sort: \Memo.recordedAt, order: .reverse) private var liveMemos: [Memo]

    var body: some View {
        let notes = BookNotesJoin.notes(forBook: book.id, in: liveMemos)
        if notes.isEmpty {
            row(notes).accessibilityIdentifier("source-notes-row")
        } else {
            Button(action: onOpen) { row(notes) }
                .buttonStyle(.plain)
                .accessibilityIdentifier("source-notes-row")
        }
    }

    private func row(_ notes: [Memo]) -> some View {
        let detail = notes.first.map {
            LibraryHatch.notesRowDetail(newestTitle: $0.displayTitle, when: LibraryHatch.shortDate($0.recordedAt))
        } ?? LibraryHatch.notesRowEmptyDetail
        return HStack(spacing: 10) {
            Text("\u{275D}")
                .font(.system(size: 18, weight: .black))
                .foregroundStyle(Color.skAccentText)
            VStack(alignment: .leading, spacing: 1) {
                Text(LibraryHatch.notesRowTitle(count: notes.count, kind: book.sourceKind))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.skText)
                Text(detail)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.skTextDim)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if !notes.isEmpty {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.skTextFaint)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.skSurface, in: .rect(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(Color.skBorder, lineWidth: 0.5))
    }
}
