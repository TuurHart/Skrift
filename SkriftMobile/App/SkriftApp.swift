import SwiftUI
import SwiftData

@main
struct SkriftApp: App {
    private let repository: NotesRepository

    init() {
        let repo = NotesRepository.shared
        DemoDataSeeder.seedIfRequested(repo)
        repository = repo
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .modelContainer(repository.container)
        }
    }
}

/// Phase 1 shell. The real tab shell (Memos / Record / Settings) arrives in
/// later phases — see MOBILE_NATIVE_REWRITE_PLAN.md.
struct RootView: View {
    var body: some View {
        MemosListView()
    }
}
