import Foundation

/// Fans the memo store out to the Obsidian sink (standalone Phase 2). Decides WHICH memos
/// publish; the actual write is `ObsidianPublisher`.
///
/// Routing rules:
/// - **Opt-in:** nothing publishes until a vault folder is picked. The folder IS the
///   consent (Tuur, 2026-08-18 — the on/off toggle died with the Settings "Export now"
///   button: every export on iOS is a deliberate tap in the app, nothing auto-publishes,
///   so a switch was a third consent stacked on two).
/// - **Processed only:** a vault note is a POLISHED note. A memo with no enhancement has
///   nothing to export — which is why the export controls only appear on a device that
///   can process (`PolishCenter.isAvailable`; see `ObsidianSettingsSection`).
/// - **Policy:** `.all` or `.importantOnly` (significance > 0 — mirrors the Mac flag-to-send).
/// - **Paired mode:** `isMacPaired` lets a deployment defer Obsidian export to a Mac that owns
///   the *enhanced* text. There's no LAN pairing under CloudKit-only, so the live wiring reports
///   unpaired (the phone publishes per policy); per-memo file ownership + content-hash idempotency
///   (in `ObsidianPublisher`) make a stray double-write harmless anyway.
@MainActor
struct PublishCoordinator {
    enum Policy: String { case all, importantOnly }

    var memosProvider: () -> [Memo]
    var publisher: ObsidianPublisher
    var isMacPaired: () -> Bool
    var obsidianEnabled: () -> Bool
    /// Is a PORTFOLIO root configured on this device? A note bound for the portfolio needs that
    /// folder, not the vault — and the two are separate picks, so a device can legitimately
    /// have one and not the other.
    var portfolioConfigured: () -> Bool = { false }
    var publishWhenPaired: () -> Bool
    var policy: () -> Policy
    /// The device's polish for a memo, if it has one. A vault note is a PROCESSED note
    /// (see `shouldPublish`), so this is what decides whether there's anything to send.
    var enhancementProvider: (UUID) -> MemoEnhancement? = { _ in nil }

    struct Summary: Equatable {
        var written = 0
        var skipped = 0
        var failed = 0
        var ineligible = 0
        /// Files the user edited in their vault → Skrift backed off, did not overwrite.
        var protected = 0
        /// Notes filed OUT of the picked folder → left where the user put them.
        var filedAway = 0
        /// Refused targets (legacy pre-stamp export / foreign file) → untouched.
        var blocked = 0
    }

    /// Production coordinator over the live store, settings, and pairing state.
    static func live(author: String) -> PublishCoordinator {
        PublishCoordinator(
            memosProvider: { NotesRepository.shared.allMemos() },
            publisher: .live(author: author),
            isMacPaired: { false },   // no LAN pairing under CloudKit-only; the phone publishes per policy
            // The picked folder IS the consent — no separate on/off (2026-08-18; the
            // old `skrift.publish.obsidianEnabled` key is dead and deliberately unread,
            // so devices that had it false don't stay silently off).
            obsidianEnabled: { ObsidianVault.isConfigured },
            portfolioConfigured: { PortfolioVault.isConfigured },
            publishWhenPaired: { UserDefaults.standard.bool(forKey: "skrift.publish.whenPaired") },
            // RATED-ONLY, always — not a setting (Tuur, 2026-07-26: unrated notes
            // "cant export either"). Deliberately hard-coded rather than read from
            // the old `skrift.publish.policy` key: a device that had stored "all"
            // would otherwise keep publishing unrated notes after the option was
            // removed from Settings. `.all` survives only for the gate's tests.
            policy: { .importantOnly },
            enhancementProvider: { NotesRepository.shared.enhancement(forMemo: $0) }
        )
    }

    /// Whether this memo should publish to Obsidian right now.
    func shouldPublish(_ memo: Memo) -> Bool {
        // The folder IS the consent, per destination: a note bound for the portfolio needs the
        // PORTFOLIO folder picked here, and one bound for the vault needs the vault.
        guard memo.destination.isPortfolio ? portfolioConfigured() : obsidianEnabled() else { return false }
        guard memo.deletedAt == nil else { return false }
        // Locked notes stay inside Skrift — the vault is plaintext .md on disk.
        // (Locking never deletes an already-published file; the lock flow tells
        // the user it's still in the vault.)
        guard !memo.locked else { return false }
        if isMacPaired() && !publishWhenPaired() { return false }   // Mac owns export when paired
        if policy() == .importantOnly && !NoteConsent.isRated(memo) { return false }
        // Needs some content to be worth a file.
        let hasBody = !(memo.transcript ?? "").isEmpty || !(memo.annotationText ?? "").isEmpty
        guard hasBody || (memo.title?.isEmpty == false) else { return false }
        // PROCESSED ONLY (Tuur, 2026-08-11): "only the iPad and the Mac can do that
        // AFTER they processed the note." A vault note is a polished note — the raw
        // ramble stays inside Skrift. This is also what the Mac has always done: its
        // primary button reads "Process" until the enhancement exists and only then
        // becomes "Export to Obsidian", so requiring it here makes the two agree.
        //
        // `isProcessed`, NOT `hasContent` (2026-08-26): the question is whether a pass
        // RAN, not whether it produced words. A note the model had nothing to say about
        // was stranded here forever — refused with "Process this note first", and
        // pressing Process did the identical nothing. The Mac never had this bug: its
        // own button reads a step flag that `BatchRunner` sets `.done` on empty input.
        return enhancementProvider(memo.id)?.isProcessed == true
    }

