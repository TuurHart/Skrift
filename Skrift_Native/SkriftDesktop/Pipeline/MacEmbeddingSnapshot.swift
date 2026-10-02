import Foundation
import SwiftData

/// What the Mac's Connections index embeds (Q168). Membership stays the queue's
/// (`NoteConsent.joinsConnectionsIndex`: live + rated); the TEXT comes from the synced
/// `Memo` + its newest `MemoEnhancement` through `SemanticSearch.snapshot(memo:…)`, the same
/// rule the phone runs, so one note embeds the same words on every device (user title,
/// typed annotation, enhancement copy-edit). A queue row with no synced memo (CloudKit off,
/// a pre-CloudKit local file) keeps the file-only snapshot.
@MainActor
enum MacEmbeddingSnapshot {

    /// Snapshots for every index member in `files`. `cloud` is a context on the shared Memo
    /// store, nil when CloudKit is unavailable. Memos and enhancements are fetched once.
    static func snapshots(files: [PipelineFile], cloud: ModelContext?) -> [MemoSnapshot] {
        let memos = cloud.flatMap { try? $0.fetch(FetchDescriptor<Memo>()) } ?? []
        let rows = cloud.flatMap { try? $0.fetch(FetchDescriptor<MemoEnhancement>()) } ?? []
        var memosByID: [UUID: Memo] = [:]
        for memo in memos { memosByID[memo.id] = memo }
        let enhancementsByMemo = Dictionary(grouping: rows, by: \.memoID)
        return files.filter(NoteConsent.joinsConnectionsIndex).compactMap { file in
            snapshot(file, memosByID: memosByID, enhancementsByMemo: enhancementsByMemo)
        }
    }

    /// One queue row's snapshot. The id is the ROW's (the sidebar's Related rows and the panel
    /// look hits up by `PipelineFile.id`); nil for a non-UUID row id (pre-CloudKit demo rows).
    static func snapshot(_ file: PipelineFile, memosByID: [UUID: Memo],
                         enhancementsByMemo: [UUID: [MemoEnhancement]]) -> MemoSnapshot? {
        guard let uuid = UUID(uuidString: file.id) else { return nil }
        if let memo = resolve(file, in: memosByID) {
            return SemanticSearch.snapshot(
                memo: memo, enhancement: SemanticSearch.newest(enhancementsByMemo[memo.id] ?? []), id: uuid)
        }
        return fileOnly(file, id: uuid)
    }

    /// `MacCloudWriteBack.resolve`'s candidate order, against an in-memory map instead of
    /// three store fetches per row.
    static func resolve(_ file: PipelineFile, in memosByID: [UUID: Memo]) -> Memo? {
        let candidates = [MacCloudWriteBack.memoID(for: file),
                          MacCloudWriteBack.uuid(fromFilename: file.filename),
                          UUID(uuidString: file.id)]
        for case let candidate? in candidates {
            if let memo = memosByID[candidate] { return memo }
        }
        return nil
    }

    /// A row with no synced memo: the body it shows (`sanitised` carries the Mac's own
    /// edits), else its copy-edit, else the transcript.
    static func fileOnly(_ file: PipelineFile, id: UUID) -> MemoSnapshot? {
        let meta = file.audioMetadataJSON.flatMap { try? JSONDecoder().decode(PhoneMetadata.self, from: $0) }
        return SemanticSearch.snapshot(
            id: id, userTitle: nil, enhancedTitle: file.enhancedTitle, summary: file.enhancedSummary,
            polished: file.sanitised ?? file.enhancedCopyedit, transcript: file.transcript, annotation: nil,
            place: meta?.location?.placeName, tags: file.tags)
    }
}
