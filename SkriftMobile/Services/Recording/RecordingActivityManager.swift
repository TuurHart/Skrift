import ActivityKit
import Foundation
import SkriftShared

/// Owns the recording Live Activity: starts it when recording begins, pushes the
/// live caption + pause state, and ends it on stop/cancel. Ported from
/// Shhhcribble's `ActivityManager` (orphan reaping + ~250 ms caption throttle so
/// frequent partials don't burn ActivityKit's update budget); adds pause/resume.
///
/// All ActivityKit calls are no-ops + graceful when Live Activities are disabled
/// (Settings) or unavailable (Simulator), so the recorder works regardless. Real
/// on-device display is device-owed.
@MainActor
final class RecordingActivityManager {
    static let shared = RecordingActivityManager()

    private var activity: Activity<RecordingActivityAttributes>?
    private var startedAt = Date()
    private var status: RecordingActivityAttributes.ContentState.Status = .recording
    private var caption = ""
    private var pausedAt: Date?

    // Throttle caption pushes — partials can fire multiple times a second.
    private var lastPushAt: Date?
    private var pendingTask: Task<Void, Never>?
    private let throttle: TimeInterval = 0.25

    private init() {}

    var isRunning: Bool { activity != nil }

    /// End any pre-existing activities — clears orphans left when the app was
    /// killed mid-recording (iOS keeps the banner alive after the process dies).
    func reapOrphans() {
        for orphan in Activity<RecordingActivityAttributes>.activities {
            Task { await orphan.end(nil, dismissalPolicy: .immediate) }
        }
    }

    @discardableResult
    func start() -> Bool {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return false }
        if activity != nil { return true }
        reapOrphans()
        startedAt = Date()
        status = .recording
        caption = ""
        pausedAt = nil
        lastPushAt = nil
        do {
            activity = try Activity.request(
                attributes: RecordingActivityAttributes(startedAt: startedAt),
                content: .init(state: makeState(), staleDate: nil),
                pushType: nil
            )
            return true
        } catch {
            print("[Skrift] Live Activity start failed: \(error)")
            return false
        }
    }

    func update(caption: String) {
        guard activity != nil else { return }
        self.caption = caption
        let now = Date()
        let since = lastPushAt.map { now.timeIntervalSince($0) } ?? .infinity
        if since >= throttle {
            push()
        } else if pendingTask == nil {
            // Trailing push so the last words still land after the throttle window.
            let delay = throttle - since
            pendingTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(delay))
                await MainActor.run { self?.push() }
            }
        }
    }

    /// Freeze the timer at the current elapsed and show the paused style.
    func pause() {
        guard activity != nil else { return }
        status = .paused
        pausedAt = Date()
        push()
    }

    /// Re-anchor `startedAt = now − elapsed` so the timer resumes from the right
    /// value (paused wall-time excluded), matching `LiveRecordingService.elapsed`.
    func resume(elapsed: TimeInterval) {
        guard activity != nil else { return }
        startedAt = Date().addingTimeInterval(-elapsed)
        status = .recording
        pausedAt = nil
        push()
    }

    func end() {
        pendingTask?.cancel(); pendingTask = nil
        lastPushAt = nil
        guard let activity else { return }
        self.activity = nil
        status = .stopping
        let final = makeState()
        Task { await activity.end(.init(state: final, staleDate: nil), dismissalPolicy: .immediate) }
    }

    private func makeState() -> RecordingActivityAttributes.ContentState {
        .init(status: status, caption: caption, startedAt: startedAt, pausedAt: pausedAt)
    }

    private func push() {
        pendingTask?.cancel(); pendingTask = nil
        guard let activity else { return }
        lastPushAt = Date()
        let state = makeState()
        Task { await activity.update(.init(state: state, staleDate: nil)) }
    }
}
