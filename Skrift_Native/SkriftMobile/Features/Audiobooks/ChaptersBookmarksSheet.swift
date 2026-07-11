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
            let current = book.chapterIndex(at: session.currentTime)
            List {
                ForEach(Array(book.effectiveChapters.enumerated()), id: \.offset) { i, ch in
                    Button {
                        session.seek(to: ch.start); dismiss()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: i == current ? "play.fill" : "circle.fill")
                                .font(.system(size: i == current ? 10 : 5))
                                .foregroundStyle(i == current ? Color.skAccent : Color.skTextFaint)
                                .frame(width: 14)
                            Text(titles[i])
                                .font(.system(size: 14.5, weight: i == current ? .semibold : .regular))
                                .foregroundStyle(i == current ? Color.skText : Color.skTextDim)
                            Spacer()
                            Text(AudiobookTime.clock(ch.start))
                                .font(.system(size: 12)).monospacedDigit()
                                .foregroundStyle(Color.skTextFaint)
                        }
                    }
                    .listRowBackground(Color.skBg)
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
                    Button {
                        session.seek(to: bm.position); dismiss()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "bookmark.fill")
                                .font(.system(size: 11)).foregroundStyle(Color.skAccent).frame(width: 14)
                            Text(bm.chapterLabel ?? "Bookmark")
                                .font(.system(size: 14.5)).foregroundStyle(Color.skText).lineLimit(1)
                            Spacer()
                            Text(AudiobookTime.clock(bm.position))
                                .font(.system(size: 12)).monospacedDigit()
                                .foregroundStyle(Color.skTextFaint)
                        }
                    }
                    .listRowBackground(Color.skBg)
                }
                .onDelete { offsets in
                    for i in offsets { bookmarks = store.remove(id: bookmarks[i].id, bookID: book.id) }
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
