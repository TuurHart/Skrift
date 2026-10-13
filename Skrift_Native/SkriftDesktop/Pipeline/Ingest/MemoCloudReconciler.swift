import Foundation
import SwiftData
import os

/// The reconcile loop for the Mac→CloudKit client (`MAC_CLOUDKIT_PLAN.md`, 8d): pull memos
/// the phone synced over CloudKit into the local pipeline queue, so the Mac processes them
/// like any other note. The launch / foreground / CloudKit-import TRIGGERS +
/// the `reconcile()` entry point (which resolve the app's containers + settings) live in the
/// app-only `MemoCloudReconciler+Wiring.swift` extension; this file holds the pure, testable
/// `sweep` so it compiles into the host-less test bundle.
///
/// Gated by `cloudKitMacSyncEnabled` (defaults ON), and `MemoCloudIngest` dedups by memo
/// UUID / embedded filename, so a memo collapses to one `PipelineFile`. Bonjour/HTTP sync is
/// retired; CloudKit is the only transport.
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
        /// Never-seen memos a `deferNewIngest` sweep left for the background ingest (Q364).
        var pendingNewIDs: [UUID] = []
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
                      people: [Person] = [], author: String = "", thisDeviceID: String = "",
                      now: Date = Date(),
                      upload: UploadService = UploadService()) -> SweepOutcome {
        sweepCore(from: cloudContext, into: localContext, people: people, author: author,
                  thisDeviceID: thisDeviceID, now: now, upload: upload, deferNewIngest: false).outcome
    }

    /// What one sweep fetched, handed back so the rest of the pass (author/reflect, the
    /// lifecycle sweep, the Connections snapshot) reuses it instead of fetching again (Q364).
    struct SweepSnapshot {
        /// Every `Memo` row as fetched (duplicates included — the lifecycle sweep's input).
        var allMemos: [Memo] = []
        /// The keeper per id (`MemoDuplicates.canonicalRows`) — what the sweep iterated.
        var memos: [Memo] = []
        var enhancements: [MemoEnhancement] = []
        /// The local rows after the sweep (pre-sweep fetch + rows this sweep created).
        var localFiles: [PipelineFile] = []
    }

    /// The memo ids whose blob-reading ingest runs on a background context right now
    /// (`prepareInBackground` → `commitPrepared`). A sweep in between skips them, so two
    /// overlapping reconciles can never ingest one memo twice.
    static var ingestInFlight: Set<UUID> = []

    /// The sweep. `deferNewIngest` (the app's reconcile): never-seen memos are NOT ingested
    /// here on the main actor; their ids come back in `pendingNewIDs` for the background
    /// ingest. false (tests, the headless harness): they ingest here, as one batch, one save.
    static func sweepCore(from cloudContext: ModelContext, into localContext: ModelContext,
                          people: [Person], author: String, thisDeviceID: String,
                          now: Date, upload: UploadService,
                          deferNewIngest: Bool) -> (outcome: SweepOutcome, snapshot: SweepSnapshot) {
        // Duplicate-tolerant: the cloud DB can hold same-id rows (the 2026-07-12 clone
        // incident; divergent pairs are never auto-healed). Collapse each id onto its
        // keeper (shared `MemoDuplicates` rule — the same row the phone's deduper keeps),
        // else two rows would take turns rewriting ONE PipelineFile every sweep
        // (recompile + re-export churn, forever).
        ReconcileWork.bump(\.memoFetches)
        let allMemos = (try? cloudContext.fetch(FetchDescriptor<Memo>())) ?? []
        let memos = MemoDuplicates.canonicalRows(allMemos)
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
        var localFiles = (try? localContext.fetch(FetchDescriptor<PipelineFile>())) ?? []
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
        // Q364: which asset KINDS each memo has, from ONE blob-free fetch, built only when a
        // late-asset heal first asks. A memo with no `diar` / `wordTimings` asset — every
        // monologue, every typed note — then never reaches `fetchAssets()`.
        let assetKinds = AssetKindIndex(cloudContext)
        var newMemos: [Memo] = []
        for memo in memos {
            let memoID = memo.id
            let id = memo.id.uuidString
            let filename = MemoCloudIngest.audioFilename(for: memo)
            let fetchAssets: () -> [MemoAsset] = {
                ReconcileWork.bump(\.assetBlobFetches)
                return (try? cloudContext.fetch(
                    FetchDescriptor<MemoAsset>(predicate: #Predicate { $0.memoID == memoID }))) ?? []
            }

            // Same match rule as `alreadyIngested` (id OR embedded
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
                let timingsHealed = MemoCloudIngest.adoptLateWordTimings(
                    memo: memo, pf: pf, assetKinds: { assetKinds.kinds(memoID) }, fetchAssets: fetchAssets)
                // …and the diarization twin (a late `diar` asset otherwise leaves the Mac
                // unable to enroll a voice from a phone-diarized conversation).
                let diarHealed = MemoCloudIngest.adoptLateDiarization(
                    memo: memo, pf: pf, assetKinds: { assetKinds.kinds(memoID) }, fetchAssets: fetchAssets)
                let anyHeal = healed || timingsHealed || diarHealed
                if anyHeal && !applied { pf.lastActivityAt = now }
                if applied || anyHeal { outcome.updatedIDs.append(pf.id) }
            } else if memo.deletedAt == nil, NoteConsent.isRated(memo), !ingestInFlight.contains(memoID) {
                // Never seen, live and rated: ingest (the gates `MemoCloudIngest.ingest`
                // applies; a trashed or unrated memo is a legitimate no-op). The sweep's maps
                // already proved there is no row by id, and none by filename this memo may
                // claim, so the batch skips `alreadyIngested`'s per-memo fetch (G3).
                newMemos.append(memo)
            }
        }

        if deferNewIngest {
            outcome.pendingNewIDs = newMemos.map(\.id)
        } else if !newMemos.isEmpty {
            // Inline batch: prepare each (blob reads + disk writes), then ONE commit + save.
            let items = newMemos.map { memo -> PreparedNew in
                let mid = memo.id
                do {
                    let assets = (try? cloudContext.fetch(FetchDescriptor<MemoAsset>(
                        predicate: #Predicate { $0.memoID == mid }))) ?? []
                    ReconcileWork.bump(\.assetBlobFetches)
                    return PreparedNew(memoID: memo.id, prepared: try upload.prepare(memo: memo, assets: assets),
                                       failure: nil)
                } catch {
                    return PreparedNew(memoID: memo.id, prepared: nil, failure: String(describing: error))
                }
            }
            let created = commit(items, memosByID: Dictionary(newMemos.map { ($0.id, $0) },
                                                              uniquingKeysWith: { a, _ in a }),
                                 enhancementByMemo: enhancementByMemo, into: localContext,
                                 people: people, author: author, thisDeviceID: thisDeviceID,
                                 now: now, upload: upload, outcome: &outcome)
            localFiles.append(contentsOf: created)
        }
        let snapshot = SweepSnapshot(allMemos: allMemos, memos: memos, enhancements: enhancements,
                                     localFiles: localFiles)
        return (outcome, snapshot)
    }

    /// One never-seen memo after its disk phase: the row descriptor, nil when there is
    /// nothing to ingest yet (a voice memo whose audio blob hasn't synced), or a failure.
    struct PreparedNew: Sendable {
        let memoID: UUID
        let prepared: UploadService.PreparedUpload?
        let failure: String?
    }

    /// Commit a batch of prepared memos as rows: ONE `UploadService.commit`, the fresh-row
    /// finish (`MemoCloudIngest.finishIngest`) and the fresh-row reflect for each, ONE save.
    /// Same per-memo outcome as the old one-at-a-time ingest: created, stranded, failed.
    @discardableResult
    static func commit(_ items: [PreparedNew], memosByID: [UUID: Memo],
                       enhancementByMemo: [UUID: MemoEnhancement], into localContext: ModelContext,
                       people: [Person], author: String, thisDeviceID: String, now: Date,
                       upload: UploadService, outcome: inout SweepOutcome) -> [PipelineFile] {
        var ready: [(memo: Memo, prepared: UploadService.PreparedUpload)] = []
        for item in items {
            guard let memo = memosByID[item.memoID] else { continue }
            if let failure = item.failure {
                // A THROW is a real failure — previously `try?`-swallowed, making a memo that
                // fails every sweep an invisible black hole. Count + name it.
                outcome.ingestFailures += 1
                AppLog.cloudkit.error("ingest FAILED memo \(memo.id, privacy: .public): \(failure)")
            } else if let prepared = item.prepared {
                ready.append((memo, prepared))
            } else if memo.deletedAt == nil, NoteConsent.isRated(memo) {
                // Rated, live, and STILL no row: the memo renders in no list section
                // at all. Every known cause is fixed (a typed note ingests as a text
                // row now); what remains is a genuine wait — a voice memo whose audio
                // blob hasn't synced yet — so name it rather than let the next one be
                // silent for a day.
                outcome.stranded += 1
                AppLog.cloudkit
                    .error("STRANDED: rated memo \(memo.id, privacy: .public) has no row after ingest — invisible in every list section")
            }
        }
        guard !ready.isEmpty else { return [] }
        let rows: [PipelineFile]
        do {
            rows = try upload.commit(ready.map(\.prepared), into: localContext, save: false)
        } catch {
            outcome.ingestFailures += ready.count
            AppLog.cloudkit.error("ingest batch FAILED (\(ready.count, privacy: .public) memos): \(error)")
            return []
        }
        for (row, entry) in zip(rows, ready) {
            MemoCloudIngest.finishIngest(row, memo: entry.memo)
            outcome.created += 1
            // Give the FRESH row everything the cloud already knows — above all a
            // `MemoEnhancement` that exists while the row does not, which is the
            // only copy of that polish anywhere. Without this the note surfaces
            // raw and waits for the NEXT sweep, where the self-echo guard throws
            // this Mac's own enhancement away for good (`isFreshRow` turns that
            // guard off exactly here, and nowhere else).
            if MemoCloudUpdate.apply(memo: entry.memo, enhancement: enhancementByMemo[entry.memo.id],
                                     to: row, people: people, author: author,
                                     thisDeviceID: thisDeviceID, now: now, isFreshRow: true) {
                outcome.updatedIDs.append(row.id)
            }
        }
        do {
            ReconcileWork.bump(\.saves)
            try localContext.save()
        } catch {
            AppLog.cloudkit.error("ingest batch save FAILED (\(rows.count, privacy: .public) rows): \(error)")
        }
        return rows
    }

    /// The background half of the app's ingest (g-mac-pipeline G3): read each new memo's
    /// asset blobs and write its working folder on a BACKGROUND context, off the main actor.
    /// Returns Sendable descriptors; `commitPrepared` inserts them on the main actor.
    nonisolated static func prepareInBackground(ids: [UUID], container: ModelContainer,
                                                upload: UploadService) async -> [PreparedNew] {
        await Task.detached(priority: .userInitiated) {
            let ctx = ModelContext(container)
            let memos = (try? ctx.fetch(FetchDescriptor<Memo>(predicate: #Predicate { ids.contains($0.id) }))) ?? []
            let byID = Dictionary(memos.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            return ids.compactMap { id -> PreparedNew? in
                guard let memo = byID[id] else { return nil }
                let assets = (try? ctx.fetch(FetchDescriptor<MemoAsset>(
                    predicate: #Predicate { $0.memoID == id }))) ?? []
                do {
                    return PreparedNew(memoID: id, prepared: try upload.prepare(memo: memo, assets: assets),
                                       failure: nil)
                } catch {
                    return PreparedNew(memoID: id, prepared: nil, failure: String(describing: error))
                }
            }
        }.value
    }

    /// The main-actor half: one memo fetch + one enhancement fetch + one local-row fetch
    /// for the whole batch (a row that appeared meanwhile is skipped), then `commit`.
    static func commitPrepared(_ items: [PreparedNew], cloud cloudContext: ModelContext,
                               into localContext: ModelContext, people: [Person], author: String,
                               thisDeviceID: String, now: Date = Date(),
                               upload: UploadService = UploadService()) -> SweepOutcome {
        var outcome = SweepOutcome()
        let ids = items.map(\.memoID)
        guard !ids.isEmpty else { return outcome }
        let idStrings = ids.map(\.uuidString)
        let existing = Set(((try? localContext.fetch(FetchDescriptor<PipelineFile>(
            predicate: #Predicate { idStrings.contains($0.id) }))) ?? []).map(\.id))
        ReconcileWork.bump(\.memoFetches)
        let memos = MemoDuplicates.canonicalRows((try? cloudContext.fetch(FetchDescriptor<Memo>(
            predicate: #Predicate { ids.contains($0.id) }))) ?? [])
        let enhancements = (try? cloudContext.fetch(FetchDescriptor<MemoEnhancement>(
            predicate: #Predicate { ids.contains($0.memoID) }))) ?? []
        commit(items.filter { !existing.contains($0.memoID.uuidString) },
               memosByID: Dictionary(memos.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a }),
               enhancementByMemo: Dictionary(enhancements.map { ($0.memoID, $0) }, uniquingKeysWith: { a, _ in a }),
               into: localContext, people: people, author: author, thisDeviceID: thisDeviceID,
               now: now, upload: upload, outcome: &outcome)
        return outcome
    }

    /// What one reconcile pass did, plus the fetches it made (for reuse by the callers).
    struct PassOutcome {
        var sweep: SweepOutcome
        var authored = 0
        var reflectedTranscripts = 0
        /// Every `Memo` row the pass fetched (duplicates included).
        var memos: [Memo] = []
        var enhancements: [MemoEnhancement] = []
        var localFiles: [PipelineFile] = []
    }

    /// The reconcile pass minus the app wiring (containers, settings, re-export): the sweep,
    /// a save when it reflected anything, then `MacMemoAuthor.backfill` + `reflectTranscripts`
    /// over ONE id→Memo dictionary built from the sweep's own fetch (g-mac-pipeline G2,
    /// h-shared-data M3: was one unindexed `Memo` fetch per local row, twice).
    /// Author/reflect failures are logged and swallowed, as before: they must never take down
    /// the ingest/reflect this exists for.
    /// `firstImportDone` (Q397, ICLOUD_MERGE A1): has the cloud store finished its first
    /// CloudKit import (`CloudFirstImport`)? Until then the backfill authors nothing; it
    /// defaults to false so a caller that forgets it can never mint twins.
    @discardableResult
    static func pass(from cloudContext: ModelContext, into localContext: ModelContext,
                     people: [Person] = [], author: String = "", thisDeviceID: String = "",
                     now: Date = Date(), upload: UploadService = UploadService(),
                     deferNewIngest: Bool = false, firstImportDone: Bool = false) throws -> PassOutcome {
        let (outcome, snapshot) = sweepCore(from: cloudContext, into: localContext, people: people,
                                            author: author, thisDeviceID: thisDeviceID, now: now,
                                            upload: upload, deferNewIngest: deferNewIngest)
        var result = PassOutcome(sweep: outcome, memos: snapshot.allMemos,
                                 enhancements: snapshot.enhancements, localFiles: snapshot.localFiles)
        // A phone edit re-linked + recompiled an existing row (Part B). Persist it.
        if !outcome.updatedIDs.isEmpty {
            do {
                ReconcileWork.bump(\.saves)
                try localContext.save()
            } catch {
                AppLog.cloudkit
                    .error("reconcile: reflect save FAILED — phone edits not persisted: \(error)")
            }
        }
        var memosByID: [UUID: Memo] = [:]
        for memo in snapshot.memos { memosByID[memo.id] = memo }
        do {
            result.authored = try MacMemoAuthor.backfill(files: snapshot.localFiles, into: cloudContext,
                                                         memosByID: &memosByID,
                                                         firstImportDone: firstImportDone)
            result.reflectedTranscripts = try MacMemoAuthor.reflectTranscripts(
                files: snapshot.localFiles, into: cloudContext, memosByID: memosByID)
        } catch {
            AppLog.cloudkit.error("reconcile: author/reflect FAILED: \(error)")
        }
        return result
    }
}

/// Q364 (C278): the asset kinds each memo has, from ONE `MemoAsset` fetch that names its
/// properties — never the blob — built on first use.
@MainActor
final class AssetKindIndex {
    private let context: ModelContext
    private var map: [UUID: Set<String>]?

    init(_ context: ModelContext) { self.context = context }

    func kinds(_ memoID: UUID) -> Set<String> {
        if map == nil {
            ReconcileWork.bump(\.assetIndexFetches)
            var d = FetchDescriptor<MemoAsset>(); d.propertiesToFetch = [\.memoID, \.kind]
            var built: [UUID: Set<String>] = [:]
            for asset in (try? context.fetch(d)) ?? [] { built[asset.memoID, default: []].insert(asset.kind) }
            map = built
        }
        return map?[memoID] ?? []
    }
}
