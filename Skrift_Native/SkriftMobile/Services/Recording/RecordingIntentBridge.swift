import Combine
import Foundation

/// Bridges App Intents (Control Center button, Siri shortcut, Live Activity Stop)
/// to the existing record UI. The intents themselves only touch their own
/// `static performer` closure (so they compile in the widget target too); the app
/// wires those performers to bump these counters at launch. The record screen
/// observes the counters via `.onChange` and routes to its existing
/// `startTapped()` / `stopTapped()` handlers — no refactor of the tested flow.
///
/// Monotonic counters (not a clearable command) sidestep "who clears it" races.
/// All intents use `openAppWhenRun: true`, so the app is foregrounded before the
/// counter bumps and SwiftUI reliably delivers the `.onChange`.
@MainActor
final class RecordingIntentBridge: ObservableObject {
    static let shared = RecordingIntentBridge()
    @Published private(set) var startRequestID = 0
    @Published private(set) var stopRequestID = 0
    private var consumedStartID = 0
    private init() {}

    func requestStart() { startRequestID += 1 }
    func requestStop() { stopRequestID += 1 }

    /// True at most once per `requestStart()`. RecordView calls this when it's
    /// ready to auto-start (foreground-active), so a fresh intent/Siri/widget
    /// request triggers recording exactly once. Reading the singleton directly
    /// (set at intent time, before the view appears) avoids the @State→cover
    /// propagation race that left a passed-in `autoStart` flag stale on cold
    /// launch. The FAB calls `clearPendingStart()` so a stale request can't
    /// auto-start a manually-opened recorder.
    func consumePendingStart() -> Bool {
        guard startRequestID > consumedStartID else { return false }
        consumedStartID = startRequestID
        return true
    }

    func clearPendingStart() { consumedStartID = startRequestID }
}
