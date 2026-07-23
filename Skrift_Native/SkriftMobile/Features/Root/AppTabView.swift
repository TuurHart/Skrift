import SwiftUI

/// Root tab bar: **Notes · Books · Journal · Settings** (audiobook reading-mode
/// redesign 2026-06-19; Books rename + Journal 2026-07-07).
///
/// - The audiobook library is a co-equal tab (not a sheet — a sheet's
///   swipe-down-to-dismiss stole pull-to-refresh, device feedback 2026-06-19),
///   renamed **Books** (`mocks/books-tab-and-resume.html`).
/// - **Journal** took the reserved Highlights slot (signed
///   `mocks/journal-retrieval.html`); P6's Highlights feed + Daily Review later
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
        if LaunchFlags.openJournal { return .journal }
        if LaunchFlags.openSettings { return .settings }
        return .notes
    }

    @State private var selection: Tab = AppTabView.initialTab()
    /// `-showTOCSheet` screenshot hook (see the `.sheet` below).
    @State private var showSeededTOC = false
    /// Keyboard `.commands` (⌘1–⌘4 + the tab-switch half of ⌘N/⌘F) post here.
    @ObservedObject private var tabBridge = TabSelectionBridge.shared
    /// `-showTextSheet` / `-showTextPrompt` screenshot hooks (unified "Text" sheet + A0).
    @State private var showSeededText = false
    @State private var showSeededTextPrompt = false

    var body: some View {
        TabView(selection: $selection) {
            MemosListView()
                .tabItem { Label(SharedCopy.notesTitle, systemImage: "note.text") }
                .tag(Tab.notes)

            AudiobookLibraryView()
                .tabItem { Label("Books", systemImage: "book") }
                .tag(Tab.books)

            JournalHomeView()
                // Display name = SharedCopy.reviewTitle (Tuur, 2026-07-07) — internal
                // ids stay `journal` (the `-openTab journal` flag + file names are
                // shared API across lanes; renaming code churns for zero user value).
                .tabItem { Label(SharedCopy.reviewTitle, systemImage: "clock.arrow.circlepath") }
                .tag(Tab.journal)

            SettingsView()
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
        // Let the app-level keyboard shortcuts switch tabs (⌘1–⌘4, and the
        // tab-focus half of ⌘N/⌘F). One-shot: consume + clear.
        .onChange(of: tabBridge.requestedTab) { _, tab in
            if let tab { selection = tab; tabBridge.requestedTab = nil }
        }
        // Sim seed hooks only (screenshots/UITests — a real book is device-only,
        // which is how the build-40 overlap shipped unseen): `-seedAudiobook`
        // fabricates a LIVE session (the V2a pill state); `-seedAudiobookIdle`
        // seeds a played book with NO session (the Continue-listening card
        // state). Launch-restore was REMOVED 2026-07-07: the card on Notes
        // replaced the phantom paused session — cards for starting, chrome for
        // controlling; a session exists only once you actually play.
        .task {
            if LaunchFlags.seedAudiobook { AudiobookSeeder.seedAndOpen() }
            else if LaunchFlags.seedAudiobookIdle { AudiobookSeeder.seedOnly() }
            // `-resumeBook`: open the last-played REAL book paused — the same
            // book-open path a library tap runs (incl. `alignIfNeeded`), for
            // headless device verification over devicectl.
            else if LaunchFlags.resumeBook,
                    let recent = AudiobookLibraryStore.shared.sortedByRecent.first {
                _ = AudiobookSession.shared.open(recent, autoplay: false)
            }
            if LaunchFlags.showTOCSheet { showSeededTOC = true }
            if LaunchFlags.showTextSheet { showSeededText = true }
            if LaunchFlags.showTextPrompt { showSeededTextPrompt = true }
        }
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
