import Foundation
import os

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
    ///
    /// `isFreshRow` — this `pf` was created by THIS sweep, moments ago. It turns the
    /// self-echo guard below OFF, because a brand-new row has no local copy of anything to
    /// protect: when a Mac-written `MemoEnhancement` is the ONLY surviving copy of a polish
    /// (the row it was written for is gone, or the memo was never ingested here at all),
    /// skipping it as "my own echo" means the note surfaces RAW forever, with its paragraphs
    /// sitting in the cloud store (Tuur, 2026-08-19: the store held the copy-edit, the open
    /// note showed the blob). On an existing row the guard stays exactly as it was.
    @discardableResult
    static func apply(memo: Memo, enhancement: MemoEnhancement?, to pf: PipelineFile,
                      people: [Person], author: String, thisDeviceID: String,
                      now: Date = Date(), isFreshRow: Bool = false) -> Bool {
        // Trash-state mirror (phone→Mac), watermarked. Reflect a phone trash/restore onto the row
        // ONLY when `memo.deletedAt` differs from what we last reflected — so a phone trash arrives
        // here (heals a note the Mac still shows after the phone binned it) and a phone restore
        // clears it, WITHOUT a Mac-local trash (whose memo is still active) being un-trashed on the
        // first post-upgrade sweep. The Mac's own trash writes `memo.deletedAt` (MacCloudDeleteSync),
        // so that path lands here too — as a no-op reflect (the values already agree).
        var trashChanged = false
        if memo.deletedAt != pf.syncedSourceDeletedAt {
            pf.deletedAt = memo.deletedAt
            pf.syncedSourceDeletedAt = memo.deletedAt
            trashChanged = true
        }
        // A trashed memo needs no text/photo reflect — it's in the bin. A restore falls through to
        // the normal reflect below so its body/polish is fresh when it reappears.
        guard memo.deletedAt == nil else {
            if trashChanged { pf.lastActivityAt = now }
            return trashChanged
        }

        // A PHONE-authored enhancement edit. The Mac's own write-back echo is skipped by the
        // device-id check, so the Mac never re-reflects what it just wrote.
        let phoneEnh: MemoEnhancement? = {
            guard let e = enhancement, e.hasContent else { return nil }
            guard isFreshRow || e.enhancedByDeviceID != thisDeviceID else { return nil }
            return e
        }()

        // CONTENT-based, not timestamp-based: the phone stamps `enhancement.enhancedAt` and THEN
        // `memo.editedAt` in the same edit (`TranscriptEditor`), so `memo.lastEditedAt` can be a
        // hair NEWER than the enhancement — a timestamp race that must NOT hide a copy-edit change.
        // Comparing the actual text is race-proof AND self-healing (recovers even if a prior run
        // advanced the watermark without applying).
        var contentChanged = false
        var why: [String] = []   // DIAG 2026-07-27: which field fired (the `reflected=N` churn hunt)

        // Path 2 — the phone edited the polished copy-edit / title / summary.
        if let e = phoneEnh {
            if pf.enhancedCopyedit != e.copyedit { pf.enhancedCopyedit = e.copyedit; contentChanged = true; why.append("enh.copyedit") }
            if !e.title.isEmpty, pf.enhancedTitle != e.title { pf.enhancedTitle = e.title; contentChanged = true; why.append("enh.title") }
            if !e.summary.isEmpty, pf.enhancedSummary != e.summary { pf.enhancedSummary = e.summary; contentChanged = true; why.append("enh.summary") }
        }

        // Path 2b — the note's TITLE was chosen on another device. `Memo.title` is the
        // title every device's list actually renders, while `enhancement.title` above is
        // only the Mac's SUGGESTION; the two are different fields on purpose. Without this
        // the sync was one-way — the Mac pushed a chosen title out (`MacCloudMetaSync
        // .setTitle`) but never adopted one chosen on the phone/iPad.
        // ADOPT ONLY, never clear. `memo.title == nil` is the DEFAULT state of every note
        // nobody has chosen a title for — not an instruction to erase one. Clearing on nil
        // would wipe the Mac's own generated suggestion (`pf.enhancedTitle`, which lives
        // only on the row) on the very next sweep, since a generated suggestion never
        // writes `Memo.title`. Value-compared, so an agreeing title is not a change and
        // cannot churn the sweep.
        if let chosen = memo.title?.trimmingCharacters(in: .whitespacesAndNewlines),
           !chosen.isEmpty, pf.enhancedTitle != chosen {
            pf.enhancedTitle = chosen
            contentChanged = true; why.append("memo.title")
        }

        // Path 3 — the phone edited the RAW transcript.
        if let t = memo.transcript, pf.transcript != t {
            pf.transcript = t
            contentChanged = true; why.append("transcript")
        }

        // The metadata BLOB changed (book fields edited, photo OCR landed, …) — refresh the
        // stored copy and recompile (the frontmatter reads it). Deterministic byte-compare:
        // `metadataJSON` sorts keys, so an unchanged blob never churns.
        let blob = MemoCloudIngest.metadataJSON(for: memo)
        if pf.audioMetadataJSON != blob {
            pf.audioMetadataJSON = blob
            why.append("metaBlob")
            contentChanged = true
        }

        // Every plain `PipelineFile` ⇄ `Memo` mirror, from the ONE declaration
        // (`MirroredNoteFields`) — tags, importance, destination, lock, reminder. Content-based
        // like the rest: a Mac edit writes the Memo synchronously (MacCloudMetaSync), so this
        // compare has already converged and there is no clobber loop. Each field says whether
        // it reaches the frontmatter, which is what decides a recompile.
        var metaChanged = false
        for field in MirroredNoteFields.all where field.pull(memo, pf) {
            if field.recompiles { contentChanged = true } else { metaChanged = true }
            why.append(field.name)
        }
        // The note's name decisions (C81, D20) — the links reach the body, so recompile.
        if NameResolutionsMirror.pull(memo, into: pf) { contentChanged = true; why.append("nameResolutions") }

        // The flat OCR search text — derived, not a mirrored field.
        let ocr = MemoCloudIngest.ocrText(for: memo)
        if pf.imageOCRText != ocr { pf.imageOCRText = ocr; metaChanged = true; why.append("ocr") }

        guard contentChanged || metaChanged || trashChanged else { return false }
        #if DEBUG
        Logger(subsystem: "com.skrift.desktop", category: "synctrace")
            .notice("reflect \(pf.id, privacy: .public) ← \(why.joined(separator: ","), privacy: .public)")
        #endif

        if contentChanged {
            // Re-link + recompile once (no LLM) over the pristine working text (copy-edit →
            // transcript), so a path-2 copy-edit wins the body and a path-3 raw edit falls
            // through for un-enhanced rows.
            resanitiseAndCompile(pf, people: people, author: author)
            pf.syncedSourceEditedAt = max(memo.lastEditedAt, phoneEnh?.enhancedAt ?? .distantPast)
        }
        pf.lastActivityAt = now
        return true
    }

    /// Deterministic re-link + recompile (no LLM) over the pristine working text
    /// (copy-edit → transcript) — the same operation as `ProcessingCoordinator.resanitiseForNames`,
    /// sharing `PipelineFile.relinkNames` so the updater stays pure/testable (no coordinator, no container).
    private static func resanitiseAndCompile(_ pf: PipelineFile, people: [Person], author: String) {
        // The shared body-source rule (Q155): a copy-edit with no words (a title-only polish
        // writes "") falls through to the transcript, as on the phone.
        let working = CompilerInput.workingBody(raw: pf.transcript, copyedit: pf.enhancedCopyedit).text
        guard !working.isEmpty else { return }
        let isConversation = pf.sourceType == .audio && SpeakerTranscript.isAttributed(working)
        pf.relinkNames(working: working, isConversation: isConversation, people: people)
        pf.sanitiseStatus = .done
        pf.compiledText = Compiler.compile(file: pf, author: author, knownPeople: people)
    }
}
