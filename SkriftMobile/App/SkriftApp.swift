import SwiftUI

@main
struct SkriftApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

/// Phase 0 placeholder. Replaced by the real tab shell (Memos / Record /
/// Settings) in later phases — see MOBILE_NATIVE_REWRITE_PLAN.md.
struct RootView: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("Skrift")
                .font(.largeTitle.bold())
                .accessibilityIdentifier("app-title")
            Text("Native rewrite — Phase 0")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("app-subtitle")
        }
        .accessibilityIdentifier("root-view")
    }
}
