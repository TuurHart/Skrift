import UIKit

/// Runs an async block under a UIKit background-task assertion, so a brief piece of
/// work can finish in the ~30s of grace iOS grants after the user backgrounds the
/// app. Best-effort: if the assertion expires the work is suspended — callers that
/// need guaranteed completion pair this with a launch-time recovery sweep (e.g.
/// `MemoSaver.recoverStuckDiarizations`). Used by "Split speakers" so backgrounding
/// the app mid-identify doesn't silently abandon the diarization (2026-06-21 bug).
@MainActor
enum BackgroundTask {
    /// Holds the assertion id by reference so the expiration handler and the normal
    /// completion path can both end exactly the same assertion without racing.
    private final class Holder { var id: UIBackgroundTaskIdentifier = .invalid }

    static func run(name: String, _ work: () async -> Void) async {
        let app = UIApplication.shared
        let holder = Holder()
        holder.id = app.beginBackgroundTask(withName: name) {
            if holder.id != .invalid { app.endBackgroundTask(holder.id); holder.id = .invalid }
        }
        await work()
        if holder.id != .invalid { app.endBackgroundTask(holder.id); holder.id = .invalid }
    }
}
