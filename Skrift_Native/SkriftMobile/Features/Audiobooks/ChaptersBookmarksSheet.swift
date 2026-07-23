import SwiftUI

/// The table-of-contents sheet (player redesign): Chapters | Bookmarks tabs,
/// reached from the slim Chapters/Bookmark row on the player. Promotes chapters
/// out of the ⋯ menu (the user couldn't find them there) and is the home for the
/// lightweight position bookmarks.
struct ChaptersBookmarksSheet: View {
    let book: Audiobook
    /// Which tab opens first — the Bookmark button deep-links to .bookmarks.
    var initialTab: Tab = .chapters

    @ObservedObject private var session = AudiobookSession.shared
    @Environment(\.dismiss) private var dismiss
    @State private var tab: Tab
    @State private var bookmarks: [AudiobookBookmark] = []
    private let store = BookmarkStore()

    enum Tab { case chapters, bookmarks }

    init(book: Audiobook, initialTab: Tab = .chapters) {
        self.book = book
        self.initialTab = initialTab
        _tab = State(initialValue: initialTab)
    }

    var body: some View {
        VStack(spacing: 0) {
            Capsule().fill(Color.skBorder).frame(width: 36, height: 4)
                .padding(.top, 10).padding(.bottom, 14)

            Picker("", selection: $tab) {
                Text("Chapters").tag(Tab.chapters)
                Text("Bookmarks").tag(Tab.bookmarks)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16).padding(.bottom, 8)

            switch tab {
            case .chapters:  chaptersList
            case .bookmarks: bookmarksList
            }
        }
        .background(Color.skBg.ignoresSafeArea())
        .onAppear { bookmarks = store.load(bookID: book.id) }
        .accessibilityIdentifier("toc-sheet")
    }

    // MARK: - Chapters

    @ViewBuilder
    private var chaptersList: some View {
        if book.effectiveChapters.isEmpty {
            empty("No chapters", "This book has no chapter marks.")
        } else {
            let titles = book.displayChapterTitles
            let current = book.chapterIndex(at: session.currentTime)   // playable index
            let playableIndex = chapterPlayableIndices(book)
            List {
                ForEach(Array(book.effectiveChapters.enumerated()), id: \.offset) { i, ch in
                    if ch.isSeparator == true {
                        // A divider between WORKS (multi-book import) — a
                        // section header, not a chapter: no bullet, no time,
                        // not tappable, excluded from every count.
                        AudiobookChapterSeparator(title: titles[i])
                            .listRowBackground(Color.skBg)
                            .listRowSeparator(.hidden)
                    } else {
                        AudiobookChapterRow(title: titles[i], time: ch.start, isCurrent: playableIndex[i] == current) {
                            session.seek(to: ch.start); dismiss()
                        }
                        .listRowBackground(Color.skBg)
                    }
                }
            }
            .listStyle(.plain)
        }
    }

    // MARK: - Bookmarks

    @ViewBuilder
    private var bookmarksList: some View {
        if bookmarks.isEmpty {
            // (Copy fixed 2026-07-06 — the bottom "Mark" button is long gone;
            // folding the page corner in the reader's margin is the gesture.)
            empty("No bookmarks yet", "Tap the page corner beside the line you're hearing to fold a bookmark there.")
        } else {
            List {
                ForEach(bookmarks) { bm in
                    AudiobookBookmarkRow(bookmark: bm) {
                        session.seek(to: bm.position); dismiss()
                    }
                    .listRowBackground(Color.skBg)
                }
                .onDelete { offsets in
                    for i in offsets { bookmarks = store.remove(id: bookmarks[i].id, bookID: book.id) }
                    AudiobookCloudSync.bookmarksChanged(bookID: book.id)   // push-on-edit (synced books)
                }
            }
            .listStyle(.plain)
        }
    }

    private func empty(_ title: String, _ subtitle: String) -> some View {
        VStack(spacing: 7) {
            Spacer()
            Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Color.skText)
            Text(subtitle).font(.system(size: 12.5)).foregroundStyle(Color.skTextDim)
                .multilineTextAlignment(.center).padding(.horizontal, 40)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Row i of `book.effectiveChapters` → its index among PLAYABLE chapters (nil
/// for a "Book N" separator) — shared by the sheet's List and the standing
/// rail so both index the current-highlight identically.
func chapterPlayableIndices(_ book: Audiobook) -> [Int?] {
    var out: [Int?] = []
    var p = 0
    for ch in book.effectiveChapters {
        if ch.isSeparator == true { out.append(nil) } else { out.append(p); p += 1 }
    }
    return out
}

// MARK: - Reusable rows (bare — chrome/padding is the host's job, so the
// sheet's List rendering above stays pixel-identical to before this refactor)

/// One chapter row — shared by the sheet's List and the standing rail.
struct AudiobookChapterRow: View {
    let title: String
    let time: TimeInterval
    let isCurrent: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: isCurrent ? "play.fill" : "circle.fill")
                    .font(.system(size: isCurrent ? 10 : 5))
                    .foregroundStyle(isCurrent ? Color.skAccent : Color.skTextFaint)
                    .frame(width: 14)
                Text(title)
                    .font(.system(size: 14.5, weight: isCurrent ? .semibold : .regular))
                    .foregroundStyle(isCurrent ? Color.skText : Color.skTextDim)
                Spacer()
                Text(AudiobookTime.clock(time))
                    .font(.system(size: 12)).monospacedDigit()
                    .foregroundStyle(Color.skTextFaint)
            }
        }
    }
}

