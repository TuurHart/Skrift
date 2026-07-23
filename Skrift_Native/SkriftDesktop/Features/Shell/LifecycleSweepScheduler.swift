import AppKit
import Foundation
import SwiftData
import os

/// The fading → Recently-Deleted auto-move (60d), moved here verbatim from the
/// retired `FadingShelfColumn.swift` (step ④). Fully automatic (Tuur,
/// 2026-07-18: an arming gate read as friction; the 14-day trash + shelf
/// counts are the safety), idempotent. v3 (2026-07-23): every sweep run is a
/// human open by construction (see the scheduler below), so it also stamps
/// the purge clock — both for the notes it moves and for any trashed note
/// that synced in while this Mac wasn't being looked at.
@MainActor
enum MacFadingSweep {
    static func run(memos: [Memo], context: ModelContext, now: Date = Date()) {
        // The open-stamp first: phone-swept / phone-deleted rows whose purge
        // clock hasn't started get it started at THIS open.
        var wrote = MemoLifecycle.stampTrashSightings(memos, now: now) > 0

        let live = memos.filter { $0.deletedAt == nil }
        let backlinked = MemoLifecycle.backlinkedIDs(in: live)
        for memo in live where MemoLifecycle.sweepDue(memo, backlinked: backlinked, now: now) {
            memo.deletedAt = now
            memo.trashSeenAt = now   // swept with the user present — clock starts now
            wrote = true
        }
        if wrote { try? context.save() }
    }
}

/// Owns the 60-day fading → Recently-Deleted sweep as its own heartbeat —
/// which, since v3 "no note dies unseen" (Tuur, 2026-07-23), beats only when
/// a human is actually here: **launch + every app activation**, nothing else.
///
/// The previous triggers (day-change notification + a 24h timer) let a Mac
/// left running sweep notes into the trash — and start their purge clocks —
/// with nobody at the machine, which is exactly the "note dies while I'm
/// away" failure the doctrine forbids: the final doors only move while
/// you're looking. The staleness worry that motivated the timers (Q4,
/// mocks/lifecycle-ia-explorations.html #m3: "shown dates must be true") is
/// still honored: an overdue row in an idle window shows "moves to Recently
/// Deleted today", which is true — it moves at your next activation, and any
/// real usage pattern fires activations constantly. `JournalView.refresh`
/// still never sweeps — this stays the one place that does.
@MainActor
enum LifecycleSweepScheduler {
    private static let log = Logger(subsystem: "com.skrift.desktop", category: "lifecycle")
    private static var started = false
    private static var activationObserver: NSObjectProtocol?

    static func start() {
        guard !started else { return }
        started = true

        runNow()   // launch is an open

        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { _ in Task { @MainActor in runNow() } }

        #if DEBUG
        // `-poke-sweep <sec>`: run the sweep after <sec> seconds, for headless
        // harness runs that never activate. (Replaces `-poke-daychange` /
        // `-sweepHeartbeatSeconds` — the unattended triggers they exercised are
        // gone; the activation observer is verified live with a real cmd-tab,
        // which posting a synthetic didBecomeActive would only fake anyway.)
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-poke-sweep"), i + 1 < args.count,
           let delay = Double(args[i + 1]) {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(delay))
                log.log("poke: running the sweep on request")
                runNow()
            }
        }
        #endif
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
