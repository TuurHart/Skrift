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

    /// What one synced note contributes, read from the `Memo` + its newest `MemoEnhancement`
    /// — the ONE text both apps embed (Q168, C87/C110), so the same note lands on the same
    /// vector on every device. `id` defaults to the memo's; the Mac passes its queue row's id
    /// so its index keeps answering in the ids its sidebar and panel look up.
    static func snapshot(memo: Memo, enhancement: MemoEnhancement?, id: UUID? = nil) -> MemoSnapshot? {
        let polished = (enhancement?.hasContent == true) ? enhancement?.copyedit : nil
        return snapshot(
            id: id ?? memo.id, userTitle: memo.title, enhancedTitle: enhancement?.title,
            summary: enhancement?.summary, polished: polished, transcript: memo.transcript,
            annotation: memo.annotationText, place: memo.metadata?.location?.placeName,
            tags: memo.tags)
    }

    /// The newest polish row of a memo (LWW by `enhancedAt`), the one `snapshot(memo:…)` reads.
    static func newest(_ rows: [MemoEnhancement]) -> MemoEnhancement? {
        rows.max { $0.enhancedAt < $1.enhancedAt }
    }

    /// Both apps start the engine load on the FIRST search keystroke, before the debounce:
    /// a cold load is the slow part, so the query that follows finds it warm (Q168).
    static func warmsEngine(forQuery query: String) -> Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
