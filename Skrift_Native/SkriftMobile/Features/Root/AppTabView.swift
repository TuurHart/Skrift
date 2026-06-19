import SwiftUI

/// Root tab bar (audiobook reading-mode redesign, 2026-06-19).
///
/// Replaces the old single-screen Memos root with Library + Settings hidden
/// behind toolbar `.sheet`s. The audiobook **Library is now a co-equal tab**, not
/// a sheet — a sheet's swipe-down-to-dismiss gesture stole pull-to-refresh, so you
/// couldn't resync the way you can in Notes (device feedback 2026-06-19). Notes ·
/// Library · Highlights(soon) · Settings, matching `mocks/audiobook-player-reading-
/// mode.html` screen 1.
///
/// Each tab owns its own navigation; the shared SwiftData model container +
/// environment flow down from `RootView` unchanged. The record FAB + audiobook
/// mini-player stay inside the Notes tab (they're notes-context chrome).
struct AppTabView: View {
    enum Tab: Hashable { case notes, library, highlights, settings }
    @State private var selection: Tab = .notes

    var body: some View {
        TabView(selection: $selection) {
            MemosListView()
                .tabItem { Label("Notes", systemImage: "note.text") }
                .tag(Tab.notes)

            AudiobookLibraryView()
                .tabItem { Label("Library", systemImage: "book") }
                .tag(Tab.library)

            HighlightsComingSoonView()
                .tabItem { Label("Highlights", systemImage: "bookmark") }
                .tag(Tab.highlights)

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(Tab.settings)
        }
        .tint(.skAccent)
    }
}

/// The Phase-6 "Highlights" slot — a Commonplace-Book / captured-quotes surface
/// that doesn't exist yet. Shown as a placeholder so the tab is present in the IA
/// (the mock dims it "soon"); stock `TabView` can't dim a single tab item, so the
/// "coming soon" cue lives in the screen body for now.
struct HighlightsComingSoonView: View {
    var body: some View {
        ZStack {
            Color.skBg.ignoresSafeArea()
            VStack(spacing: 10) {
                Image(systemName: "bookmark")
                    .font(.system(size: 34))
                    .foregroundStyle(Color.skAccent.opacity(0.85))
                Text("Highlights")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.skText)
                Text("Your captured quotes and highlights will gather here.\nComing soon.")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.skTextDim)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }
            .padding(.horizontal, 44)
        }
        .accessibilityIdentifier("highlights-coming-soon")
    }
}
