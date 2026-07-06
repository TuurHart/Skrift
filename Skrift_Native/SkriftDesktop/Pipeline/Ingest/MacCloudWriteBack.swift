import Foundation
import SwiftData

/// The WRITE-BACK side of the Mac→CloudKit client (`MAC_CLOUDKIT_PLAN.md`, 8c): after the
/// pipeline enhances a memo-sourced `PipelineFile`, upsert the Mac's polish (copy-edit /
/// title / summary) as a `MemoEnhancement` into the CloudKit `Memo` store, so it syncs back
/// to the phone + iPad. A **sidecar** keyed by `memoID` — the phone's `Memo.transcript` stays
/// RAW (the contract spine); `MemoExporter` already PREFERS this enhancement when present, so
/// a paired Mac auto-upgrades the phone's standalone Obsidian export with zero phone-UI work.
///
/// Written ONLY by the Mac (the phone has no enhancement engine). LWW by `enhancedAt` if two
/// Macs ever process the same memo; for the single-user/single-Mac case the latest run wins.
enum MacCloudWriteBack {

    /// Recover the owning memo's UUID for a memo-sourced `PipelineFile`: the embedded
    /// filename (`memo_<uuid>.m4a` / `capture_<uuid>`), falling back to the row `id` (which
    /// a CloudKit-ingested row sets to the memo UUID). `nil` for a name that carries neither.
    static func memoID(for pf: PipelineFile) -> UUID? {
        uuid(fromFilename: pf.filename) ?? UUID(uuidString: pf.id)
    }

    /// Parse the memo UUID out of a `memo_<uuid>.<ext>` / `capture_<uuid>` filename.
    static func uuid(fromFilename name: String) -> UUID? {
        for prefix in ["memo_", "capture_"] where name.hasPrefix(prefix) {
            let stem = (name as NSString).deletingPathExtension          // strip .m4a etc.
            return UUID(uuidString: String(stem.dropFirst(prefix.count)))
        }
        return nil
    }

    /// Upsert the polish for a just-enhanced file into the CloudKit Memo `context`. Returns the
    /// written `MemoEnhancement`, or `nil` when skipped: not a synced memo (no matching `Memo`
    /// row in the CloudKit store — e.g. a locally-ingested file), or nothing to write yet (no
    /// copy-edit / title / summary). The phone re-links + re-compiles from the pieces, so only
    /// the raw-names polish + provenance is stored (no pre-compiled markdown).
    /// `bodyOverride` carries the LIVE-EDITED body for the Mac→phone edit write-back (Part B):
    /// a manual edit lands in `pf.sanitised` (names `[[linked]]`), so the edit path passes the
    /// un-linked `Sanitiser.unlinkToSpoken(pf.bestBodyText, people:)` here — the phone stores that
    /// RAW copy-edit and re-links it. `nil` (the post-process path) uses `pf.enhancedCopyedit`.
    @discardableResult
    static func upsert(for pf: PipelineFile, into context: ModelContext,
                       deviceID: String, now: Date = Date(),
                       bodyOverride: String? = nil) throws -> MemoEnhancement? {
        guard let memoID = memoID(for: pf) else { return nil }

        let copyedit = bodyOverride ?? (pf.enhancedCopyedit ?? "")
        let title = pf.enhancedTitle ?? ""
        let summary = pf.enhancedSummary ?? ""
        // Nothing worth syncing back yet — leave the phone on the raw transcript.
        guard !(copyedit.isEmpty && title.isEmpty && summary.isEmpty) else { return nil }

        // Only write back for a memo that actually exists in the synced store — never orphan
        // an enhancement onto a local-only / non-synced file.
        let memoExists = ((try? context.fetchCount(
            FetchDescriptor<Memo>(predicate: #Predicate { $0.id == memoID }))) ?? 0) > 0
        guard memoExists else { return nil }

        let existing = try context.fetch(
            FetchDescriptor<MemoEnhancement>(predicate: #Predicate { $0.memoID == memoID })).first
        // Echo/LWW guard (Part B): don't clobber a STRICTLY-NEWER edit made on ANOTHER device
        // (a phone edit that arrived while this write was queued). Our own device's earlier
        // write is always safe to update. `enhancedAt` is the last-write-wins key.
        if let existing, existing.enhancedByDeviceID != deviceID, existing.enhancedAt > now {
            return existing
        }
        let enhancement = existing ?? MemoEnhancement(memoID: memoID)
        enhancement.copyedit = copyedit
        enhancement.title = title
        enhancement.summary = summary
        enhancement.enhancedByDeviceID = deviceID
        enhancement.enhancedAt = now
        if existing == nil { context.insert(enhancement) }
        try context.save()
        return enhancement
    }
}
