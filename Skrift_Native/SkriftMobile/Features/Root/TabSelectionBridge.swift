import SwiftUI

/// Lets the app-level keyboard `.commands` (⌘1–⌘4, and the tab-switch half of
/// ⌘N/⌘F) drive the root tab selection from OUTSIDE the view tree. `AppTabView`
/// keeps its own `@State selection` (so `initialTab()` / `-openTab` routing is
/// unchanged) and just consumes a one-shot `requestedTab` posted here.
///
/// A singleton, mirroring `RecordingIntentBridge` / `MemoOpenBridge`: the App
/// struct has no view state, so a shared object is the seam a command handler
/// can reach.
final class TabSelectionBridge: ObservableObject {
    static let shared = TabSelectionBridge()
    private init() {}

    /// Set by a command; consumed (and cleared) by AppTabView's `.onChange`.
    @Published var requestedTab: AppTabView.Tab?

    func select(_ tab: AppTabView.Tab) { requestedTab = tab }
}
