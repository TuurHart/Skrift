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
        for memo in memos {
            let memoID = memo.id
            let assets = (try? cloudContext.fetch(
                FetchDescriptor<MemoAsset>(predicate: #Predicate { $0.memoID == memoID }))) ?? []
            let id = memo.id.uuidString
            let filename = MemoCloudIngest.audioFilename(for: memo)

            if MemoCloudIngest.alreadyIngested(id: id, filename: filename, in: localContext) {
                // Already have a row — reflect a phone edit into it (no-op when up to date).
                guard let pf = existingFile(id: id, filename: filename, in: localContext) else { continue }
                let enhancement = (try? cloudContext.fetch(
                    FetchDescriptor<MemoEnhancement>(predicate: #Predicate { $0.memoID == memoID }))) ?? []
                let applied = MemoCloudUpdate.apply(memo: memo, enhancement: enhancement.first, to: pf,
                                                    people: people, author: author,
                                                    thisDeviceID: thisDeviceID, now: now)
                // Materialize photos the phone added AFTER first ingest — the update path above
                // reflects the [[img_NNN]] markers but never wrote the image files (they'd render
                // as literal text + miss the vault). Idempotent; heals an already-broken note on
                // the next sweep. When it heals a row `apply` didn't touch, nudge lastActivityAt so
                // the open review body re-renders and resolves the markers. Skip a trashed memo —
                // no point materializing photos for something in the bin.
                let healed = memo.deletedAt == nil
                    && MemoPhotoMaterializer.materializeMissing(memo: memo, assets: assets, pf: pf)
                if healed && !applied { pf.lastActivityAt = now }
                if applied || healed { outcome.updatedIDs.append(pf.id) }
            } else {
                // nil = gated/trashed (a legitimate no-op); a THROW is a real failure —
                // previously `try?`-swallowed, making a memo that fails every sweep an
                // invisible black hole. Count + name it for the reconcile summary.
                do {
                    if try MemoCloudIngest.ingest(memo: memo, assets: assets, into: localContext,
                                                  processEverything: processEverything) != nil {
                        outcome.created += 1
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
