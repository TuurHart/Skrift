import Foundation
import SwiftData
import os

/// The reconcile loop for the Mac→CloudKit client (`MAC_CLOUDKIT_PLAN.md`, 8d): pull memos
/// the phone synced over CloudKit into the local pipeline queue, so the Mac processes them
/// exactly as it would a Bonjour upload. The launch / foreground / CloudKit-import TRIGGERS +
/// the `reconcile()` entry point (which resolve the app's containers + settings) live in the
/// app-only `MemoCloudReconciler+Wiring.swift` extension; this file holds the pure, testable
/// `sweep` so it compiles into the host-less test bundle.
///
/// **Coexists with Bonjour.** Gated behind the opt-in `cloudKitMacSync` setting (OFF by
/// default), and `MemoCloudIngest` dedups by memo UUID / embedded filename, so a memo seen
/// via BOTH transports collapses to one `PipelineFile`. The Bonjour/HTTP server is untouched.
@MainActor
enum MemoCloudReconciler {
    /// Set once by `start()` (the App wiring) so the launch/active/import observers register
    /// only once.
    static var didStart = false

    /// The one pending coalesced sweep (see `reconcileSoon` in the app wiring) —
    /// stored here because extensions can't hold stored statics.
    @MainActor static var pendingReconcile: Task<Void, Never>?

    /// What a sweep did: how many NEW rows were ingested, and the ids of EXISTING rows a phone
    /// edit updated (Part B) — the latter drive a re-export so the vault reflects the edit too.
    struct SweepOutcome: Equatable {
        var created = 0
        var updatedIDs: [String] = []
        var ingestFailures = 0
        /// Rated, live memos this sweep left WITHOUT a `PipelineFile` — the invisible
        /// state (no queue row, and the quiet rows are the unrated ones), so this must
        /// stay 0. Non-zero is a real hole worth a log line, not a statistic: it is what
        /// a note that looks deleted but isn't counts as (Tuur, 2026-08-19).
        var stranded = 0
    }

