import ActivityKit
import Foundation
import SkriftShared
import UIKit

/// Owns the recording Live Activity: starts it when recording begins, pushes the
/// live caption + pause state, and ends it on stop/cancel. Ported from
/// Shhhcribble's `ActivityManager` (orphan reaping + ~250 ms caption throttle so
/// frequent partials don't burn ActivityKit's update budget); adds pause/resume.
///
/// ZOMBIE-BANNER defences (2026-06-10: the lock screen kept showing
/// "recording · 45min" long after the app died mid-recording): every content
/// push carries a `staleDate`, refreshed by a keep-alive timer while we're
/// really recording — if the process crashes or is killed, no refresh lands and
/// the banner flips to the widget's "Recording interrupted" fallback instead of
/// a forever-counting timer. Orphans are additionally swept on every app
/// foreground (not just launch), and `end()` sweeps strays on every stop path.
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

    /// No update for this long → ActivityKit marks the banner stale and the
    /// widget renders the "Recording interrupted" fallback (`context.isStale`).
    /// Generous enough that a briefly-suspended paused recording doesn't flap.
    private static let staleAfter: TimeInterval = 180
    /// Refresh the staleDate well inside the window while recording is live.
    /// (Recording holds the `audio` background mode, so this fires backgrounded.)
    private static let keepAliveInterval: TimeInterval = 60
    private var keepAliveTimer: Timer?

    private init() {
        // A crash/kill mid-recording orphans the banner (the dead process can't
        // end it) — sweep stale activities on EVERY return to the foreground,
        // not just at launch.
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { RecordingActivityManager.shared.reapOrphans() }
        }
        // Best-effort end on a graceful termination mid-recording (a hard kill
        // can't run this — that's what the staleDate fallback is for).
        NotificationCenter.default.addObserver(
            forName: UIApplication.willTerminateNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { RecordingActivityManager.shared.end() }
        }
    }

    var isRunning: Bool { activity != nil }

    /// End any activities that don't belong to the live recording — orphans left
    /// when the app was killed mid-recording (iOS keeps the banner alive after
    /// the process dies). Safe to call at any time: the current activity, if one
    /// is running, is skipped. Runs at launch and on every foreground.
    func reapOrphans() {
        let liveID = activity?.id
        for orphan in Activity<RecordingActivityAttributes>.activities where orphan.id != liveID {
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
                content: .init(state: makeState(), staleDate: Date().addingTimeInterval(Self.staleAfter)),
                pushType: nil
            )
            startKeepAlive()
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
        keepAliveTimer?.invalidate(); keepAliveTimer = nil
        lastPushAt = nil
        let ending = activity
        activity = nil
        if let ending {
            status = .stopping
            let final = makeState()
            Task { await ending.end(.init(state: final, staleDate: nil), dismissalPolicy: .immediate) }
        }
        // Belt-and-braces: sweep anything else still showing (an activity this
        // manager lost track of) so no stop path can leave a zombie banner.
        reapOrphans()
    }

    private func makeState() -> RecordingActivityAttributes.ContentState {
        .init(status: status, caption: caption, startedAt: startedAt, pausedAt: pausedAt)
    }

    /// Periodic content refresh purely to extend the staleDate — without it a
    /// recording with no caption updates (live captioning off, or long silence)
    /// would falsely go stale mid-recording.
    private func startKeepAlive() {
        keepAliveTimer?.invalidate()
        keepAliveTimer = Timer.scheduledTimer(withTimeInterval: Self.keepAliveInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.push() }
        }
    }

    private func push() {
        pendingTask?.cancel(); pendingTask = nil
        guard let activity else { return }
        lastPushAt = Date()
        let state = makeState()
        Task { await activity.update(.init(state: state, staleDate: Date().addingTimeInterval(Self.staleAfter))) }
    }
}
