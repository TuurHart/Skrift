import SwiftUI

/// Root tab bar (audiobook reading-mode redesign 2026-06-19; trimmed 2026-07-06).
///
/// Notes · Books · Settings. The audiobook library ("Books") is a co-equal tab,
/// not a sheet — a sheet's swipe-down-to-dismiss gesture stole pull-to-refresh
/// (device feedback 2026-06-19). The Highlights placeholder tab was CUT
/// 2026-07-06: captures already live in Notes (book glyph + ❝-quote rows), so a
/// tab-level filtered duplicate never earned its slot; a per-book notes surface
/// belongs in the book context instead.
///
/// Each tab owns its own navigation; the shared SwiftData model container +
/// environment flow down from `RootView` unchanged. The record FAB stays inside
/// the Notes tab. The audiobook mini-player is GLOBAL (2026-07-06): mounted as a
/// bottom `safeAreaInset` on every tab, so the listening session keeps one body
/// wherever you are — and scroll views automatically make room for it.
struct AppTabView: View {
    enum Tab: Hashable { case notes, books, settings }
    @State private var selection: Tab = .notes

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

            SettingsView()
                .safeAreaInset(edge: .bottom) { GlobalMiniPlayerMount() }
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(Tab.settings)
        }
        .tint(.skAccent)
        // Launch restore: arm the most recently played book as a PAUSED session so
        // "continue my book" is one tap (play on the capsule) from wherever you
        // land — no Library-dig. Never auto-plays (surprise audio on launch is
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
