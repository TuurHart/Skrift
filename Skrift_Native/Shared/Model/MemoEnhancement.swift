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
/// `MemoLinking` (deterministic, no drift). Any device may author one — the Mac's batch
/// polisher and, since iPad wave 1 (2026-07-22), the iPad's on-demand `PolishCenter`
/// (same model, same `PolishPrompts`); LWW by `enhancedAt` between writers.
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

    /// When a polish PASS last ran for this note — set by every polisher (the Mac's batch,
    /// the iPad's `PolishCenter`) whether or not the model had anything to say. Optional
    /// with a nil default, so it is an additive CloudKit change and pre-existing rows
    /// simply carry nil. See `isProcessed`.
    var processedAt: Date? = nil

    init(memoID: UUID, copyedit: String = "", title: String = "", summary: String = "",
         enhancedByDeviceID: String = "", enhancedAt: Date = Date(),
         processedAt: Date? = nil) {
        self.memoID = memoID
        self.copyedit = copyedit
        self.title = title
        self.summary = summary
        self.enhancedByDeviceID = enhancedByDeviceID
        self.enhancedAt = enhancedAt
        self.processedAt = processedAt
    }

    /// True when there's actually polished content to prefer (an empty enhancement — e.g. a
    /// placeholder row — falls back to the raw transcript everywhere).
    var hasContent: Bool {
        !copyedit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Has a polish pass RUN for this note? A DIFFERENT question from `hasContent`
    /// ("is there polish worth showing instead of the raw text?"), and conflating the
    /// two is what stranded notes the model had nothing to say about — a bare shared
    /// photo, a three-word note, a link with no comment. They were PROCESSED and had NO
    /// CONTENT, so every gate read them as unprocessed: the export button said "Process
    /// this note first" forever, pressing it did the identical nothing, and on the iPad
    /// they never left the to-process pile (2026-08-26).
    ///
    /// Rows written before `processedAt` existed carry nil, so they fall back to the
    /// ALL-THREE rule — never "any part present", because a note's polished title is
    /// also written from the user's own chosen title, and that would call a merely
    /// retitled note processed. (That rule was hand-rolled inside the phone's
    /// `MemoDetailView`; it lives here now, where all three apps read it.)
    var isProcessed: Bool {
        Self.isProcessed(processedAt: processedAt, copyedit: copyedit, title: title, summary: summary)
    }

    /// The rule on bare values, for a caller holding a row's fields rather than a
    /// `MemoEnhancement` (`NoteWorkState.Inputs.LocalPolish`, the Mac's `PipelineFile`).
    static func isProcessed(processedAt: Date?, copyedit: String, title: String, summary: String) -> Bool {
        if processedAt != nil { return true }
        func filled(_ s: String) -> Bool {
            !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return filled(copyedit) && filled(title) && filled(summary)
    }
}
