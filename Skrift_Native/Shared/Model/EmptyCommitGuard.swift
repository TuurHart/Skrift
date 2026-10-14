import Foundation

/// An editor commit that would turn a non-empty body into nothing (C261 / R70), on every editor
/// in both apps: the phone and iPad `NoteBodyView` commit, the Mac `BodyTextView` end-of-session
/// commit, for the RAW transcript and for the Mac's POLISHED copy-edit. Such a commit never lands
/// silently: the view asks first (same destructive-confirm shape as `NameDeleteConfirm`), and
/// Cancel keeps the prior text.
///
/// The "nets to empty" decision is `netsToEmpty`, the only copy. Pure state, no UI: a view calls
/// `request` with the text it is about to replace, shows its own dialog while `isPending`, and
/// only `confirm()` hands back the (empty) text to write. `cancel()` hands back the prior text to
/// put back on screen.
struct EmptyCommitGuard: Equatable {
    /// Which stored body the commit targets (the dialog names it).
    enum Field: Equatable {
        case raw        // the transcript / note body
        case polished   // the Mac's copy-edit
    }

    struct Pending: Equatable {
        let field: Field
        let prior: String
        let proposed: String
    }

    private(set) var pending: Pending?

    var isPending: Bool { pending != nil }

    /// True when committing `proposed` over `prior` wipes a body that had words in it. Blank
    /// means whitespace only. An already-empty prior never asks, and a body that keeps a photo
    /// marker (`[[img_001]]`) is not empty.
    static func netsToEmpty(prior: String?, proposed: String) -> Bool {
        isBlank(proposed) && !isBlank(prior ?? "")
    }

    private static func isBlank(_ s: String) -> Bool {
        s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// A commit is about to replace `prior` with `proposed`. Returns true when the write may
    /// proceed now; false when it nets to empty (parked, pending a confirm).
    mutating func request(_ field: Field, prior: String?, proposed: String) -> Bool {
        guard Self.netsToEmpty(prior: prior, proposed: proposed) else { return true }
        pending = Pending(field: field, prior: prior ?? "", proposed: proposed)
        return false
    }

    /// The user said "Clear": the parked commit to write (once), clears the dialog.
    mutating func confirm() -> Pending? {
        defer { pending = nil }
        return pending
    }

    /// The user cancelled or dismissed: the parked commit, whose `prior` goes back on screen.
    mutating func cancel() -> Pending? {
        defer { pending = nil }
        return pending
    }

    static func title(for field: Field) -> String {
        switch field {
        case .raw: return "Clear this note?"
        case .polished: return "Clear the polished text?"
        }
    }

    static func message(for field: Field) -> String {
        switch field {
        case .raw: return "This removes all of the text. Cancel keeps what was there."
        case .polished: return "This clears the polished text on every device. Cancel keeps what was there."
        }
    }

    static let confirmLabel = "Clear text"
    static let cancelLabel = "Keep text"
}
