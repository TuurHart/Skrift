import Combine
import Foundation

/// Bridges a programmatic "open this memo" request to the memos-list navigation.
/// Used when a memo is created OUTSIDE a user tap and we want to land the user on
/// it — specifically a video shared from Photos, which imports on app foreground
/// (share extension → App Group inbox → `CaptureInboxDrainer` → `MemoSaver.importVideo`)
/// and then relocates in the list to the video's filming date, so it'd otherwise
/// "vanish" from the top. We instead push it onto the nav stack so the user sees it.
///
/// Mirrors `RecordingIntentBridge`: a monotonic counter + the target id, observed
/// by `MemosListView` via `.onChange` AND consumed on `.onAppear` (so a request
/// fired during a COLD launch — exactly the share case — isn't missed). Monotonic
/// (not a clearable command) sidesteps "who clears it" races.
@MainActor
final class MemoOpenBridge: ObservableObject {
    static let shared = MemoOpenBridge()
    @Published private(set) var requestID = 0
    private var pendingID: UUID?
    private var consumedID = 0
    private init() {}

    /// Request that the list open `id`. The most recent request wins if several
    /// fire before the list consumes (e.g. multiple videos shared at once).
    func open(_ id: UUID) {
        pendingID = id
        requestID += 1
    }

    /// Returns the memo to open at most once per `open(_:)`. `MemosListView` calls
    /// this on appear + on `requestID` change, then pushes it onto its nav path.
    func consume() -> UUID? {
        guard requestID > consumedID else { return nil }
        consumedID = requestID
        return pendingID
    }
}
