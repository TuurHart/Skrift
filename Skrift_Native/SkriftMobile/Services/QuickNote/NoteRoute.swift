import Foundation

/// A navigable note screen: either a fresh, not-yet-created quick-note draft
/// (C112/C114/C43) or a real, already-persisted memo (Q47/BUGS §3).
///
/// The kind travels INLINE on the pushed/selected value itself — it used to
/// be a bare `UUID` (`path` / `selectedMemoID`) cross-referenced against a
/// SEPARATE, independently-settable `quickNoteDraftID` state var to decide
/// which screen to route to. Two pieces of state that must agree can desync
/// for one race window; a `NoteRoute` carries its own answer, so there is
/// nothing left to desync FROM. (Build 172: the first ✎ tap after a
/// mid-take-crash relaunch opened the launch-recovered "Recovered
/// recording…" note instead of a new draft; a second tap worked.)
enum NoteRoute: Hashable, Identifiable {
    case draft(UUID)
    case memo(UUID)

    var id: UUID {
        switch self {
        case .draft(let id), .memo(let id): return id
        }
    }

    var isDraft: Bool {
        if case .draft = self { return true }
        return false
    }

    /// Mint a route for a brand-new quick note (✎ / widget / Siri / Control
    /// Center). Always a fresh `UUID` — nothing in the store can ever hold
    /// it, so it can never collide with, or be mistaken for, an existing
    /// memo's id, including one the launch recovery sweep created moments
    /// earlier.
    static func newDraft() -> NoteRoute { .draft(UUID()) }

    /// Route to an existing, already-persisted memo (row tap, saved
    /// recording, deep link, reminder, search jump).
    static func existing(_ id: UUID) -> NoteRoute { .memo(id) }
}
