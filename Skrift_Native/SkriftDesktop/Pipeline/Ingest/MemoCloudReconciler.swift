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
    }

    /// Sweep every `Memo` in `cloudContext` into `localContext` (the pipeline store): fetch each
    /// memo's `MemoAsset` blob rows and either INGEST it (never seen) or, if already ingested,
    /// reflect a newer phone EDIT via `MemoCloudUpdate` (Part B, phone→Mac live sync). Gated
    /// (significance) / unchanged memos are no-ops. Pure (takes both contexts + roster/author)
    /// so it's unit-testable host-less.
    @discardableResult
    static func sweep(from cloudContext: ModelContext, into localContext: ModelContext,
                      processEverything: Bool,
                      people: [Person] = [], author: String = "", thisDeviceID: String = "",
                      now: Date = Date()) -> SweepOutcome {
        // Duplicate-tolerant: the cloud DB can hold same-id rows (the 2026-07-12 clone
        // incident; divergent pairs are never auto-healed). Collapse each id onto its
        // keeper (shared `MemoDuplicates` rule — the same row the phone's deduper keeps),
        // else two rows would take turns rewriting ONE PipelineFile every sweep
        // (recompile + re-export churn, forever).
        let memos = MemoDuplicates.canonicalRows(
            (try? cloudContext.fetch(FetchDescriptor<Memo>())) ?? [])
        var outcome = SweepOutcome()
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
            if let pf = fileByID[id] ?? (filename.isEmpty ? nil : fileByFilename[filename]) {
                // Already have a row — reflect a phone edit into it (no-op when up to date).
                let applied = MemoCloudUpdate.apply(memo: memo, enhancement: enhancementByMemo[memoID], to: pf,
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
                if healed && !applied { pf.lastActivityAt = now }
                if applied || healed { outcome.updatedIDs.append(pf.id) }
            } else {
                // nil = gated/trashed (a legitimate no-op); a THROW is a real failure —
                // previously `try?`-swallowed, making a memo that fails every sweep an
                // invisible black hole. Count + name it for the reconcile summary.
                do {
                    if let created = try MemoCloudIngest.ingest(memo: memo, assets: fetchAssets(),
                                                                into: localContext,
                                                                processEverything: processEverything) {
                        outcome.created += 1
                        // Keep the lookup maps live so a same-sweep duplicate
                        // (Bonjour-era filename twin) can't double-ingest.
                        if fileByID[created.id] == nil { fileByID[created.id] = created }
                        if !created.filename.isEmpty, fileByFilename[created.filename] == nil {
                            fileByFilename[created.filename] = created
                        }
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
        (try? context.fetch(FetchDescriptor<PipelineFile>(
            predicate: #Predicate { $0.id == id || $0.filename == filename }))).flatMap(\.first)
    }
}
