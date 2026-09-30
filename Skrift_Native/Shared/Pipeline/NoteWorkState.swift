import Foundation

/// What a note's primary button should OFFER — one rule for every app.
///
/// It was three rules before 2026-08-14, and they disagreed: the Mac read
/// `steps.enhance == .done` (a flag only the Mac itself ever sets, so a note the iPad
/// polished still offered "Process" and would redo the work), the iPad's inline button
/// hid itself when an enhancement existed, and the iPad's ⋯ menu offered "Process" on a
/// note it had just polished. Same note, three answers, two of them wrong.
///
/// The rule is Tuur's, and it is the same one `ProcessPile` already keys on:
/// *"if there is a Mac enhancement, I should be able to export it on the iPad — the
/// enhancement has been done."* **Processed is processed, whichever device ran it.** Local
/// step bookkeeping is not a fact about the note; the polished content is.
enum NoteWorkState: Equatable {
    /// No polish yet — the model hasn't run, or ran and wrote nothing.
    case needsProcessing
    /// Polished, never written to the vault.
    case readyToExport
    /// Polished and exported. Offering it again is legitimate (re-export after an edit),
    /// which is why this is a state and not simply "finished".
    case exported

    /// - Parameters:
    ///   - hasPolish: the note carries polished content. Callers must require ALL THREE
    ///     parts (title + copy-edit + summary), never just one: a note's polished TITLE is
    ///     also written from the user's own chosen title, so "any part present" would call a
    ///     merely-retitled note processed.
    ///   - isExported: this note has been written to the vault at least once.
    static func of(hasPolish: Bool, isExported: Bool) -> NoteWorkState {
        guard hasPolish else { return .needsProcessing }
        return isExported ? .exported : .readyToExport
    }

    /// The button's words. Shared so the two apps cannot drift into saying different things
    /// about the same note — the whole reason this type exists.
    ///
    /// The verb names WHERE the note is going (Tuur, 2026-08-27: *"if I set it to Inspiration
    /// it should not say export to Obsidian at the top right"*). A button that promises the
    /// wrong destination is the same class of wrong as one that promises what it can't do.
    func label(for destination: NoteDestination = .personal) -> String {
        switch self {
        case .needsProcessing: SharedCopy.processVerb
        case .readyToExport: destination.isPortfolio ? "Export to portfolio" : "Export to Obsidian"
        case .exported: "Re-export"
        }
    }

    /// True while the note still owes the model a pass — the only state in which running
    /// the polisher is the obvious next move rather than a deliberate re-run.
    var wantsProcessing: Bool { self == .needsProcessing }
}
