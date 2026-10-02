import Foundation

/// WHO MAY EXPORT A NOTE — one predicate for both apps (Q156, C61, C194).
///
/// It was asked twice with different answers: the iPad's `PublishCoordinator.shouldPublish`
/// checked folder, trash, lock, rating, content and processing; the Mac's
/// `VaultExporter.export` checked lock, the two-versions hold and the folder only, and left
/// rating / trash / processing to its callers (`reexportEdited` checked locked + trashed but
/// not rated). Each side also worded the refusals itself (`ExportOutcomeCopy.refusal` owns
/// them now).
///
/// `check` returns the FIRST failing gate, in this order:
///
/// | # | Failure             | iPad | Mac | Notes |
/// |---|---------------------|------|-----|-------|
/// | 1 | `noPortfolioFolder` | yes  | yes | portfolio-bound note, no portfolio root picked on this device |
/// | 1 | `noVaultFolder`     | yes  | yes | vault-bound note, no vault folder picked on this device |
/// | 2 | `trashed`           | yes  | yes | |
/// | 3 | `locked`            | yes  | yes | the vault is plain text |
/// | 4 | `twoVersions`       | no   | yes | DEVICE DIFFERENCE: the hold is Mac-only (`EditConflictHold`, mock Q4); D139 does not require it on the iPad, so the iPad exports a note the Mac would hold |
/// | 5 | `unrated`           | yes  | yes | rating is consent (`NoteConsent`) |
/// | 6 | `nothingToExport`   | yes  | yes | no body and no title |
/// | 7 | `unprocessed`       | yes  | yes | a vault note is a polished note |
enum ExportGate {

    enum Device: Equatable { case ipad, mac }

    enum Failure: Equatable, CaseIterable {
        case noPortfolioFolder, noVaultFolder, trashed, locked, twoVersions
        case unrated, nothingToExport, unprocessed
    }

    /// What the gate needs to know, derived by each app from its own row type
    /// (`Memo` on the phone, `PipelineFile` on the Mac). Defaults are the "all clear" values.
    struct Facts: Equatable {
        var destinationIsPortfolio = false
        /// A folder is picked on THIS device for the note's destination (portfolio root or vault).
        var folderConfigured = true
        var trashed = false
        var locked = false
        /// The note has two versions and the Mac is holding it (Mac-only input; ignored on iPad).
        var twoVersionsHeld = false
        var rated = true
        /// The note has a body or a title worth a file.
        var hasContent = true
        /// Polished by any device (`NoteWorkState.Inputs.hasPolish`).
        var processed = true

        init(destinationIsPortfolio: Bool = false, folderConfigured: Bool = true,
             trashed: Bool = false, locked: Bool = false, twoVersionsHeld: Bool = false,
             rated: Bool = true, hasContent: Bool = true, processed: Bool = true) {
            self.destinationIsPortfolio = destinationIsPortfolio
            self.folderConfigured = folderConfigured
            self.trashed = trashed
            self.locked = locked
            self.twoVersionsHeld = twoVersionsHeld
            self.rated = rated
            self.hasContent = hasContent
            self.processed = processed
        }

        /// The memo channel (the phone, and the Mac for a cloud `Memo`).
        init(memo: Memo, folderConfigured: Bool, processed: Bool, twoVersionsHeld: Bool = false) {
            let hasBody = !(memo.transcript ?? "").isEmpty || !(memo.annotationText ?? "").isEmpty
            self.init(destinationIsPortfolio: memo.destination.isPortfolio,
                      folderConfigured: folderConfigured,
                      trashed: memo.deletedAt != nil,
                      locked: memo.locked,
                      twoVersionsHeld: twoVersionsHeld,
                      rated: NoteConsent.isRated(memo),
                      hasContent: hasBody || (memo.title?.isEmpty == false),
                      processed: processed)
        }
    }

    /// Which gates to ask. `engine` is what the Mac's write path itself enforces (it is also
    /// reached by the headless harness and tests with bare rows): folder, lock, hold. `full`
    /// is what a person's Export press, and a re-export after a sync, must pass.
    enum Scope: Equatable { case full, engine }

    /// The first failing gate, nil when the note may export.
    static func check(_ facts: Facts, device: Device, scope: Scope = .full) -> Failure? {
        if !facts.folderConfigured {
            return facts.destinationIsPortfolio ? .noPortfolioFolder : .noVaultFolder
        }
        if scope == .full, facts.trashed { return .trashed }
        if facts.locked { return .locked }
        if device == .mac, facts.twoVersionsHeld { return .twoVersions }
        guard scope == .full else { return nil }
        if !facts.rated { return .unrated }
        if !facts.hasContent { return .nothingToExport }
        if !facts.processed { return .unprocessed }
        return nil
    }

    /// The memo-channel form: `ExportGate.check(note, device)`.
    static func check(memo: Memo, device: Device, folderConfigured: Bool, processed: Bool,
                      twoVersionsHeld: Bool = false, scope: Scope = .full) -> Failure? {
        check(Facts(memo: memo, folderConfigured: folderConfigured, processed: processed,
                    twoVersionsHeld: twoVersionsHeld), device: device, scope: scope)
    }
}
