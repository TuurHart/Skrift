import Foundation

/// THE list of fields that live on BOTH the Mac's local `PipelineFile` and the synced
/// `Memo` — declared ONCE, so adding one is a single entry here instead of a hand-written
/// copy in `MemoCloudIngest`, another in `MemoCloudUpdate`, and a third in
/// `MacCloudMetaSync`. Every bug in this seam has been one of those copies drifting:
/// un-rating on the Mac reaching nothing (2026-07-26), and the rate→row hole (2026-08-20).
///
/// **Why the duplication exists at all — do NOT "simplify" it away.** `PipelineFile` is
/// local SwiftData; `Memo` is the CloudKit store. The Mac must keep working with
/// `cloudKitMacSyncEnabled` OFF, and with legacy/demo rows whose id isn't a memo UUID —
/// in both cases `MacMemoAuthor` never authors a `Memo`, so there is no counterpart to
/// read through to. The copies are what make that work. What was needless was maintaining
/// them by hand in three files; that is what this type removes.
///
/// **Deliberately NOT here:** `title` and `transcript`. Both carry ADOPT-ONLY semantics —
/// `memo.title == nil` is the DEFAULT state of every note, so a nil must never clear the
/// title chosen on the Mac. That is real logic, not a mirror, and it keeps its explicit
/// code in `MemoCloudUpdate`.
enum MirroredNoteFields {

    struct Field {
        let name: String

        /// phone → Mac, on a live update. Returns true when it changed the file.
        let pull: (Memo, PipelineFile) -> Bool

        /// Does a change here mean the Mac must RECOMPILE the note? Tags and importance
        /// reach the frontmatter; the lock flag and the reminder do not.
        let recompiles: Bool

        /// Mac → phone on the PASSIVE mirror pass. `nil` means **event-only** in that
        /// direction: a value whose "empty" is ambiguous must never ride a passive pass.
        /// See `significance` below — it is the reason this field exists.
        let push: ((PipelineFile, Memo) -> Bool)?

        /// FIRST CONTACT (`MemoCloudIngest`), where the row is brand new. Defaults to
        /// `pull`; `tags` overrides it because a just-created row may already carry the
        /// Mac's own derived tags, which an empty phone list must not wipe.
        let adopt: (Memo, PipelineFile) -> Bool

        init(name: String,
             recompiles: Bool,
             pull: @escaping (Memo, PipelineFile) -> Bool,
             push: ((PipelineFile, Memo) -> Bool)? = nil,
             adopt: ((Memo, PipelineFile) -> Bool)? = nil) {
            self.name = name
            self.recompiles = recompiles
            self.pull = pull
            self.push = push
            self.adopt = adopt ?? pull
        }
    }

    static let all: [Field] = [
        Field(name: "tags", recompiles: true,
              pull: { memo, pf in
                  guard pf.tags != memo.tags else { return false }
                  pf.tags = memo.tags
                  return true
              },
              push: { pf, memo in
                  guard memo.tags != pf.tags else { return false }
                  memo.tags = pf.tags
                  return true
              },
              adopt: { memo, pf in
                  // First contact only: the Mac's own derivation lands in `tagSuggestions`,
                  // but a row can already carry applied tags — an empty phone list is not a
                  // reason to clear them.
                  guard !memo.tags.isEmpty, pf.tags != memo.tags else { return false }
                  pf.tags = memo.tags
                  return true
              }),

        Field(name: "significance", recompiles: true,
              pull: { memo, pf in
                  guard pf.significance != memo.significance else { return false }
                  pf.significance = memo.significance
                  return true
              },
              // A nil is SKIPPED here on purpose. This is a passive "mirror current values"
              // pass that also runs on tag edits, and `nil` is ambiguous on a `PipelineFile`:
              // it means "cleared" OR "never rated". A legacy Mac import (pre-D159) legitimately sits at
              // nil while its authored `Memo` carries `MacMemoAuthor`'s 0.1 floor, so treating
              // nil as 0 here would silently un-rate it on the next tag edit. Clearing is an
              // EVENT — `MacCloudMetaSync.setRating`.
              push: { pf, memo in
                  guard let sig = pf.significance, memo.significance != sig else { return false }
                  memo.significance = sig
                  return true
              }),

        // Event-only Mac→phone (`MacCloudMetaSync.setDestination`): a destination change
        // decides whether a note may leave for a repo an AI reads, so it lands the moment
        // it is made rather than on the next unrelated tag edit.
        Field(name: "destination", recompiles: true,
              pull: { memo, pf in
                  guard pf.destination != memo.destination else { return false }
                  pf.destination = memo.destination
                  return true
              }),

        // Row mirrors that need no recompile. Phone-authored only — the Mac has no control
        // that writes either one, so neither has a push.
        Field(name: "locked", recompiles: false,
              pull: { memo, pf in
                  guard pf.locked != memo.locked else { return false }
                  pf.locked = memo.locked
                  return true
              }),

        Field(name: "remindAt", recompiles: false,
              pull: { memo, pf in
                  guard pf.remindAt != memo.remindAt else { return false }
                  pf.remindAt = memo.remindAt
                  return true
              }),
    ]

    /// Every field the passive Mac→phone mirror carries.
    static var pushable: [Field] { all.filter { $0.push != nil } }
}
