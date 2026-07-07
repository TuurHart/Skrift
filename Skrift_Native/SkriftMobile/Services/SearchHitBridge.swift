import Foundation

/// List-search → note handoff (round-4 ask: "take me to the spot and
/// highlight it for a second"): tapping a result while a query is active
/// stashes the query here; the opened note's editor consumes it ONCE and
/// flashes the first hit — the matched text range, or the photo whose OCR
/// text matched when the words live inside a picture.
@MainActor
enum SearchHitBridge {
    static var pending: (memoID: UUID, query: String)?

    /// One-shot take: the query if it targets this memo, clearing the stash.
    static func take(for memoID: UUID) -> String? {
        guard let p = pending, p.memoID == memoID else { return nil }
        pending = nil
        return p.query
    }
}
