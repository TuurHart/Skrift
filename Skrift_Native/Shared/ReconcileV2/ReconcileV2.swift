import Foundation
import SwiftData

/// Reconcile v2 (rewrite target 3, Q429): the Mac's sweep of the synced `Memo` store into its
/// local `PipelineFile` rows, beside v1 (`MemoCloudReconciler`, C2). The app still calls v1; the
/// Q428 harness (`ReconcileDiffHarnessTests`) runs this over the corpus and diffs every row
/// against v1's golden. Mac-only: it builds `PipelineFile` rows, so only the desktop targets
/// compile this folder.
///
/// One sweep, synchronous, on the main actor (C294, the Q492/Q505/Q507 lesson): there is no
/// `await` anywhere in it, so no query can observe a row half-written, and every SwiftData row is
/// touched on its context's thread. It reads each store once, decides every memo, writes, and
/// saves once.
///
/// Per memo (C41-C48):
/// - its row is found by memo id, else by audio filename unless another memo owns that row (C188);
/// - an existing row takes the phone's changes field by field (`Reflect`, C47) and heals late
///   assets (`Heal`, C45);
/// - a never-seen memo that is live and rated becomes a row (`Ingest`, C43/C44); a never-rated or
///   trashed one never does (C41, C187);
/// - same-id clones collapse to one keeper first (`MemoDuplicates`, C48).
@MainActor
enum ReconcileV2 {

    /// What one sweep did.
    struct Outcome: Equatable {
        var created = 0
        /// Rows a phone change or a heal rewrote — the re-export candidates (C189).
        var updatedIDs: [String] = []
        var ingestFailures = 0
        /// Rated, live memos left without a row (must stay 0, C41).
        var stranded = 0
        /// Existing rows seen with a memo for the first time (their watermark was baselined).
        var newlyLinked = 0
        /// Never-seen memos left for the background ingest (`deferNew`), by id.
        var pendingNewIDs: [UUID] = []
        /// Rows whose watermark moved to a phone polish they had already (R44); saved, not re-exported.
        var watermarked = 0
        /// R40 / C52: the store could not be read, so nothing was pulled. Never an empty list.
        var fetchFailure: String?
    }

    /// Everything one sweep reads, fetched once.
    struct Inputs {
        let memos: [Memo]            // the keeper per id
        let allMemos: [Memo]         // clones included
        let enhancements: [UUID: MemoEnhancement]
        let rows: [PipelineFile]
    }

    /// The fixed context of a sweep: who is sweeping, for whom, and where rows' folders live.
    struct Context {
        var people: [Person] = []
        var author = ""
        var thisDeviceID = ""
        var now = Date()
        /// The root every working folder is written under (`<id>_<file>`, `<id>_note`, `capture_<id>`).
        var outputDir: URL
        /// Memos whose background ingest is running: not ingested again, not orphans.
        var inFlight: Set<UUID> = []
    }

    /// What the pass around the sweep reuses from it, so nothing is fetched twice.
    struct Snapshot {
        var memos: [Memo] = []
        /// Every memo row read, clones included (the lifecycle sweep reuses it).
        var allMemos: [Memo] = []
        var enhancements: [MemoEnhancement] = []
        var rows: [PipelineFile] = []
        /// Row ids that have a memo right now (matched, or made this sweep).
        var rowsWithMemo: Set<String> = []
    }

    // MARK: - the sweep

    /// Sweep `cloud` into `local`. `fetchMemos` exists only so a test can make the read fail (R40).
    @discardableResult
    static func sweep(cloud: ModelContext, local: ModelContext, context ctx: Context,
                      fetchMemos: (ModelContext) throws -> [Memo] = { try $0.fetch(FetchDescriptor<Memo>()) })
        -> Outcome {
        run(cloud: cloud, local: local, context: ctx, deferNew: false, fetchMemos: fetchMemos).outcome
    }

