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

    /// The ONE predicate (`ExportGate`, Q156): the first gate this memo fails right now, nil
    /// when it may publish. The folder IS the consent, per destination: a note bound for the
    /// portfolio needs the PORTFOLIO folder picked here, one bound for the vault needs the vault.
    ///
    /// Locked notes stay inside Skrift (the vault is plaintext .md on disk; locking never
    /// deletes an already-published file, the lock flow tells the user it's still there).
    /// Rated-only unless the (test-only) `.all` policy says otherwise.
    ///
    /// PROCESSED ONLY (Tuur, 2026-08-11): "only the iPad and the Mac can do that AFTER they
    /// processed the note." A vault note is a polished note — the raw ramble stays inside
    /// Skrift. `isProcessed`, NOT `hasContent` (2026-08-26): the question is whether a pass
    /// RAN, not whether it produced words. A note the model had nothing to say about was
    /// stranded here forever — refused with "Process this note first", and pressing Process
    /// did the identical nothing. The Mac never had this bug: its own button reads a step flag
    /// that `BatchRunner` sets `.done` on empty input.
    ///
    /// The Mac's two-versions hold (`EditConflictHold`) is deliberately NOT asked here: it is
    /// Mac-only (D139 does not require it on the iPad) — see the `ExportGate` table.
    func gateFailure(_ memo: Memo) -> ExportGate.Failure? {
        var facts = ExportGate.Facts(
            memo: memo,
            folderConfigured: memo.destination.isPortfolio ? portfolioConfigured() : obsidianEnabled(),
            processed: enhancementProvider(memo.id)?.isProcessed == true)
        if policy() == .all { facts.rated = true }
        return ExportGate.check(facts, device: .ipad)
    }

    /// Whether this memo should publish to Obsidian right now.
    func shouldPublish(_ memo: Memo) -> Bool {
        if isMacPaired() && !publishWhenPaired() { return false }   // Mac owns export when paired
        return gateFailure(memo) == nil
    }

    /// Why `shouldPublish` would refuse this memo right now, in the user's words — nil
    /// when it would publish. The predicate is `gateFailure` (`ExportGate`, shared with the
    /// Mac) and the words are `ExportOutcomeCopy.refusal`, so neither can drift. Exists because the
    /// iPad's chrome Export button ran the gate SILENTLY (Tuur, 2026-08-18: "i clicked
    /// the export to obsidian button on ipad. nothing happened" — no vault was configured
    /// on that device, and nothing said so).
    func exportRefusal(_ memo: Memo) -> String? {
        if isMacPaired() && !publishWhenPaired() { return "The Mac owns Obsidian export while paired." }
        return gateFailure(memo).map { ExportOutcomeCopy.refusal($0, device: .ipad).text }
    }

    /// Publish one memo if eligible; nil when the gate excludes it.
    @discardableResult
    func publishIfEligible(_ memo: Memo) throws -> PublishOutcome? {
        guard shouldPublish(memo) else { return nil }
        return try publisher.publish(memo)
    }

    /// `publishIfEligible`, with the file and photo count the outcome line quotes.
    func publishReportIfEligible(_ memo: Memo) throws -> PublishReport? {
        guard shouldPublish(memo) else { return nil }
        return try publisher.publishReport(memo)
    }

    /// The Process / Export / Re-export inputs for one note — the SAME derivation the Mac
    /// runs (`NoteWorkState.Inputs`): the synced enhancement's `isProcessed` and the export
    /// ledger of the folder this note's destination writes to.
    static func workInputs(for memo: Memo, enhancement: MemoEnhancement?) -> NoteWorkState.Inputs {
        .from(memo: memo, enhancement: enhancement, ledger: ledger(for: memo))
    }

    /// Has this note ever been written to the vault? Read from the export LEDGER, which is
    /// keyed on the picked folder — the same record the writer consults, so the button can
    /// never claim something the engine would contradict. False when no vault is configured
    /// (nothing can have been exported yet).
    static func hasPublished(_ memo: Memo) -> Bool {
        ledger(for: memo)?.entry(for: memo.id) != nil
    }

    /// The export ledger of the folder this note would be written to; nil when no vault /
    /// portfolio folder is configured. Per DESTINATION: the ledger is keyed on the folder
    /// written to, so "has this been exported" is asked of the folder the note would go to.
    static func ledger(for memo: Memo) -> ExportLedger? {
        let profile = ExportProfile.of(memo.destination)
        guard let root = memo.destination.isPortfolio
                ? PortfolioVault.folder(for: memo.destination)
                : ObsidianVault.resolveVault() else { return nil }
        let scopeRoot = memo.destination.isPortfolio ? (PortfolioVault.resolveRoot() ?? root) : root
        let needsStop = scopeRoot.startAccessingSecurityScopedResource()
        defer { if needsStop { scopeRoot.stopAccessingSecurityScopedResource() } }
        return ExportLedger.default(for: VaultLayout.home(forPicked: root, profile: profile))
    }
}
