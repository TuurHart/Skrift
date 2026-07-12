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

    var body: some View {
        TabView(selection: $selection) {
            MemosListView()
                .tabItem { Label("Notes", systemImage: "note.text") }
                .tag(Tab.notes)

            AudiobookLibraryView()
                .tabItem { Label("Books", systemImage: "book") }
                .tag(Tab.books)

            JournalHomeView()
                // Display name "Review" (Tuur, 2026-07-07) — internal ids stay
                // `journal` (the `-openTab journal` flag + file names are shared
                // API across lanes; renaming code churns for zero user value).
                .tabItem { Label("Review", systemImage: "clock.arrow.circlepath") }
                .tag(Tab.journal)

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(Tab.settings)
        }
        .tint(.skAccent)
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
            if LaunchFlags.showTOCSheet { showSeededTOC = true }
        }
        // `-showTOCSheet`: render the Chapters/Bookmarks sheet over the seeded
        // book — a deterministic screenshot without UI-test taps.
        .sheet(isPresented: $showSeededTOC) {
            if let book = AudiobookSession.shared.book {
                ChaptersBookmarksSheet(book: book)
            }
        }
    }
}
