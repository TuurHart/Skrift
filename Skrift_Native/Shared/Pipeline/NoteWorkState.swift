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

// MARK: - The one input

extension NoteWorkState {
    /// The two facts `NoteWorkState.of` needs, derived ONCE for every app (Q117, C194).
    ///
    /// The label table was shared and the inputs were not: the iPad asked
    /// `MemoEnhancement.isProcessed` + the per-folder export ledger, the Mac asked its own
    /// step flags (`steps.enhance == .done || all three parts`, `steps.export == .done`).
    /// A pass that produced nothing read as processed on one device and not the other, and a
    /// note exported to a since-changed vault folder read as "Re-export" on the Mac only.
    /// Both apps now come through here.
    struct Inputs: Equatable {
        let hasPolish: Bool
        let isExported: Bool

        var state: NoteWorkState { .of(hasPolish: hasPolish, isExported: isExported) }

        /// A Mac row's OWN polish facts, for a note whose synced `MemoEnhancement` is not in
        /// the CloudKit store (sync off, a local-only import, or the write-back still queued).
        /// Same rule as `MemoEnhancement.isProcessed`: a pass ran, or all three parts exist.
        struct LocalPolish: Equatable {
            var passRan = false
            var copyedit: String? = nil
            var title: String? = nil
            var summary: String? = nil

            var isProcessed: Bool {
                passRan || MemoEnhancement.isProcessed(
                    processedAt: nil, copyedit: copyedit ?? "", title: title ?? "", summary: summary ?? "")
            }
        }

        /// - Parameters:
        ///   - enhancement: the memo's synced `MemoEnhancement`, if any.
        ///   - ledger: the export ledger of the folder this note would be written to (the
        ///     note's destination's folder); nil when none is configured.
        static func from(memo: Memo, enhancement: MemoEnhancement?, ledger: ExportLedger?) -> Inputs {
            from(ledgerID: memo.id, enhancement: enhancement, ledger: ledger)
        }

        /// The same rule for a caller that has no `Memo` in hand (a Mac-only row) or whose
        /// ledger key is not the memo's id (the Mac keys it on the row id). `local` is OR-ed
        /// in so a polish this device just ran is never forgotten before it syncs.
        static func from(ledgerID: UUID, enhancement: MemoEnhancement?, ledger: ExportLedger?,
                         local: LocalPolish? = nil) -> Inputs {
            let processed = enhancement?.isProcessed == true || local?.isProcessed == true
            return Inputs(hasPolish: processed,
                          isExported: ledger?.entry(for: ledgerID) != nil)
        }
    }
}
