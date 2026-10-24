import Foundation
import SwiftData

/// C52: what starts a reconcile sweep. Exactly these three, and nothing on a clock — no
/// heartbeat timer. The app wiring (`MemoCloudReconciler+Wiring`) maps each one to its
/// notification and hands it to ONE `ReconcileCoalescer`.
enum ReconcileTrigger: String, CaseIterable, Sendable {
    /// The app launched (`MemoCloudReconciler.start()`).
    case launch
    /// The app became active (`NSApplication.didBecomeActiveNotification`).
    case activation
    /// A CloudKit import finished (`NSPersistentCloudKitContainer.eventChangedNotification`,
    /// type `.import`, ended, succeeded).
    case cloudKitImport
    /// A follow-up the app itself asks for after a LOCAL change (a file arrived, an orphaned
    /// transcription landed, the test library loaded). Event-driven like the other three,
    /// never periodic.
    case localChange

    /// C52's three outside triggers: the ones `MemoCloudReconciler.start()` registers.
    static let external: [ReconcileTrigger] = [.launch, .activation, .cloudKitImport]
}

/// C52: every trigger asks for a sweep; triggers that arrive inside `delay` of each other
/// collapse into ONE sweep (CloudKit import events land in bursts, and launch and the first
/// activation fire together). Each request cancels the pending one and re-arms it, so the
/// sweep runs once, `delay` after the last trigger of the burst. Pure (no AppKit, no
/// containers) so the test bundle drives it host-less.
@MainActor
final class ReconcileCoalescer {
    let delay: Duration
    private let run: @MainActor () -> Void
    private(set) var pending: Task<Void, Never>?
    /// Sweeps actually run, and the triggers that asked since the last one (tests read these).
    private(set) var runs = 0
    private(set) var requestedSinceRun: [ReconcileTrigger] = []

    init(delay: Duration = .seconds(1), run: @escaping @MainActor () -> Void) {
        self.delay = delay
        self.run = run
    }

    func request(_ trigger: ReconcileTrigger) {
        requestedSinceRun.append(trigger)
        pending?.cancel()
        let delay = self.delay
        pending = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            self.pending = nil
            self.runs += 1
            self.requestedSinceRun = []
            self.run()
        }
    }
}

/// The app's reconcile entry points (`MemoCloudReconciler+Wiring`): the triggers, the coalescer,
/// and the pass that calls reconcile v2 (`ReconcileV2.pass`).
@MainActor
enum MemoCloudReconciler {
    /// Set once by `start()` (the App wiring) so the launch/active/import observers register
    /// only once.
    static var didStart = false

    /// C52: the ONE coalescer every trigger goes through (see `reconcileSoon` in the app
    /// wiring, which creates it) — stored here because extensions can't hold stored statics.
    static var coalescer: ReconcileCoalescer?
}

extension MemoCloudReconciler {
    /// C52: the context a sweep reads the cloud store through — ALWAYS a new one. A CloudKit
    /// import writes to the persistent store but does not refresh objects an older context
    /// already registered, so a long-lived context (`mainContext`) returns stale memos and the
    /// sweep never sees a phone's later delete / tag / edit (2026-07-15 device test).
    static func freshCloudContext(_ container: ModelContainer) -> ModelContext {
        ModelContext(container)
    }

    /// R40 / C168: the text a failed cloud-store fetch shows (the sync state's detail line).
    nonisolated static func fetchFailureText(_ failure: String) -> String {
        "Couldn't read this Mac's iCloud store: \(failure)"
    }
}
