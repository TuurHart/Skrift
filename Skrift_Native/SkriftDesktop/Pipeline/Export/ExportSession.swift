import Foundation

/// One export RUN on the Mac (Q365, D186; plan/perf2/g-mac-pipeline.md G8): "Export N to
/// Obsidian", a sync's re-export sweep. It decodes each destination's export ledger ONCE and
/// snapshots the names roster ONCE, where the per-note path decoded both for every note and
/// rewrote the whole ledger after every write.
///
/// Crash-safe: while the run is open, each note's ledger change is appended to the ledger's
/// journal the moment it happens (`ExportLedger.beginDeferring`), so a run that dies keeps every
/// entry it wrote. `finish()` folds the journal into one full ledger write. Always call it
/// (`defer { session.finish() }`); a missed call costs only the compaction, never an entry.
final class ExportSession: @unchecked Sendable {
    private let lock = NSLock()
    private var ledgers: [String: ExportLedger] = [:]
    private var peopleSnapshot: [Person]?

    /// `people` = the roster to compile against; nil reads `NamesStore` once, on first use.
    init(people: [Person]? = nil) {
        peopleSnapshot = people
    }

    /// This run's ledger for the export home `root` — decoded on first ask, then shared.
    func ledger(for root: URL) -> ExportLedger {
        let key = root.standardizedFileURL.path
        lock.lock(); defer { lock.unlock() }
        if let known = ledgers[key] { return known }
        let ledger = ExportLedger.default(for: root)
        ledger.beginDeferring()
        ledgers[key] = ledger
        return ledger
    }

    /// This run's ledger for `root` if the run already opened it, else nil (nothing decoded).
    func ledgerIfOpen(for root: URL) -> ExportLedger? {
        lock.lock(); defer { lock.unlock() }
        return ledgers[root.standardizedFileURL.path]
    }

    /// The live roster, read from names.json once per run.
    var people: [Person] {
        lock.lock(); defer { lock.unlock() }
        if let peopleSnapshot { return peopleSnapshot }
        let live = NamesStore.shared.livePeople()
        peopleSnapshot = live
        return live
    }

    /// End the run: one full write per ledger this run touched.
    func finish() {
        lock.lock()
        let all = Array(ledgers.values)
        ledgers = [:]
        lock.unlock()
        for ledger in all { ledger.compact() }
    }
}
