import Foundation
import SwiftData

/// The per-book bookmark reconcile (iPad wave, 2026-07-23) — whole-list LWW by
/// `modifiedAt`, mirroring `VocabularySyncCore`/`PolishPromptsSyncCore` exactly
/// (same fresh-device guard, same duplicate-carrier collapse). Mobile-only (the
/// Mac plays no books); the caller owns fetching/saving and the `BookmarkStore`.
enum AudiobookBookmarkSyncCore {
    enum Outcome: Equatable {
        /// The carrier is newer — the caller adopts list + stamp into the store.
        case adoptRemote(items: [AudiobookBookmark], modifiedAt: Date)
        /// Local was newer (or first) — the carrier now holds the local list. When
        /// `seededLocalStamp`, the store had no stamp yet and should adopt `stamp`.
        case pushedLocal(stamp: Date, seededLocalStamp: Bool)
        case noop
    }

    static func reconcile(bookID: UUID, localItems: [AudiobookBookmark], localModifiedAt: Date,
                          records: [AudiobookBookmarksRecord], now: Date = Date(),
                          insert: (AudiobookBookmarksRecord) -> Void,
                          delete: (AudiobookBookmarksRecord) -> Void) -> Outcome {
        let mine = records.filter { $0.bookID == bookID }
        guard let newest = mine.max(by: { $0.modifiedAt < $1.modifiedAt }) else {
            // No carrier yet. A device that never bookmarked this book (empty +
            // no stamp) must NOT mint an empty-@-now carrier — whole-list LWW
            // would wipe the other device's real bookmarks once it syncs. Wait
            // to RECEIVE. (A genuine "removed my last bookmark" has a real
            // stamp, so the deletion still propagates.)
            guard !localItems.isEmpty || localModifiedAt != .distantPast else { return .noop }
            guard let blob = try? JSONEncoder().encode(localItems) else { return .noop }
            let seeded = localModifiedAt == .distantPast
            let ts = seeded ? now : localModifiedAt
            insert(AudiobookBookmarksRecord(bookID: bookID, itemsBlob: blob, modifiedAt: ts))
            return .pushedLocal(stamp: ts, seededLocalStamp: seeded)
        }

        // Collapse duplicate carriers (two devices each created one pre-sync).
        for extra in mine where extra !== newest { delete(extra) }

        if newest.modifiedAt > localModifiedAt {
            let items = (try? JSONDecoder().decode([AudiobookBookmark].self, from: newest.itemsBlob)) ?? []
            return .adoptRemote(items: items, modifiedAt: newest.modifiedAt)
        } else if localModifiedAt > newest.modifiedAt {
            guard let blob = try? JSONEncoder().encode(localItems) else { return .noop }
            newest.itemsBlob = blob
            newest.modifiedAt = localModifiedAt
            return .pushedLocal(stamp: localModifiedAt, seededLocalStamp: false)
        }
        return .noop
    }
}