    /// Why `shouldPublish` would refuse this memo right now, in the user's words — nil
    /// when it would publish. Lives BESIDE the gate so the two lists can't drift: every
    /// guard in `shouldPublish` has one line here, in the same order. Exists because the
    /// iPad's chrome Export button ran the gate SILENTLY (Tuur, 2026-08-18: "i clicked
    /// the export to obsidian button on ipad. nothing happened" — no vault was configured
    /// on that device, and nothing said so).
    func exportRefusal(_ memo: Memo) -> String? {
        if memo.destination.isPortfolio, !portfolioConfigured() {
            return "No portfolio folder is set on this device yet. Pick one in Settings → Destinations."
        }
        if !memo.destination.isPortfolio, !obsidianEnabled() {
            return "No vault folder is set on this device yet. Pick one in Settings → Obsidian."
        }
        if memo.deletedAt != nil { return "This note is in Recently Deleted." }
        if memo.locked { return "Locked notes stay inside Skrift — the vault is plain text on disk." }
        if isMacPaired() && !publishWhenPaired() { return "The Mac owns Obsidian export while paired." }
        if policy() == .importantOnly && !NoteConsent.isRated(memo) {
            return "Rate this note first — unrated notes never leave Skrift."
        }
        let hasBody = !(memo.transcript ?? "").isEmpty || !(memo.annotationText ?? "").isEmpty
        if !(hasBody || (memo.title?.isEmpty == false)) { return "There's nothing to export yet." }
        if enhancementProvider(memo.id)?.isProcessed != true {
            return "Process this note first — the vault gets the polished note, not the raw one."
        }
        return nil
    }

    /// Publish one memo if eligible; nil when the gate excludes it.
    @discardableResult
    func publishIfEligible(_ memo: Memo) throws -> PublishOutcome? {
        guard shouldPublish(memo) else { return nil }
        return try publisher.publish(memo)
    }

    /// Has this note ever been written to the vault? Read from the export LEDGER, which is
    /// keyed on the picked folder — the same record the writer consults, so the button can
    /// never claim something the engine would contradict. False when no vault is configured
    /// (nothing can have been exported yet).
    static func hasPublished(_ memo: Memo) -> Bool {
        // Per DESTINATION: the ledger is keyed on the folder written to, so "has this been
        // exported" is asked of the folder this note would actually go to.
        let profile = ExportProfile.of(memo.destination)
        guard let root = memo.destination.isPortfolio
                ? PortfolioVault.folder(for: memo.destination)
                : ObsidianVault.resolveVault() else { return false }
        let scopeRoot = memo.destination.isPortfolio ? (PortfolioVault.resolveRoot() ?? root) : root
        let needsStop = scopeRoot.startAccessingSecurityScopedResource()
        defer { if needsStop { scopeRoot.stopAccessingSecurityScopedResource() } }
        return ExportLedger.default(for: VaultLayout.home(forPicked: root, profile: profile))
            .entry(for: memo.id) != nil
    }

    /// Publish every eligible memo, tallying the outcomes.
    @discardableResult
    func publishAll() -> Summary {
        var s = Summary()
        for memo in memosProvider() {
            guard shouldPublish(memo) else { s.ineligible += 1; continue }
            do {
                switch try publisher.publish(memo) {
                case .written:          s.written += 1
                case .skippedUnchanged: s.skipped += 1
                case .userEdited:       s.protected += 1   // user edited it in the vault → left alone
                case .movedAway:        s.filedAway += 1   // filed out of the inbox → left there
                case .blocked:          s.blocked += 1     // legacy/foreign at the target → untouched
                case .noVault:          s.failed += 1      // enabled but the bookmark didn't resolve
                }
            } catch {
                s.failed += 1
            }
        }
        return s
    }
}
