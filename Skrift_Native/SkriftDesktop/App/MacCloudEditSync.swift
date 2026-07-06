import Foundation
import SwiftData
import os

/// Debounced Mac→phone LIVE-EDIT write-back (`LIVE_SYNC_HANDOFF.md` Part B). When the user edits
/// a note on the Mac review screen (body / title / summary), the bindings call `note(_:)`; after
/// a short idle we push the edited polish to CloudKit via `MacCloudWriteBack`, so the phone
/// reflects the edit within seconds. Same carrier + gate as the post-process write-back
/// (`ProcessingCoordinator.writeBackEnhancement`), just fired on MANUAL edits too.
///
/// App-only (touches the app's `MemoCloudStore` container), like the reconcile wiring. Gated
/// exactly like the reconcile loop — `cloudKitMacSyncEnabled` + an available container — and a
/// no-op otherwise; `upsert` itself skips a non-synced / empty file, so `note(_:)` is safe to
/// call for any note. The body is sent UN-LINKED to each person's spoken word
/// (`Sanitiser.unlinkToSpoken`) so the phone editor stays bracket-free and re-links cleanly.
@MainActor
final class MacCloudEditSync {
    static let shared = MacCloudEditSync()

    /// Idle window before a burst of keystrokes flushes to CloudKit (avoids per-keystroke churn).
    var debounce: Duration = .seconds(1.5)

    private var pending: [String: Task<Void, Never>] = [:]   // keyed by pf.id, latest reschedule wins
    private let log = Logger(subsystem: "com.skrift.desktop", category: "cloudkit")

    private init() {}

    /// Register an edit to `pf` and (re)schedule its write-back after the debounce window.
    func note(_ pf: PipelineFile) {
        guard SettingsStore.shared.load().cloudKitMacSyncEnabled, MemoCloudStore.container != nil else { return }
        let id = pf.id
        pending[id]?.cancel()
        pending[id] = Task { [weak self, weak pf] in
            guard let self else { return }
            try? await Task.sleep(for: self.debounce)
            guard !Task.isCancelled, let pf else { return }
            self.pending[id] = nil
            self.flush(pf)
        }
    }

    /// Push the edited polish now. Reads `pf.bestBodyText` at fire time, so a burst of edits
    /// coalesces to the latest text.
    func flush(_ pf: PipelineFile) {
        guard let container = MemoCloudStore.container else { return }
        do {
            let raw = Sanitiser.unlinkToSpoken(pf.bestBodyText, people: NamesStore.shared.livePeople())
            try MacCloudWriteBack.upsert(for: pf, into: container.mainContext,
                                         deviceID: DeviceID.current(), bodyOverride: raw)
        } catch {
            log.error("edit write-back failed for \(pf.id, privacy: .public): \(String(describing: error), privacy: .public)")
        }
    }
}
