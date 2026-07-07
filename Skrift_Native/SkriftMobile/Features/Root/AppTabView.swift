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

    var body: some View {
        TabView(selection: $selection) {
            MemosListView()
                .tabItem { Label("Notes", systemImage: "note.text") }
                .tag(Tab.notes)

            AudiobookLibraryView()
                .tabItem { Label("Books", systemImage: "book") }
                .tag(Tab.books)

            JournalHomeView()
                .tabItem { Label("Journal", systemImage: "clock.arrow.circlepath") }
                .tag(Tab.journal)

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(Tab.settings)
        }
        .tint(.skAccent)
        // Launch restore: arm the most recently played book as a PAUSED session so
        // "continue my book" is one tap (play on the pill) from where you land —
        // no Books-dig. Never auto-plays (surprise audio on launch is wrong);
        // open() bails safely if the audio isn't on disk. `-seedAudiobook`
        // fabricates the session instead (sim screenshots — a real book is
        // device-only, which is how the build-40 overlap shipped unseen).
        .task {
            if LaunchFlags.seedAudiobook {
                AudiobookSeeder.seedAndOpen()
                return
            }
            guard !LaunchFlags.inMemoryStore else { return }
            AudiobookSession.shared.restoreOnLaunch()
        }
    }
}
