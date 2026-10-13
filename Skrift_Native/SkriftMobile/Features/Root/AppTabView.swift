import FeedbackKit
import SwiftUI

/// Root tab bar: **Notes · Library · Review · Settings** (audiobook reading-mode
/// redesign 2026-06-19; Books rename + Journal 2026-07-07; Books → Library Q352, the Q6 mock).
///
/// - The audiobook library is a co-equal tab (not a sheet — a sheet's
///   swipe-down-to-dismiss stole pull-to-refresh, device feedback 2026-06-19),
///   renamed **Books** (`mocks/books-tab-and-resume.html`).
/// - **Journal** took the reserved Highlights slot (signed
///   `mocks/`-openTab books|journal|settings` (screenshot/UITest routing), else Notes.-retrieval.html`); P6's Highlights feed + Daily Review later
///   land as sections INSIDE Journal, not a fifth tab.
///
/// Audiobook chrome scope (2026-07-07 bottom-chrome redesign,
/// `mocks/notes-bottom-chrome.html` Option A — replaces the build-40 global
/// `safeAreaInset` mount, which iOS 26 never propagated into the tabs'
/// NavigationStacks, burying the record button under the capsule):
/// - **Notes** hosts the compact `AudiobookMiniPill` beside the record button
///   (one row, mounted INSIDE `MemosListView` — see `bottomChrome`).
/// - **Books** hosts the full `AudiobookMiniPlayerBar` (mounted inside
///   `AudiobookLibraryView`).
/// - **Journal / Settings** carry no audiobook chrome (user call: you don't
///   start a book from there).
struct AppTabView: View {
    enum Tab: Hashable { case notes, books, journal, settings }

    /// `-openTab books|journal|settings` (screenshot/UITest routing) wins, then
    /// the older single-tab flags, else Notes.
    private static func initialTab() -> Tab {
        switch LaunchFlags.openTab {
        case "books": return .books
        case "journal": return .journal
        case "settings": return .settings
        default: break
        }
        return .notes
    }

    @State private var selection: Tab = AppTabView.initialTab()
    /// `-showTOCSheet` screenshot hook (see the `.sheet` below).
    @State private var showSeededTOC = false
    @State private var showTileGallery = false
    @State private var showSeededPlayer = false
    /// Keyboard `.commands` (⌘1–⌘4 + the tab-switch half of ⌘N/⌘F) post here.
    @ObservedObject private var tabBridge = TabSelectionBridge.shared
    /// `-showTextSheet` / `-showTextPrompt` screenshot hooks (unified "Text" sheet + A0).
    @State private var showSeededText = false
    @State private var showSeededTextPrompt = false
    /// Q379 tabs option A: at regular width the tabs are `IPadTabControl` at the top of the list
    /// column and the system tab bar is hidden (`ipadTabChrome`).
    @Environment(\.horizontalSizeClass) private var hSize

