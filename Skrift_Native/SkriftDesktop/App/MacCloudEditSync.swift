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
    let debounce: Duration = .seconds(1.5)

    /// Q363 (M4): one pending push per note, body and title together.
    private lazy var typing = MacTypingDebounce(delay: debounce)
    /// Notes whose BODY polish is waiting to go out (pipeline rows only, see `note`).
    private var bodyPending: Set<String> = []
    /// Notes whose typed TITLE is waiting to go out. Held strongly: an unrated note's
    /// projection row may be dropped by its pane before the window ends, and the title
    /// must still reach the memo.
    private var titlePending: [String: PipelineFile] = [:]
    /// Per-note flush counter: a flush whose off-main round trip finishes after a NEWER
    /// flush started is dropped, so an older body can never land last (M13).
    private var flushGeneration: [String: Int] = [:]

    private init() {}

    /// Register an edit to `pf` and (re)schedule its write-back after the debounce window.
    /// `title: true` = the edit was the typed title: it goes onto `Memo.title` on the same
    /// debounce as the body — one CloudKit save + one sidebar notification per pause, not
    /// per key (Q363, M4).
    ///
    /// A row with no `modelContext` is a `MemoNoteProjection` — an unrated memo rendered
    /// through the note view, with no pipeline row behind it. Its edits DO belong on the
    /// memo, but not through this carrier: this one writes a `MemoEnhancement`, i.e. "the
    /// Mac polished this", which would be a lie about a note the Mac has never processed.
    /// `MemoNoteProjection.writeBack` puts them on the memo's own fields instead. Its typed
    /// title still goes out through `MacCloudMetaSync.setTitle`, as it always did.
    func note(_ pf: PipelineFile, title: Bool = false) {
        // Q489: a body edit also keeps the row's copy-edit in step (`flush`), with sync on or off,
        // so the title-only push is the one part that needs the synced store.
        let synced = MemoCloudStore.syncContainer != nil
        let body = pf.modelContext != nil
        guard body || (title && synced) else { return }
        guard body || title else { return }
        let id = pf.id
        if body { bodyPending.insert(id) }
        if title { titlePending[id] = pf }
        typing.schedule(id) { [weak self, weak pf] in
            guard let self else { return }
            let titled = self.titlePending.removeValue(forKey: id)
            let bodied = self.bodyPending.remove(id) != nil
            if let titled, synced { MacCloudMetaSync.setTitle(titled.enhancedTitle, for: titled) }
            if bodied, let pf { self.flush(pf) }
        }
    }

    /// Push the edited polish now. Reads `pf.bestBodyText` at fire time, so a burst of edits
    /// coalesces to the latest text. The Sanitiser round trip runs off the main actor (M13);
    /// only the store reads and writes stay on it.
    private func flush(_ pf: PipelineFile) {
        let id = pf.id
        let generation = (flushGeneration[id] ?? 0) + 1
        flushGeneration[id] = generation
        let people = NamesStore.shared.livePeople()
        let body = pf.bestBodyText
        let ctx = MemoCloudStore.syncContainer != nil ? MemoCloudStore.container?.mainContext : nil
        let memo = ctx.flatMap { ReconcileV2.Writers.resolve(pf, in: $0) }
        // A title/summary-only edit never touches `pf.sanitised`; `MacEditRoundTrip` round-trips
        // the stored polish through the same pipeline so only a REAL body change registers (Q42).
        let before = memo.flatMap { m in ctx.flatMap { EditConflicts.polishedBody(for: m.id, in: $0) } }
            ?? pf.enhancedCopyedit
        let neverLink = Set(pf.unlinkedNames)
        let namePicks = pf.namePicks
        // Q508: a diarized note's body is speaker turns, compared through the turn linker.
        let conversation = SpeakerTranscript.isConversation(
            CompilerInput.workingBody(raw: pf.transcript, copyedit: pf.enhancedCopyedit).text, source: pf.noteSource)
        Task { @MainActor [weak self, weak pf] in
            let trip = await MacEditRoundTrip.offMain(body: body, before: before, people: people,
                                                      neverLink: neverLink, namePicks: namePicks,
                                                      conversation: conversation)
            guard let self, let pf, self.flushGeneration[id] == generation else { return }
            self.flushGeneration[id] = nil
            MacEditRoundTrip.adopt(trip, into: pf)
            try? pf.modelContext?.save()
            guard let ctx else { return }
            do {
                try ReconcileV2.Writers.upsertEnhancement(for: pf, into: ctx, deviceID: DeviceID.current(),
                                                          body: trip.raw)
                // C98 (Q38): he edited the polished body here, so it is a words edit for conflict
                // detection. Only when the body actually moved: a title/summary edit flushes here too.
                if trip.bodyMoved, let memo,
                   EditConflicts.recordPolishedEdit(memo, in: ctx) {
                    try ctx.save()
                }
            } catch {
                AppLog.cloudkit.error("edit write-back failed for \(pf.id, privacy: .public): \(String(describing: error), privacy: .public)")
            }
        }
    }
}
