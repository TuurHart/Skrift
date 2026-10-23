import Foundation
import SwiftData

/// The WRITE-BACK side of the Mac→CloudKit client (`MAC_CLOUDKIT_PLAN.md`, 8c): after the
/// pipeline enhances a memo-sourced `PipelineFile`, upsert the Mac's polish (copy-edit /
/// title / summary) as a `MemoEnhancement` into the CloudKit `Memo` store, so it syncs back
/// to the phone + iPad. A **sidecar** keyed by `memoID` — the phone's `Memo.transcript` stays
/// RAW (the contract spine); `MemoExporter` already PREFERS this enhancement when present, so
/// a paired Mac auto-upgrades the phone's standalone Obsidian export with zero phone-UI work.
///
/// Any device may author an enhancement since iPad wave 1 (the iPad's on-demand
/// `PolishCenter` — same model, same shared prompts). LWW by `enhancedAt` between
/// writers; the guard below also refuses to clobber a strictly-newer other-device write.
enum MacCloudWriteBack {

    /// Recover the owning memo's UUID for a memo-sourced `PipelineFile`: the embedded
    /// filename (`memo_<uuid>.m4a` / `capture_<uuid>`), falling back to the row `id` (which
    /// a CloudKit-ingested row sets to the memo UUID). `nil` for a name that carries neither.
    ///
    /// A MAC RECORDING inverts that order, and getting it wrong is silent. Its filename is
    /// `memo_<uuid>.m4a` too — but that UUID is the RECORDER's, minted by
    /// `RecordingCore.filename()` for the audio file, while the Memo is authored under the
    /// row's own `id`. Preferring the filename therefore hands back a UUID no `Memo` has, and
    /// every Mac→cloud write keyed on it — rating, delete-sync, chosen title, the enhancement
    /// write-back — quietly does nothing at all. Found 2026-07-28 when clearing a bad rating on
    /// a real take changed the local row and left the phone's copy untouched.
    ///
    /// Prefer `resolve(for:in:)` where a store is at hand: it asks which UUID actually HAS a
    /// Memo, which is right for takes recorded before `isLocalRecording` existed too.
    static func memoID(for pf: PipelineFile) -> UUID? {
        pf.isLocalRecording
            ? UUID(uuidString: pf.id) ?? uuid(fromFilename: pf.filename)
            : uuid(fromFilename: pf.filename) ?? UUID(uuidString: pf.id)
    }

    /// The `Memo` this file belongs to, resolved against the STORE rather than by naming
    /// convention: try both candidate UUIDs and return whichever exists.
    ///
    /// Every writer should use this. A pure guess has to pick an order, and either order is
    /// wrong for some vintage of row — including the takes recorded before the recorder
    /// stamped `isLocalRecording`, which no rule about names can rescue. Asking the store
    /// can't be wrong.
    static func resolve(for pf: PipelineFile, in ctx: ModelContext) -> Memo? {
        var seen = Set<UUID>()
        for candidate in [memoID(for: pf), uuid(fromFilename: pf.filename), UUID(uuidString: pf.id)] {
            guard let candidate, seen.insert(candidate).inserted else { continue }
            if let memo = (try? ctx.fetch(
                FetchDescriptor<Memo>(predicate: #Predicate { $0.id == candidate })))?.first {
                return memo
            }
        }
        return nil
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
    /// `passRan` marks this as the write that follows a POLISH PASS (the coordinator's
    /// post-process + redo write-backs, both already gated on `enhanceStatus == .done`),
    /// as opposed to a manual-edit re-sync (`MacCloudEditSync`). Only a pass may record
    /// an EMPTY result: without it, a note the model had nothing to say about wrote no
    /// row at all, so the phone and iPad could never learn it had been processed.
    @discardableResult
    static func upsert(for pf: PipelineFile, into context: ModelContext,
                       deviceID: String, now: Date = Date(),
                       bodyOverride: String? = nil,
                       passRan: Bool = false) throws -> MemoEnhancement? {
        // Store-resolved, like every other writer: a Mac RECORDING's filename UUID isn't its
        // Memo's, so guessing here orphaned the polish for exactly the notes this Mac made.
        guard let memoID = resolve(for: pf, in: context)?.id else { return nil }

        let copyedit = bodyOverride ?? (pf.enhancedCopyedit ?? "")
        let title = pf.enhancedTitle ?? ""
        let summary = pf.enhancedSummary ?? ""
        // Nothing worth syncing back yet — leave the phone on the raw transcript. A PASS
        // is the exception: an empty result is still a fact the other devices need.
        guard passRan || !(copyedit.isEmpty && title.isEmpty && summary.isEmpty) else { return nil }

        // `resolve` already proved the memo exists in the synced store, so an enhancement can
        // never be orphaned onto a local-only / non-synced file.

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
        enhancement.pendingBlock = pf.pendingPolishBlock ?? ""   // C152: "" once a pass polished it
        enhancement.enhancedByDeviceID = deviceID
        enhancement.enhancedAt = now
        if passRan { enhancement.processedAt = now }
        if existing == nil { context.insert(enhancement) }
        try context.save()
        return enhancement
    }
}
