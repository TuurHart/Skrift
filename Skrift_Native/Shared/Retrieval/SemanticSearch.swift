import Foundation

/// Search by meaning — the rules both apps share (Q82 group 13). The phone had a Related
/// section under its exact matches; the Mac had the index but no search. What is embedded
/// and what survives the floor are decided here, once.
enum SemanticSearch {

    /// The Related section's ids: scores at or above the floor, exact matches dropped,
    /// best first, capped. (Was the phone's `JournalIndexService.relatedResults`.)
    static func results(scores: [(memoID: UUID, score: Float)],
                        excluding exact: Set<UUID>,
                        floor: Float = RetrievalTuning.searchFloor,
                        limit: Int = 8) -> [UUID] {
        scores
            .filter { $0.score >= floor && !exact.contains($0.memoID) }
            .sorted { $0.score > $1.score }
            .prefix(limit)
            .map(\.memoID)
    }

    /// What one note contributes to the index. Body = the polished copy when there is one,
    /// else the transcript, plus any typed annotation; title = the user's, else the Mac's.
    /// nil when there is nothing to embed.
    static func snapshot(id: UUID, userTitle: String?, enhancedTitle: String?, summary: String?,
                         polished: String?, transcript: String?, annotation: String?,
                         place: String?, tags: [String]) -> MemoSnapshot? {
        let body = polished ?? transcript ?? ""
        let annotated = annotation.map { body.isEmpty ? $0 : body + "\n" + $0 } ?? body
        guard !annotated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        func clean(_ s: String?) -> String? {
            guard let t = s?.trimmingCharacters(in: .whitespaces), !t.isEmpty else { return nil }
            return t
        }
        return MemoSnapshot(id: id, title: clean(userTitle) ?? clean(enhancedTitle), summary: summary,
                            body: annotated, place: place, tags: tags)
    }
}
