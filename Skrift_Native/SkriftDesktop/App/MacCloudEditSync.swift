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
    ///
    /// A row with no `modelContext` is a `MemoNoteProjection` — an unrated memo rendered
    /// through the note view, with no pipeline row behind it. Its edits DO belong on the
    /// memo, but not through this carrier: this one writes a `MemoEnhancement`, i.e. "the
    /// Mac polished this", which would be a lie about a note the Mac has never processed.
    /// `MemoNoteProjection.writeBack` puts them on the memo's own fields instead.
    func note(_ pf: PipelineFile) {
        guard pf.modelContext != nil else { return }
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
            let ctx = container.mainContext
            let memo = MacCloudWriteBack.resolve(for: pf, in: ctx)
            let before = memo.flatMap { EditConflicts.polishedBody(for: $0.id, in: ctx) }
            try MacCloudWriteBack.upsert(for: pf, into: ctx, deviceID: DeviceID.current(), bodyOverride: raw)
            // C98 (Q38): he edited the polished body here, so it is a words edit for conflict
            // detection. Only when the body moved: a title/summary edit flushes here too.
            if let memo, EditConflicts.polishedBody(for: memo.id, in: ctx) != before,
               EditConflicts.recordPolishedEdit(memo, in: ctx) {
                try ctx.save()
            }
        } catch {
            log.error("edit write-back failed for \(pf.id, privacy: .public): \(String(describing: error), privacy: .public)")
        }
    }
}
