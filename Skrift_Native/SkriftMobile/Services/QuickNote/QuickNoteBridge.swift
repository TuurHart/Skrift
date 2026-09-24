import Combine
import Foundation

/// Bridges a "New Note" request (Lock Screen widget / Control Center / Siri /
/// `skrift://newnote`) to the list's navigation. Mirrors `RecordingIntentBridge`
/// and `MemoOpenBridge`: a monotonic counter (not a clearable command) so a
/// request that fires during a COLD launch (widget/Siri opening the app fresh)
/// isn't missed by the time `MemosListView` subscribes, and several rapid
/// requests can't race on "who clears it".
@MainActor
final class QuickNoteBridge: ObservableObject {
    static let shared = QuickNoteBridge()
    @Published private(set) var requestID = 0
    private init() {}

    func requestNew() { requestID += 1 }
}
