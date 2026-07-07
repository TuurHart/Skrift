import SwiftUI

/// Root tab bar (audiobook reading-mode redesign 2026-06-19; Journal takes the
/// reserved Highlights slot 2026-07-07, per the signed `mocks/journal-retrieval.html`).
///
/// Replaces the old single-screen Memos root with Library + Settings hidden
/// behind toolbar `.sheet`s. The audiobook **Library is now a co-equal tab**, not
/// a sheet — a sheet's swipe-down-to-dismiss gesture stole pull-to-refresh, so you
/// couldn't resync the way you can in Notes (device feedback 2026-06-19). Notes ·
/// Library · Journal · Settings. P6's Highlights feed + Daily Review later land
/// as sections INSIDE Journal, not a fifth tab (JOURNAL_RETRIEVAL_PLAN.md).
///
/// Each tab owns its own navigation; the shared SwiftData model container +
/// environment flow down from `RootView` unchanged. The record FAB + audiobook
/// mini-player stay inside the Notes tab (they're notes-context chrome).
struct AppTabView: View {
    enum Tab: Hashable { case notes, library, journal, settings }
    @State private var selection: Tab = LaunchFlags.openJournal ? .journal
        : LaunchFlags.openSettings ? .settings : .notes

    var body: some View {
        TabView(selection: $selection) {
            MemosListView()
                .tabItem { Label("Notes", systemImage: "note.text") }
                .tag(Tab.notes)

            AudiobookLibraryView()
                .tabItem { Label("Library", systemImage: "book") }
                .tag(Tab.library)

            JournalHomeView()
                .tabItem { Label("Journal", systemImage: "clock.arrow.circlepath") }
                .tag(Tab.journal)

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(Tab.settings)
        }
        .tint(.skAccent)
    }
}
