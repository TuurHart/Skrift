import SwiftUI

/// Root tab bar (audiobook reading-mode redesign 2026-06-19; reshaped 2026-07-07
/// by TWO converging chats): **Notes · Books · Journal · Settings**.
///
/// - The audiobook library is a co-equal tab (not a sheet — a sheet's
///   swipe-down-to-dismiss stole pull-to-refresh, device feedback 2026-06-19),
///   renamed **Books** (Library→Books, `mocks/books-tab-and-resume.html`).
/// - **Journal** took the reserved Highlights slot (signed
///   `mocks/journal-retrieval.html`); the Highlights placeholder tab was cut the
///   same day by the Books chat — both agreed a bare captured-quotes tab never
///   earned its slot. P6's Highlights feed + Daily Review later land as sections
///   INSIDE Journal, not a fifth tab (JOURNAL_RETRIEVAL_PLAN.md); per-book notes
///   belong in the book context.
///
/// Each tab owns its own navigation; the shared SwiftData model container +
/// environment flow down from `RootView` unchanged. The record FAB stays inside
/// the Notes tab. The audiobook mini-player is GLOBAL (2026-07-06): mounted as a
/// bottom `safeAreaInset` on every tab, so the listening session keeps one body
/// wherever you are — and scroll views automatically make room for it.
struct AppTabView: View {
    enum Tab: Hashable { case notes, books, journal, settings }
    @State private var selection: Tab = LaunchFlags.openJournal ? .journal : .notes

    var body: some View {
        TabView(selection: $selection) {
            MemosListView()
                .safeAreaInset(edge: .bottom) { GlobalMiniPlayerMount() }
                .tabItem { Label("Notes", systemImage: "note.text") }
                .tag(Tab.notes)

            AudiobookLibraryView()
                .safeAreaInset(edge: .bottom) { GlobalMiniPlayerMount() }
                .tabItem { Label("Books", systemImage: "book") }
                .tag(Tab.books)

            JournalHomeView()
                .safeAreaInset(edge: .bottom) { GlobalMiniPlayerMount() }
                .tabItem { Label("Journal", systemImage: "clock.arrow.circlepath") }
                .tag(Tab.journal)

            SettingsView()
                .safeAreaInset(edge: .bottom) { GlobalMiniPlayerMount() }
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(Tab.settings)
        }
        .tint(.skAccent)
        // Launch restore: arm the most recently played book as a PAUSED session so
        // "continue my book" is one tap (play on the capsule) from wherever you
        // land — no Books-dig. Never auto-plays (surprise audio on launch is
        // wrong); open() bails safely if the audio isn't on disk. Skipped under
        // the UI-test store flag so hermetic tests never inherit a sim library.
        .task {
            guard !LaunchFlags.inMemoryStore else { return }
            AudiobookSession.shared.restoreOnLaunch()
        }
    }
}

/// The cross-tab mini-player mount: renders the glass capsule only while a book
/// session is active, with the same slide-in the old Notes-only mount had. A tiny
/// wrapper view so only IT re-renders on session ticks — the TabView shell above
/// observes nothing.
private struct GlobalMiniPlayerMount: View {
    @ObservedObject private var session = AudiobookSession.shared

    var body: some View {
        Group {
            if session.isActive {
                AudiobookMiniPlayerBar()
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(Theme.Motion.spring, value: session.isActive)
    }
}
