import Foundation
import SwiftData

/// The Mac's polished result for a memo, synced BACK to the phone via CloudKit — the
/// Mac→CloudKit write-back (`MAC_CLOUDKIT_PLAN.md`). A **sidecar** keyed by a loose
/// `memoID` (the `MemoAsset` pattern), NOT fields on `Memo`, so `Memo.transcript` stays
/// **RAW** — the contract spine the Mac trusts. The Mac never overwrites the phone's
/// transcript; it adds this derived layer, and `MemoExporter` PREFERS it when present, so
/// a paired Mac auto-upgrades the phone's standalone Obsidian export.
///
/// Carries the enhanced **pieces** (copy-edit / title / summary), not a pre-compiled
/// markdown blob — the phone re-compiles + re-links from them via the shared `Compiler` +
/// `MemoLinking` (deterministic, no drift). Written ONLY by the Mac (the phone has no
/// enhancement engine); LWW by `enhancedAt` if two Macs ever write.
///
/// CloudKit shape rules (mirror `Memo`/`MemoAsset`): every attribute has a default, and
/// there is NO `@Attribute(.unique)` (uniqueness is app-level — one enhancement per memo,
/// reconciled by `memoID`). This `@Model` is shared into BOTH apps via `Shared/Model`.
@Model
final class MemoEnhancement {
    /// The owning memo's UUID. Loose foreign key (see `MemoAsset`) — not a relationship.
    var memoID: UUID = UUID()

    /// The copy-edited body (fillers removed, grammar fixed). The phone re-links names over
    /// this before compiling, so it stays the Mac's RAW-names polish here.
    var copyedit: String = ""

    /// The LLM title + summary. Empty when the Mac skipped them (e.g. a too-short note).
    var title: String = ""
    var summary: String = ""

    /// The install that produced this (the Mac's `DeviceID`). Provenance + LWW tiebreak.
    var enhancedByDeviceID: String = ""
    var enhancedAt: Date = Date()

    init(memoID: UUID, copyedit: String = "", title: String = "", summary: String = "",
         enhancedByDeviceID: String = "", enhancedAt: Date = Date()) {
        self.memoID = memoID
        self.copyedit = copyedit
        self.title = title
        self.summary = summary
        self.enhancedByDeviceID = enhancedByDeviceID
        self.enhancedAt = enhancedAt
    }

    /// True when there's actually polished content to prefer (an empty enhancement — e.g. a
    /// placeholder row — falls back to the raw transcript everywhere).
    var hasContent: Bool {
        !copyedit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
