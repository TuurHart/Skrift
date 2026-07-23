import Foundation
import SwiftData

/// The polish-prompts reconcile — ONE algorithm for every polisher (Mac, iPad).
/// Whole-blob last-write-wins by `modifiedAt`, mirroring `VocabularySyncCore`
/// exactly (same fresh-device guard, same duplicate-carrier collapse). The
/// caller owns fetching/saving and its local store and applies the outcome.
enum PolishPromptsSyncCore {
    /// The three prompt texts as one LWW unit (they're one voice, not three
    /// knobs — syncing them piecemeal could mix two devices' half-edits).
    struct Blob: Equatable, Sendable {
        var copyEdit: String
        var summary: String
        var title: String

        static let defaults = Blob(copyEdit: PolishPrompts.copyEdit,
                                   summary: PolishPrompts.summary,
                                   title: PolishPrompts.title)
        var isAllDefault: Bool { self == .defaults }
    }

    enum Outcome: Equatable {
        /// The carrier is newer — the caller replaces its local prompts + stamp.
        case adoptRemote(blob: Blob, modifiedAt: Date)
        /// Local was newer (or first) — the carrier now holds the local blob. When
        /// `seededLocalStamp`, the local store had no stamp yet and should adopt `stamp`.
        case pushedLocal(stamp: Date, seededLocalStamp: Bool)
        /// Nothing to do (timestamps equal, or nothing anywhere yet).
        case noop
    }

    static func reconcile(localBlob: Blob, localModifiedAt: Date,
                          records: [PolishPromptsRecord], now: Date = Date(),
                          insert: (PolishPromptsRecord) -> Void,
                          delete: (PolishPromptsRecord) -> Void) -> Outcome {
        guard let newest = records.max(by: { $0.modifiedAt < $1.modifiedAt }) else {
            // No carrier yet. A device that has NEVER edited its prompts (all-default
            // + no stamp) must NOT create a default-@-now carrier: whole-blob LWW
            // would clobber another device's real tuning once it syncs. Wait to
            // RECEIVE instead. (A genuine "reset to defaults" carries a real local
            // stamp, so it still propagates.)
            guard !localBlob.isAllDefault || localModifiedAt != .distantPast else { return .noop }
            let seeded = localModifiedAt == .distantPast
            let ts = seeded ? now : localModifiedAt
            insert(PolishPromptsRecord(copyEdit: localBlob.copyEdit, summary: localBlob.summary,
                                       title: localBlob.title, modifiedAt: ts))
            return .pushedLocal(stamp: ts, seededLocalStamp: seeded)
        }

        // Collapse any duplicate carriers (two devices each created one pre-sync).
        for extra in records where extra !== newest { delete(extra) }

        if newest.modifiedAt > localModifiedAt {
            return .adoptRemote(blob: Blob(copyEdit: newest.copyEdit, summary: newest.summary,
                                           title: newest.title),
                                modifiedAt: newest.modifiedAt)
        } else if localModifiedAt > newest.modifiedAt {
            newest.copyEdit = localBlob.copyEdit
            newest.summary = localBlob.summary
            newest.title = localBlob.title
            newest.modifiedAt = localModifiedAt
            return .pushedLocal(stamp: localModifiedAt, seededLocalStamp: false)
        }
        return .noop
    }
}
