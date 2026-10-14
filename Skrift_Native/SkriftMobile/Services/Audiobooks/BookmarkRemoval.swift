import Foundation

/// What one bookmark removal did (C269/R82). EVERY removal path (player margin tap,
/// swipe in the bookmarks sheet) removes exactly ONE bookmark and shows `notice` with
/// an Undo, so a removal is never silent and never ambiguous about how many went.
struct BookmarkRemoval: Equatable {
    let removed: AudiobookBookmark
    /// The sorted list after the removal.
    let list: [AudiobookBookmark]
    /// "Removed 1 bookmark at 12:34" — always shown.
    var notice: String { "Removed 1 bookmark at \(AudiobookTime.clock(removed.position))" }
}

extension BookmarkStore {
    /// The one bookmark in `candidates` nearest `position`; an exact tie goes to the
    /// EARLIER one. Nil when `candidates` is empty.
    static func nearest(to position: TimeInterval, in candidates: [AudiobookBookmark]) -> AudiobookBookmark? {
        candidates.min { a, b in
            let da = abs(a.position - position), db = abs(b.position - position)
            return da != db ? da < db : a.position < b.position
        }
    }

    /// Remove exactly the one bookmark nearest `position` among `candidates` (default:
    /// every bookmark of the book). Nil when there is nothing to remove.
    @discardableResult
    func removeNearest(to position: TimeInterval, among candidates: [AudiobookBookmark]? = nil,
                       bookID: UUID) -> BookmarkRemoval? {
        guard let target = Self.nearest(to: position, in: candidates ?? load(bookID: bookID)) else { return nil }
        return removeOne(id: target.id, bookID: bookID)
    }

    /// Remove the single bookmark `id` (the swipe path: the row IS the target).
    @discardableResult
    func removeOne(id: UUID, bookID: UUID) -> BookmarkRemoval? {
        guard let target = load(bookID: bookID).first(where: { $0.id == id }) else { return nil }
        let list = remove(id: id, bookID: bookID)
        return BookmarkRemoval(removed: target, list: list)
    }

    /// Undo a removal: put the bookmark back (no near-duplicate guard — it sat there a
    /// moment ago) and stamp the LWW clock. Returns the new sorted list.
    @discardableResult
    func restore(_ removal: BookmarkRemoval, bookID: UUID) -> [AudiobookBookmark] {
        var list = load(bookID: bookID)
        guard !list.contains(where: { $0.id == removal.removed.id }) else { return list }
        list.append(removal.removed)
        list.sort { $0.position < $1.position }
        try? save(list, bookID: bookID)
        markEdited(bookID: bookID)
        return list
    }
}