    /// The sweep, and what it read. `deferNew`: never-seen memos are NOT ingested here; their ids
    /// come back in `pendingNewIDs` for the app's background ingest (`Ingest.prepare` off the main
    /// actor, then `Ingest.commit` on it), so a first enable with a big backlog never writes
    /// hundreds of folders on the main thread.
    static func run(cloud: ModelContext, local: ModelContext, context ctx: Context, deferNew: Bool,
                    fetchMemos: (ModelContext) throws -> [Memo]) -> (outcome: Outcome, snapshot: Snapshot) {
        let inputs: Inputs
        switch read(cloud: cloud, local: local, fetchMemos: fetchMemos) {
        case .failure(let message):
            AppLog.cloudkit.error("reconcile v2: store read failed, nothing pulled: \(message, privacy: .public)")
            return (Outcome(fetchFailure: message), Snapshot())
        case .success(let read): inputs = read
        }
        var snapshot = Snapshot(memos: inputs.memos, allMemos: inputs.allMemos,
                                enhancements: Array(inputs.enhancements.values), rows: inputs.rows)

        var outcome = Outcome()
        let held = EditConflictHold.refresh(memos: inputs.memos, in: cloud,
                                            thisDevice: ctx.thisDeviceID.isEmpty ? DeviceID.current() : ctx.thisDeviceID)
        let assets = AssetIndex(cloud)
        let matcher = RowMatcher(rows: inputs.rows, memos: inputs.memos)
        var fresh: [Memo] = []

        for memo in inputs.memos {
            let enhancement = inputs.enhancements[memo.id]
            guard let row = matcher.row(for: memo) else {
                if memo.deletedAt == nil, NoteConsent.isRated(memo), !ctx.inFlight.contains(memo.id) { fresh.append(memo) }
                continue
            }
            snapshot.rowsWithMemo.insert(row.id)
            let reflected = held.contains(row.id) ? Reflect.Result()
                : Reflect.apply(memo: memo, enhancement: enhancement, to: row, context: ctx)
            let healed = memo.deletedAt == nil
                && Heal.run(memo: memo, row: row, assets: assets, transcriptChanged: reflected.transcriptChanged)
            if row.syncedSourceEditedAt == nil {
                row.syncedSourceEditedAt = memo.lastEditedAt   // C157: this row has had a memo
                outcome.newlyLinked += 1
            }
            if healed && !reflected.changed { row.lastActivityAt = ctx.now }
            if reflected.changed || healed { outcome.updatedIDs.append(row.id) }
            if reflected.watermarked { outcome.watermarked += 1 }
        }

        if deferNew {
            outcome.pendingNewIDs = fresh.map(\.id)
        } else {
            let prepared = fresh.map { memo in
                Ingest.attempt(memo.id) { try Ingest.prepare(memo, assets: assets.blobs(for: memo.id), outputDir: ctx.outputDir) }
            }
            let rows = Ingest.commit(prepared, memos: inputs.memos, enhancements: inputs.enhancements,
                                     into: local, context: ctx, outcome: &outcome, save: false)
            snapshot.rows += rows
            snapshot.rowsWithMemo.formUnion(rows.map(\.id))
        }

        if outcome.created > 0 || !outcome.updatedIDs.isEmpty || outcome.newlyLinked > 0 || outcome.watermarked > 0 {
            ReconcileWork.bump(\.saves)
            do { try local.save() } catch {
                AppLog.cloudkit.error("reconcile v2: save failed: \(String(describing: error), privacy: .public)")
            }
        }
        return (outcome, snapshot)
    }

    /// The memos whose background ingest is running in the app (`Ingest.prepare` off the main
    /// actor, then `Ingest.commit`): the app passes this set as `Context.inFlight`, so an
    /// overlapping pass neither ingests them twice nor trashes their rows as orphans.
    static var ingestInFlight: Set<UUID> = []

    // MARK: - reading

    enum Read { case success(Inputs), failure(String) }

    /// One memo fetch, one enhancement fetch, one row fetch. A failed read is a failure, never an
    /// empty store (R40): an empty memo list would look like "nothing new", an empty row list
    /// would re-ingest everything, an empty enhancement list would drop every polish.
    static func read(cloud: ModelContext, local: ModelContext,
                     fetchMemos: (ModelContext) throws -> [Memo]) -> Read {
        do {
            ReconcileWork.bump(\.memoFetches)
            let all = try fetchMemos(cloud)
            let enhancements = try cloud.fetch(FetchDescriptor<MemoEnhancement>())
            let rows = try local.fetch(FetchDescriptor<PipelineFile>())
            return .success(Inputs(memos: MemoDuplicates.canonicalRows(all), allMemos: all,
                                   enhancements: Dictionary(enhancements.map { ($0.memoID, $0) },
                                                            uniquingKeysWith: { a, _ in a }),
                                   rows: rows))
        } catch {
            return .failure(error.localizedDescription)   // C168: the sync state's detail line shows it
        }
    }

    // MARK: - matching (C188)

    /// Row match = memo id, else the memo's audio filename — but never a row another memo already
    /// owns (an audiobook quote capture inherits its source memo's filename; letting it claim that
    /// row made the two overwrite each other every sweep). A legacy row whose id is nobody's memo
    /// is still claimed by filename.
    struct RowMatcher {
        private var byID: [String: PipelineFile] = [:]
        private var byFilename: [String: PipelineFile] = [:]
        private let ownedIDs: Set<String>

        init(rows: [PipelineFile], memos: [Memo]) {
            for row in rows {
                if byID[row.id] == nil { byID[row.id] = row }
                if !row.filename.isEmpty, byFilename[row.filename] == nil { byFilename[row.filename] = row }
            }
            ownedIDs = Set(memos.map(\.id.uuidString))
        }

        func row(for memo: Memo) -> PipelineFile? {
            let id = memo.id.uuidString
            if let row = byID[id] { return row }
            guard let row = byFilename[Ingest.audioFilename(for: memo)] else { return nil }
            return row.id != id && ownedIDs.contains(row.id) ? nil : row
        }
    }

    // MARK: - the pass around the sweep (C185, C189)

    /// The order of one reconcile, as data so the wiring and its test read one list (C185): names
    /// and vocabulary first so linking sees the fresh roster, then the memo sweep, then the
    /// notice, the save + re-export, the Mac's own memos, the transcript reflect, the index.
    enum Step: String, CaseIterable {
        case names, vocabulary, prompts, sweep, notify, saveAndReexport, authorBackfill,
             transcriptReflect, connectionsIndex
    }

    /// C189: after a sweep only notes ALREADY in the vault re-export — exported, unlocked, live.
    /// The first export of a note is always his verb.
    static func reexportIDs(updated: [String], rows: [PipelineFile]) -> [String] {
        let byID = Dictionary(rows.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var seen = Set<String>()
        return updated.filter { id in
            guard seen.insert(id).inserted, let row = byID[id] else { return false }
            return row.exportStatus == .done && !row.locked && row.deletedAt == nil
        }
    }
}