    var body: some View {
        TabView(selection: $selection) {
            MemosListView()
                .ipadTabChrome(hSize, hostsOwnRow: true)
                .feedbackScreen("Notes")   // Q299: newest visible tag wins (a pushed note/sheet)
                .tabItem { Label(SharedCopy.notesTitle, systemImage: "note.text") }
                .tag(Tab.notes)

            AudiobookLibraryView()
                .ipadTabChrome(hSize, hostsOwnRow: false)
                .feedbackScreen("Library")
                .tabItem { Label("Library", systemImage: "book") }
                .tag(Tab.books)

            JournalHomeView()
                .ipadTabChrome(hSize, hostsOwnRow: false)
                .feedbackScreen(SharedCopy.reviewTitle)
                // Display name = SharedCopy.reviewTitle (Tuur, 2026-07-07) — internal
                // ids stay `journal` (the `-openTab journal` flag + file names are
                // shared API across lanes; renaming code churns for zero user value).
                .tabItem { Label(SharedCopy.reviewTitle, systemImage: "clock.arrow.circlepath") }
                .tag(Tab.journal)

            SettingsView()
                .ipadTabChrome(hSize, hostsOwnRow: false)
                .feedbackScreen("Settings")
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(Tab.settings)
        }
        .tint(.skAccent)
        // iPadOS 18 top tab strip (+ a free sidebar the user can pull open);
        // compact width falls back to the standard bottom tab bar, so the phone
        // is pixel-untouched. `selection`/`-openTab` routing is unaffected.
        // .tabBarOnly (Tuur, live iPad round 2026-07-23): the system's sidebar
        // mode duplicated four tabs into a whole column — "weird and
        // unnecessary. just keep it up top."
        .tabViewStyle(.tabBarOnly)
        .environment(\.ipadTab, IPadTabContext(current: selection, select: { selection = $0 }))
        // Let the app-level keyboard shortcuts switch tabs (⌘1–⌘4, and the
        // tab-focus half of ⌘N/⌘F). One-shot: consume + clear.
        .onChange(of: tabBridge.requestedTab) { _, tab in
            if let tab { selection = tab; tabBridge.requestedTab = nil }
        }
        // Sim seed hooks only (screenshots/UITests — a real book is device-only,
        // which is how the build-40 overlap shipped unseen): `-seedAudiobook`
        // fabricates a LIVE session (the V2a pill state). A session exists only once you
        // actually play (launch-restore was removed 2026-07-07).
        .task {
            var seeded = false
            #if DEBUG
            if LaunchFlags.seedAudiobook { AudiobookSeeder.seedAndOpen(); seeded = true }
            else if LaunchFlags.seedLibraryShelf { AudiobookSeeder.seedShelf(); seeded = true }
            else if LaunchFlags.seedEpisode { AudiobookSeeder.seedEpisode(); seeded = true }
            if LaunchFlags.showPlayer { showSeededPlayer = true }
            if LaunchFlags.showSentNote, let first = AudiobookLibraryStore.shared.sortedByRecent.first,
               let id = LibraryHatch.sendToNote(book: first) {
                TabSelectionBridge.shared.select(.notes)
                MemoOpenBridge.shared.open(id)
            }
            #endif
            // `-resumeBook`: open the last-played REAL book paused — the same
            // book-open path a library tap runs (incl. `alignIfNeeded`), for
            // headless device verification over devicectl.
            if !seeded, LaunchFlags.resumeBook,
               let recent = AudiobookLibraryStore.shared.sortedByRecent.first {
                _ = AudiobookSession.shared.open(recent, autoplay: false)
            }
            if LaunchFlags.showTOCSheet { showSeededTOC = true }
            #if DEBUG
            if LaunchFlags.showBookTileGallery { showTileGallery = true }
            #endif
            if LaunchFlags.showTextSheet { showSeededText = true }
            if LaunchFlags.showTextPrompt { showSeededTextPrompt = true }
        }
        #if DEBUG
        .fullScreenCover(isPresented: $showTileGallery) { BookTileGallery() }
        // `-showPlayer` (Q353): the full player over the seeded session, for screenshots.
        .fullScreenCover(isPresented: $showSeededPlayer) { AudiobookPlayerView() }
        #endif
        // `-showTOCSheet`: render the Chapters/Bookmarks sheet over the seeded
        // book — a deterministic screenshot without UI-test taps.
        .sheet(isPresented: $showSeededTOC) {
            if let book = AudiobookSession.shared.book {
                ChaptersBookmarksSheet(book: book)
            }
        }
        // `-showTextSheet` / `-showTextPrompt`: the unified "Text" sheet + the A0
        // prompt over the seeded book (Add is inert here — render-only hooks).
        .sheet(isPresented: $showSeededText) {
            if let book = AudiobookSession.shared.book ?? AudiobookLibraryStore.shared.sortedByRecent.first {
                BookTextSheet(book: book, busyMessage: nil) {}
            }
        }
        .sheet(isPresented: $showSeededTextPrompt) {
            if let book = AudiobookSession.shared.book ?? AudiobookLibraryStore.shared.sortedByRecent.first {
                BookTextPromptSheet(book: book) {}
            }
        }
    }
}
