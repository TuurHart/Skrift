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
/// Names push from there. First launch shows onboarding.
struct RootView: View {
    @State private var needsOnboarding = RootView.shouldOnboard()

    var body: some View {
        if needsOnboarding {
            OnboardingView {
                UserDefaults.standard.set(true, forKey: "onboardingComplete")
                withAnimation(Theme.Motion.spring) { needsOnboarding = false }
            }
        } else {
            MemosListView()
        }
    }

    private static func shouldOnboard() -> Bool {
        if LaunchFlags.skipOnboarding { return false }
        if LaunchFlags.forceOnboarding { return true }
        if LaunchFlags.inMemoryStore { return false }   // UI tests auto-skip
        return !UserDefaults.standard.bool(forKey: "onboardingComplete")
    }
}
