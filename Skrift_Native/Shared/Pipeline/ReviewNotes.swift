import Foundation

/// The ONE note set every Review surface reads (Q166, recsj-100/-101/-113): the river,
/// the calendar, the map, the places rail and Then vs Now all take `live(...)` — one row
/// per id (`MemoDuplicates.canonicalRows`), trashed and fading notes out
/// (`MemoLifecycle.partition`). Fading notes have exactly one surface, the conveyor
/// (C212), so a calendar dot or a map pin must never count one.
enum ReviewNotes {

    /// The rows split once: (every Review surface, the Fading conveyor).
    static func split(_ rows: [Memo], now: Date = Date()) -> (live: [Memo], fading: [Memo]) {
        MemoLifecycle.partition(MemoDuplicates.canonicalRows(rows), now: now)
    }

    /// The note set the Review surfaces show.
    static func live(_ rows: [Memo], now: Date = Date()) -> [Memo] {
        split(rows, now: now).live
    }

    // MARK: - the map's pinned place (C233: an owned camera, dive-down only)

    /// One `onMapCameraChange(.onEnd)` event. A camera move the app made itself (a dive or a
    /// place-row focus sets `programmaticMove` just before it animates) keeps the pinned
    /// place and consumes the flag; any other end is the user's own pan or zoom and returns
    /// the list to "In view" (the phone's b89 rule, now both apps).
    static func cameraEnded(programmaticMove: Bool) -> (clearPinnedPlace: Bool, programmaticMove: Bool) {
        (clearPinnedPlace: !programmaticMove, programmaticMove: false)
    }

    /// The count a list heading shows — always the count of the rows it renders.
    static func noteCount(_ n: Int) -> String {
        "\(n) note\(n == 1 ? "" : "s")"
    }
}