    /// Sweep every `Memo` in `cloudContext` into `localContext` (the pipeline store): fetch each
    /// memo's `MemoAsset` blob rows and either INGEST it (never seen) or, if already ingested,
    /// reflect a newer phone EDIT via `MemoCloudUpdate` (Part B, phone→Mac live sync). Gated
    /// (significance) / unchanged memos are no-ops. Pure (takes both contexts + roster/author)
    /// so it's unit-testable host-less.
    /// `upload` exists for ONE reason: its `outputDir`. The default writes working folders
    /// into the app's real audio-output directory, which is right for the app and wrong for
    /// a test — every sweep test since 8d has been materialising folders into the user's
    /// live Dev data folder (1987 of them by 2026-08-20). Tests pass a temp dir.
    @discardableResult
    static func sweep(from cloudContext: ModelContext, into localContext: ModelContext,
                      processEverything: Bool,
                      people: [Person] = [], author: String = "", thisDeviceID: String = "",
                      now: Date = Date(),
                      upload: UploadService = UploadService()) -> SweepOutcome {
        // Duplicate-tolerant: the cloud DB can hold same-id rows (the 2026-07-12 clone
        // incident; divergent pairs are never auto-healed). Collapse each id onto its
        // keeper (shared `MemoDuplicates` rule — the same row the phone's deduper keeps),
        // else two rows would take turns rewriting ONE PipelineFile every sweep
        // (recompile + re-export churn, forever).
        let memos = MemoDuplicates.canonicalRows(
            (try? cloudContext.fetch(FetchDescriptor<Memo>())) ?? [])
        var outcome = SweepOutcome()
        // C98/D139: a note edited on two devices while apart is a conflict — its row keeps
        // the Mac's words (no reflect of the newest-wins `Memo` row over them) and waits.
        let held = EditConflictHold.refresh(memos: memos, in: cloudContext,
                                            thisDevice: thisDeviceID.isEmpty ? DeviceID.current() : thisDeviceID)
        // ONE local fetch + ONE enhancement fetch up front, instead of 2-3
        // fetches per memo — and NO MemoAsset fetch unless a memo actually
        // needs its blobs: asset rows fault-fill their multi-MB audio/photo
        // blobs on touch (row-level faulting, no external storage under
        // CloudKit), so the steady-state sweep must never realize them.
        let localFiles = (try? localContext.fetch(FetchDescriptor<PipelineFile>())) ?? []
        var fileByID: [String: PipelineFile] = [:]
        var fileByFilename: [String: PipelineFile] = [:]
        for pf in localFiles {
            if fileByID[pf.id] == nil { fileByID[pf.id] = pf }
            if !pf.filename.isEmpty, fileByFilename[pf.filename] == nil { fileByFilename[pf.filename] = pf }
        }
        // Which local rows are already OWNED by a memo (their id IS a memo uuid). A row in
        // here must never be claimed by a DIFFERENT memo via the filename arm — that is what
        // let two memos sharing an `audioFilename` overwrite one row forever.
        let memoOwnedRowIDs = Set(memos.map(\.id.uuidString))
        let enhancements = (try? cloudContext.fetch(FetchDescriptor<MemoEnhancement>())) ?? []
        let enhancementByMemo = Dictionary(enhancements.map { ($0.memoID, $0) },
                                           uniquingKeysWith: { a, _ in a })
        for memo in memos {
            let memoID = memo.id
            let id = memo.id.uuidString
            let filename = MemoCloudIngest.audioFilename(for: memo)
            let fetchAssets: () -> [MemoAsset] = {
                (try? cloudContext.fetch(
                    FetchDescriptor<MemoAsset>(predicate: #Predicate { $0.memoID == memoID }))) ?? []
            }

            // Same match rule as `alreadyIngested`/`existingFile` (id OR embedded
            // filename), minus the empty-filename cross-match those allowed.
            // The filename arm may claim a row only if that row is not ALREADY another
            // memo's. A legacy Bonjour row (random id, nobody's memo uuid) is still claimed,
            // which is what keeps that dedup working; a row owned by memo A is off-limits to
            // memo B, which is what stops the two overwriting each other every sweep when an
            // audiobook quote capture inherits the source memo's `audioFilename`.
            let filenameRow = filename.isEmpty ? nil : fileByFilename[filename]
            let filenameRowIsAnothersMemo = filenameRow.map {
                $0.id != id && memoOwnedRowIDs.contains($0.id)
            } ?? false
            let byFilename = filenameRowIsAnothersMemo ? nil : filenameRow
            if let pf = fileByID[id] ?? byFilename {
                // Already have a row — reflect a phone edit into it (no-op when up to date).
                let applied = held.contains(id) ? false
                    : MemoCloudUpdate.apply(memo: memo, enhancement: enhancementByMemo[memoID], to: pf,
                                            people: people, author: author,
                                            thisDeviceID: thisDeviceID, now: now)
                // Materialize photos the phone added AFTER first ingest — the update path above
                // reflects the [[img_NNN]] markers but never wrote the image files (they'd render
                // as literal text + miss the vault). Idempotent; heals an already-broken note on
                // the next sweep. When it heals a row `apply` didn't touch, nudge lastActivityAt so
                // the open review body re-renders and resolves the markers. Skip a trashed memo —
                // no point materializing photos for something in the bin.
                let healed = memo.deletedAt == nil
                    && MemoPhotoMaterializer.materializeMissing(memo: memo, pf: pf, fetchAssets: fetchAssets)
                // Same late-asset hole, karaoke-flavored: adopt a `wordTimings` asset that
                // synced AFTER first ingest (guards inside keep the steady-state sweep from
                // faulting blobs; never clobbers Mac-ASR timings).
                let timingsHealed = MemoCloudIngest.adoptLateWordTimings(memo: memo, pf: pf,
                                                                         fetchAssets: fetchAssets)
                // …and the diarization twin (a late `diar` asset otherwise leaves the Mac
                // unable to enroll a voice from a phone-diarized conversation).
                let diarHealed = MemoCloudIngest.adoptLateDiarization(memo: memo, pf: pf,
                                                                      fetchAssets: fetchAssets)
                let anyHeal = healed || timingsHealed || diarHealed
                if anyHeal && !applied { pf.lastActivityAt = now }
                if applied || anyHeal { outcome.updatedIDs.append(pf.id) }
            } else {
                // nil = gated/trashed (a legitimate no-op); a THROW is a real failure —
                // previously `try?`-swallowed, making a memo that fails every sweep an
                // invisible black hole. Count + name it for the reconcile summary.
                do {
                    if let created = try MemoCloudIngest.ingest(memo: memo, assets: fetchAssets(),
                                                                upload: upload,
                                                                into: localContext,
                                                                processEverything: processEverything,
                                                                // …so this memo gets its OWN row
                                                                // instead of being silently dropped.
                                                                allowFilenameMatch: !filenameRowIsAnothersMemo) {
                        outcome.created += 1
                        // Give the FRESH row everything the cloud already knows — above all a
                        // `MemoEnhancement` that exists while the row does not, which is the
                        // only copy of that polish anywhere. Without this the note surfaces
                        // raw and waits for the NEXT sweep, where the self-echo guard throws
                        // this Mac's own enhancement away for good (`isFreshRow` turns that
                        // guard off exactly here, and nowhere else).
                        if MemoCloudUpdate.apply(memo: memo, enhancement: enhancementByMemo[memoID],
                                                 to: created, people: people, author: author,
                                                 thisDeviceID: thisDeviceID, now: now,
                                                 isFreshRow: true) {
                            outcome.updatedIDs.append(created.id)
                        }
                        // Keep the lookup maps live so a same-sweep duplicate
                        // (Bonjour-era filename twin) can't double-ingest.
                        if fileByID[created.id] == nil { fileByID[created.id] = created }
                        if !created.filename.isEmpty, fileByFilename[created.filename] == nil {
                            fileByFilename[created.filename] = created
                        }
                    } else if memo.deletedAt == nil, NoteConsent.isRated(memo) {
                        // Rated, live, and STILL no row: the memo renders in no list section
                        // at all. Every known cause is fixed (a typed note ingests as a text
                        // row now); what remains is a genuine wait — a voice memo whose audio
                        // blob hasn't synced yet — so name it rather than let the next one be
                        // silent for a day.
                        outcome.stranded += 1
                        Logger(subsystem: "com.skrift.desktop", category: "cloudkit")
                            .error("STRANDED: rated memo \(memo.id, privacy: .public) has no row after ingest — invisible in every list section")
                    }
                } catch {
                    outcome.ingestFailures += 1
                    Logger(subsystem: "com.skrift.desktop", category: "cloudkit")
                        .error("ingest FAILED memo \(memo.id, privacy: .public): \(error)")
                }
            }
        }
        return outcome
    }

    /// The existing `PipelineFile` for a memo — by memo-UUID id, else by embedded filename
    /// (a Bonjour-era row). Mirrors `MemoCloudIngest.alreadyIngested`'s match.
    static func existingFile(id: String, filename: String, in context: ModelContext) -> PipelineFile? {
        let hits = (try? context.fetch(FetchDescriptor<PipelineFile>(
            predicate: #Predicate { $0.id == id || $0.filename == filename }))) ?? []
        // Prefer the id match — a filename hit is the legacy-row fallback. (Ownership by
        // ANOTHER memo can't be judged here without the memo list; the sweep, which has it,
        // applies that rule before this is ever reached.)
        return hits.first { $0.id == id } ?? hits.first
    }
}
