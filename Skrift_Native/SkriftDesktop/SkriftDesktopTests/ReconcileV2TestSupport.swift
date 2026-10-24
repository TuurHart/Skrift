import Foundation
import SwiftData

/// Q432: the one-call forms tests use to drive reconcile v2 (v1's `MemoCloudIngest.ingest`,
/// `MemoCloudUpdate.apply`, `MacCloudWriteBack.upsert` and `MemoCloudReconciler.sweep` were
/// one call each). Each is the app's own v2 path, nothing re-implemented.
@MainActor
enum V2 {

    static func context(people: [Person] = [], author: String = "", device: String = "",
                        now: Date = Date(), outputDir: URL? = nil) -> ReconcileV2.Context {
        .init(people: people, author: author, thisDeviceID: device, now: now,
              outputDir: outputDir ?? FileManager.default.temporaryDirectory
                  .appendingPathComponent("v2-\(UUID().uuidString)", isDirectory: true))
    }

    /// First contact for one memo: `Ingest.prepare` then `Ingest.commit`, the sweep's own two
    /// halves. Nil when the memo makes no row (unrated, trashed, waiting for its audio, or a row
    /// with its id already exists). Saves `local` when a row was made.
    @discardableResult
    static func ingest(_ memo: Memo, assets: [MemoAsset], outputDir: URL, into local: ModelContext,
                       enhancement: MemoEnhancement? = nil, people: [Person] = [], author: String = "",
                       device: String = "") throws -> PipelineFile? {
        let attempt = ReconcileV2.Ingest.attempt(memo.id) {
            try ReconcileV2.Ingest.prepare(memo, assets: assets, outputDir: outputDir)
        }
        if case .failed(_, let message) = attempt { throw IngestFailed(message: message) }
        var outcome = ReconcileV2.Outcome()
        let rows = ReconcileV2.Ingest.commit([attempt], memos: [memo], enhancements: enhancement.map { [memo.id: $0] } ?? [:],
                                             into: local,
                                             context: context(people: people, author: author, device: device, outputDir: outputDir),
                                             outcome: &outcome, save: true)
        return rows.first
    }

    struct IngestFailed: Error { let message: String }

    /// The phone → Mac reflect on an existing row; true when the row changed.
    @discardableResult
    static func reflect(_ memo: Memo, enhancement: MemoEnhancement?, to row: PipelineFile,
                        people: [Person] = [], author: String = "", device: String = "",
                        now: Date = Date(), freshRow: Bool = false) -> Bool {
        ReconcileV2.Reflect.apply(memo: memo, enhancement: enhancement, to: row,
                                  context: context(people: people, author: author, device: device, now: now),
                                  freshRow: freshRow).changed
    }

    /// The Mac's polish write-back; returns the memo's enhancement as stored afterwards (nil when
    /// the row has no memo or nothing was written).
    @discardableResult
    static func upsert(_ row: PipelineFile, into cloud: ModelContext, device: String, now: Date = Date(),
                       body: String? = nil, passRan: Bool = false) throws -> MemoEnhancement? {
        switch try ReconcileV2.Writers.upsertEnhancement(for: row, into: cloud, deviceID: device, now: now,
                                                         body: body, passRan: passRan) {
        case .noMemo, .nothingToWrite: return nil
        case .written, .refusedNewer:
            guard let id = ReconcileV2.Writers.resolve(row, in: cloud)?.id else { return nil }
            return try cloud.fetch(FetchDescriptor<MemoEnhancement>(predicate: #Predicate { $0.memoID == id })).first
        }
    }

    /// One sweep of `cloud` into `local`.
    @discardableResult
    static func sweep(_ cloud: ModelContext, into local: ModelContext, people: [Person] = [], author: String = "",
                      device: String = "", now: Date = Date(), outputDir: URL? = nil) -> ReconcileV2.Outcome {
        ReconcileV2.sweep(cloud: cloud, local: local,
                          context: context(people: people, author: author, device: device, now: now, outputDir: outputDir))
    }

    /// The memo a Mac row becomes (`Author.author`), saved, as the arrival path saves it.
    @discardableResult
    static func author(_ row: PipelineFile, into cloud: ModelContext, device: String = "") throws -> Memo? {
        let memo = try ReconcileV2.Author.author(row, into: cloud, deviceID: device)
        if memo != nil { try cloud.save() }
        return memo
    }

    /// `author` over every row with a memo-shaped id and a working path, with no first-import or
    /// local-capture gate (those are the pass's, `Author.mayBackfill`); saved once.
    @discardableResult
    static func backfill(_ rows: [PipelineFile], into cloud: ModelContext, device: String = "") throws -> Int {
        var count = 0
        for row in rows where UUID(uuidString: row.id) != nil && !row.path.isEmpty {
            if try ReconcileV2.Author.author(row, into: cloud, deviceID: device) != nil { count += 1 }
        }
        if count > 0 { try cloud.save() }
        return count
    }

    /// One reconcile pass (`ReconcileV2.pass`).
    @discardableResult
    static func pass(_ cloud: ModelContext, into local: ModelContext, people: [Person] = [], author: String = "",
                     device: String = "", now: Date = Date(), outputDir: URL? = nil, deferNew: Bool = false,
                     firstImportDone: Bool = false,
                     fetchMemos: (ModelContext) throws -> [Memo] = { try $0.fetch(FetchDescriptor<Memo>()) })
        -> ReconcileV2.PassOutcome {
        ReconcileV2.pass(cloud: cloud, local: local,
                         context: context(people: people, author: author, device: device, now: now, outputDir: outputDir),
                         firstImportDone: firstImportDone, deferNew: deferNew, fetchMemos: fetchMemos)
    }
}
