import Foundation

/// The UPDATE half of live bidirectional sync (`LIVE_SYNC_HANDOFF.md` Part B, phone→Mac).
/// `MemoCloudIngest` handles a memo the Mac has NEVER seen; this handles a memo the Mac
/// ALREADY ingested that the phone then EDITED. The one-shot ingest deduped on re-see, so
/// without this a later phone edit never reached the Mac's queue/export.
///
/// **Policy (user call):** re-link + recompile only — NO LLM re-enhance. A phone edit adopts
/// the new text, re-runs the deterministic name-linker + `Compiler`, and stops. The LLM only
/// re-runs on an explicit Redo.
///
/// **Two edit shapes** (mirroring how the phone edits, `MemoDetailView`):
/// - a memo WITH a Mac polish → the phone edits `MemoEnhancement.copyedit` (path 2);
/// - a raw memo → the phone edits `Memo.transcript` (path 3).
///
/// **Echo guard.** The Mac's OWN write-back (`MacCloudWriteBack`) also lands a `MemoEnhancement`
/// back in the Mac's CloudKit mirror. Its `enhancedByDeviceID` is THIS Mac, so it is ignored
/// here — only a PHONE-authored enhancement is reflected, and `Memo.lastEditedAt` (untouched by
/// the write-back) gates the raw path. The `syncedSourceEditedAt` watermark makes each edit
/// reflect exactly once, so there is no ping-pong.
enum MemoCloudUpdate {

    /// Reflect a phone edit to an already-ingested memo into its local `PipelineFile`.
    /// Returns true when the row changed (so the caller can save + re-export). Pure over its
    /// inputs (no container / settings) so it unit-tests host-less.
    @discardableResult
    static func apply(memo: Memo, enhancement: MemoEnhancement?, to pf: PipelineFile,
                      people: [Person], author: String, thisDeviceID: String,
                      now: Date = Date()) -> Bool {
        // Trashed memos are handled by the reconciler's delete path, not here.
        guard memo.deletedAt == nil else { return false }

        let baseline = pf.syncedSourceEditedAt ?? .distantPast
        let memoEdited = memo.lastEditedAt

        // A PHONE-authored enhancement edit (path 2). The Mac's own write-back echo is skipped
        // by the device-id check, so the Mac never re-reflects what it just wrote.
        let phoneEnh: MemoEnhancement? = {
            guard let e = enhancement, e.hasContent, e.enhancedByDeviceID != thisDeviceID else { return nil }
            return e
        }()
        let enhEdited = phoneEnh?.enhancedAt ?? .distantPast

        let sourceEdited = max(memoEdited, enhEdited)
        guard sourceEdited > baseline else { return false }   // already up to date — nothing to reflect

        var changed = false

        if let e = phoneEnh, enhEdited >= memoEdited {
            // Path 2 — the phone edited the polished copy-edit. Adopt the RAW copy-edit + any
            // title/summary the phone carried, then re-link + recompile (no LLM).
            if pf.enhancedCopyedit != e.copyedit { pf.enhancedCopyedit = e.copyedit; changed = true }
            if !e.title.isEmpty, pf.enhancedTitle != e.title { pf.enhancedTitle = e.title; changed = true }
            if !e.summary.isEmpty, pf.enhancedSummary != e.summary { pf.enhancedSummary = e.summary; changed = true }
            if changed { resanitiseAndCompile(pf, people: people, author: author) }
        } else if let t = memo.transcript, pf.transcript != t {
            // Path 3 — the phone edited the RAW transcript. Adopt it. Re-link + recompile only
            // when this row isn't LLM-enhanced (an enhanced memo is edited via the copy-edit
            // path above; re-linking a stale copy-edit off a new transcript would misrepresent
            // the edit, and re-enhancing is the user-declined heavy path).
            pf.transcript = t
            changed = true
            if pf.enhancedCopyedit == nil { resanitiseAndCompile(pf, people: people, author: author) }
        }

        // Advance the watermark even when nothing textual changed (e.g. a title-only edit we
        // don't mirror) so a no-op edit can't re-trigger every sweep.
        pf.syncedSourceEditedAt = sourceEdited
        if changed { pf.lastActivityAt = now }
        return changed
    }

    /// Deterministic re-link + recompile (no LLM) over the pristine working text
    /// (copy-edit → transcript) — the same operation as `ProcessingCoordinator.resanitiseForNames`,
    /// inlined here so the updater stays pure/testable (no coordinator, no container).
    private static func resanitiseAndCompile(_ pf: PipelineFile, people: [Person], author: String) {
        let working = pf.enhancedCopyedit ?? pf.transcript ?? ""
        guard !working.isEmpty else { return }
        let isConversation = pf.sourceType == .audio && SpeakerTranscript.isAttributed(working)
        let result = isConversation
            ? Sanitiser.processConversation(text: working, people: people,
                                            neverLink: Set(pf.unlinkedNames), namePicks: pf.namePicks)
            : Sanitiser.process(text: working, people: people,
                                neverLink: Set(pf.unlinkedNames), namePicks: pf.namePicks)
        pf.sanitised = result.sanitised
        pf.ambiguousNames = result.ambiguous.isEmpty ? nil : result.ambiguous
        pf.sanitiseStatus = .done
        pf.compiledText = Compiler.compile(file: pf, author: author, knownPeople: people)
    }
}