/// A "Book N" divider between WORKS — display-only (excluded from every
/// count/index; not tappable).
struct AudiobookChapterSeparator: View {
    let title: String
    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 11.5, weight: .semibold))
            .kerning(1.1)
            .foregroundStyle(Color.skTextFaint)
            .padding(.top, 10).padding(.bottom, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One bookmark row — shared by the sheet's List and the standing rail.
struct AudiobookBookmarkRow: View {
    let bookmark: AudiobookBookmark
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "bookmark.fill")
                    .font(.system(size: 11)).foregroundStyle(Color.skAccent).frame(width: 14)
                Text(bookmark.chapterLabel ?? "Bookmark")
                    .font(.system(size: 14.5)).foregroundStyle(Color.skText).lineLimit(1)
                Spacer()
                Text(AudiobookTime.clock(bookmark.position))
                    .font(.system(size: 12)).monospacedDigit()
                    .foregroundStyle(Color.skTextFaint)
            }
        }
    }
}

// MARK: - Standing rail (iPad wave, regular width — mock `ipad-app.html` m6)

/// The RIGHT-column rail hosted inline by the wide player: the sheet's SAME
/// row rendering + "current" semantics, but both sections STACKED in one
/// scroll (mock's `.chaps` pane) instead of tabbed — chapters above,
/// bookmarks below, exactly as m6 draws it. Parent-driven (no store reads of
/// its own): `currentTime`/`bookmarks` come from the player's own state, so
/// the rail can never show something the read-along margin glyphs disagree
/// with. Selecting a row seeks; there's nothing to dismiss — it's a standing
/// pane, not a sheet.
struct ChaptersBookmarksRail: View {
    let book: Audiobook
    let currentTime: TimeInterval
    let bookmarks: [AudiobookBookmark]
    var onSelectChapter: (AudiobookChapter) -> Void
    var onSelectBookmark: (AudiobookBookmark) -> Void
    var onDeleteBookmark: (AudiobookBookmark) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                SectionLabel("CHAPTERS")
                    .padding(.horizontal, 14).padding(.top, 16).padding(.bottom, 6)
                chaptersSection
                if !bookmarks.isEmpty {
                    SectionLabel("BOOKMARKS")
                        .padding(.horizontal, 14).padding(.top, 18).padding(.bottom, 6)
                    bookmarksSection
                }
            }
            .padding(.bottom, 24)
        }
        .accessibilityIdentifier("ipad-chapters-rail")
    }

    @ViewBuilder
    private var chaptersSection: some View {
        // Honest partial-chapter states: no chapters from ANY source (embedded/
        // detected/ePub) says so plainly rather than fabricating a "Chapter 1".
        if book.effectiveChapters.isEmpty {
            Text("No chapters yet.")
                .font(.system(size: 12)).foregroundStyle(Color.skTextFaint)
                .padding(.horizontal, 14)
        } else {
            let titles = book.displayChapterTitles
            let current = book.chapterIndex(at: currentTime)
            let playableIndex = chapterPlayableIndices(book)
            ForEach(Array(book.effectiveChapters.enumerated()), id: \.offset) { i, ch in
                if ch.isSeparator == true {
                    AudiobookChapterSeparator(title: titles[i])
                        .padding(.horizontal, 14)
                } else {
                    let isCurrent = playableIndex[i] == current
                    AudiobookChapterRow(title: titles[i], time: ch.start, isCurrent: isCurrent) {
                        onSelectChapter(ch)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 7)
                    .background(
                        isCurrent ? Color.skAccentSoft : Color.clear,
                        in: .rect(cornerRadius: 8, style: .continuous)
                    )
                    .padding(.horizontal, 6)
                }
            }
        }
    }

    @ViewBuilder
    private var bookmarksSection: some View {
        ForEach(bookmarks) { bm in
            AudiobookBookmarkRow(bookmark: bm) { onSelectBookmark(bm) }
                .padding(.horizontal, 8).padding(.vertical, 7)
                .padding(.horizontal, 6)
                .contextMenu {
                    Button(role: .destructive) { onDeleteBookmark(bm) } label: {
                        Label("Remove bookmark", systemImage: "trash")
                    }
                }
        }
    }
}
