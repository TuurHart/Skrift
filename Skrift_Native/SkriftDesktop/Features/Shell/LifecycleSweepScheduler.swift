import Foundation
import SwiftData
import os

/// The fading → Recently-Deleted auto-move (60d), moved here verbatim from the
/// retired `FadingShelfColumn.swift` (step ④) — only its trigger changed, from
/// riding `JournalView.refresh` to `LifecycleSweepScheduler` below. Fully
/// automatic (Tuur, 2026-07-18: an arming gate read as friction; the 14-day
/// trash + shelf counts are the safety), idempotent.
@MainActor
enum MacFadingSweep {
    static func run(memos: [Memo], context: ModelContext, now: Date = Date()) {
        let live = memos.filter { $0.deletedAt == nil }
        let backlinked = MemoLifecycle.backlinkedIDs(in: live)
        var swept = 0
        for memo in live where MemoLifecycle.sweepDue(memo, backlinked: backlinked, now: now) {
            memo.deletedAt = now
            swept += 1
        }
        if swept > 0 { try? context.save() }
    }
}

/// Owns the 60-day fading → Recently-Deleted sweep as its own heartbeat.
/// Previously `MacFadingSweep.run` piggybacked on Review's own refresh
/// (`JournalView.refresh`) — so a shown countdown could go stale until you
/// happened to open Review (Q4, mocks/lifecycle-ia-explorations.html #m3:
/// "shown dates must be true"). Runs on launch, on the system day-change
/// notification, and every 24h as a belt-and-braces catch-all (a
/// suspended/sleeping Mac can miss the notification). `JournalView.refresh`
/// no longer sweeps — this is the one place that does.
@MainActor
enum LifecycleSweepScheduler {
    private static let log = Logger(subsystem: "com.skrift.desktop", category: "lifecycle")
    private static var started = false
    private static var dayChangeObserver: NSObjectProtocol?
    private static var heartbeat: Task<Void, Never>?

    static func start() {
        guard !started else { return }
        started = true

        runNow()

        // NSCalendarDayChanged (Foundation) — the day-boundary trigger the
        // brief describes as "NSCalendar.dayChangedNotification"; that's not
        // the actual Foundation symbol name, so this uses the real one.
        dayChangeObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name.NSCalendarDayChanged, object: nil, queue: .main
        ) { _ in Task { @MainActor in runNow() } }

        heartbeat = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(24 * 60 * 60))
                guard !Task.isCancelled else { return }
                runNow()
            }
        }
    }

    /// Same stale-mainContext avoidance as `MemoCloudReconciler.reconcile()`
    /// (2026-07-15 device bug): a CloudKit import writes the persistent STORE
    /// but doesn't refresh an already-registered context's cached rows, so a
    /// fresh `ModelContext` per run is required to see the latest data — and
    /// the same `cloudKitMacSyncEnabled` gate, so a sweep never mutates the
    /// user's memos while they've explicitly left Mac sync off.
    private static func runNow() {
        guard SettingsStore.shared.load().cloudKitMacSyncEnabled,
              let cloud = MemoCloudStore.container else { return }
        let ctx = ModelContext(cloud)
        let all = (try? ctx.fetch(FetchDescriptor<Memo>())) ?? []
        MacFadingSweep.run(memos: all, context: ctx)
        log.log("lifecycle sweep ran over \(all.count, privacy: .public) memos")
    }
}
