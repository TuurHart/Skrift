import SwiftUI
import SwiftData

@main
struct SkriftApp: App {
    private let repository: NotesRepository
    @AppStorage("appTheme") private var appTheme = "dark"

    init() {
        let repo = NotesRepository.shared
        DemoDataSeeder.seedIfRequested(repo)
        NamesSeeder.seedIfRequested()
        repository = repo
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .modelContainer(repository.container)
                .preferredColorScheme(colorScheme)
                .tint(.skAccent)
        }
    }

    // The palette is dark-first (explicit dark surfaces), so "auto"/"light" are
    // best-effort until a light palette lands; default stays dark.
    private var colorScheme: ColorScheme? {
        switch appTheme {
        case "light": return .light
        case "auto": return nil
        default: return .dark
        }
    }
}

/// App shell. The mockups are a NavigationStack flow rooted at Memos (no tab
/// bar): Record presents over it, Memo detail pushes from a card, Settings /
/// Names push from there. The per-screen surfaces are built in Phase 7.
struct RootView: View {
    var body: some View {
        MemosListView()
    }
}
