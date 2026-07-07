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
/// **Echo guard + no ping-pong.** The decision is CONTENT-based: a change is applied only when
/// the synced text actually differs from the row, so a no-op sweep does nothing and there is no
/// loop. The Mac's OWN write-back (`MacCloudWriteBack`) lands a `MemoEnhancement` whose
/// `enhancedByDeviceID` is THIS Mac, so it is ignored — only a PHONE-authored enhancement is
/// reflected. (`syncedSourceEditedAt` is kept as an informational watermark, not the gate — an
/// earlier timestamp-gated version dropped a copy-edit edit because the phone stamps
/// `memo.editedAt` a hair after `enhancement.enhancedAt`.)
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

        // A PHONE-authored enhancement edit. The Mac's own write-back echo is skipped by the
        // device-id check, so the Mac never re-reflects what it just wrote.
        let phoneEnh: MemoEnhancement? = {
            guard let e = enhancement, e.hasContent, e.enhancedByDeviceID != thisDeviceID else { return nil }
            return e
        }()

        // CONTENT-based, not timestamp-based: the phone stamps `enhancement.enhancedAt` and THEN
        // `memo.editedAt` in the same edit (`TranscriptEditor`), so `memo.lastEditedAt` can be a
        // hair NEWER than the enhancement — a timestamp race that must NOT hide a copy-edit change.
        // Comparing the actual text is race-proof AND self-healing (recovers even if a prior run
        // advanced the watermark without applying).
        var changed = false

        // Path 2 — the phone edited the polished copy-edit / title / summary.
        if let e = phoneEnh {
            if pf.enhancedCopyedit != e.copyedit { pf.enhancedCopyedit = e.copyedit; changed = true }
            if !e.title.isEmpty, pf.enhancedTitle != e.title { pf.enhancedTitle = e.title; changed = true }
            if !e.summary.isEmpty, pf.enhancedSummary != e.summary { pf.enhancedSummary = e.summary; changed = true }
        }

        // Path 3 — the phone edited the RAW transcript.
        if let t = memo.transcript, pf.transcript != t {
            pf.transcript = t
            changed = true
        }

        guard changed else { return false }

        // Re-link + recompile once (no LLM) over the pristine working text (copy-edit → transcript),
        // so a path-2 copy-edit wins the body and a path-3 raw edit falls through for un-enhanced rows.
        resanitiseAndCompile(pf, people: people, author: author)
        pf.syncedSourceEditedAt = max(memo.lastEditedAt, phoneEnh?.enhancedAt ?? .distantPast)
        pf.lastActivityAt = now
        return true
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
