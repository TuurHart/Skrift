import Foundation

/// Why two notes are connected — the small evidence chips under a Connections
/// row (shared person 👤 / #tag / recurring “term”). MOVED here from the Mac's
/// `ConnectionsModel` (iPad wave v2, 2026-07-23) so both panels derive the SAME
/// chips from the same dumb-v1 overlap heuristic and can never drift.
struct ConnectionWhy: Hashable, Sendable {
    enum Kind: Sendable { case person, tag, term }
    let kind: Kind
    let text: String
}

enum ConnectionWhyDerivation {
    /// ≤2 shared people, ≤2 shared tags, content-word overlap filling to 4.
    /// `names` are each side's linked-people set — the Mac feeds `[[Name]]`
    /// wikilinks from the sanitised body (`wikiNames`); the phone/iPad has no
    /// sanitised layer and passes `[]` for now (tags + terms carry the why).
    static func chips(currentNames: Set<String>, currentTags: [String], currentBody: String,
                      otherNames: Set<String>, otherTags: [String], otherBody: String) -> [ConnectionWhy] {
        var chips: [ConnectionWhy] = []
        for name in currentNames.intersection(otherNames).sorted().prefix(2) {
            chips.append(ConnectionWhy(kind: .person, text: name))
        }
        for tag in Set(currentTags).intersection(otherTags).sorted().prefix(2) {
            chips.append(ConnectionWhy(kind: .tag, text: "#\(tag)"))
        }
        if chips.count < 4 {
            let a = contentWordCounts(currentBody), b = contentWordCounts(otherBody)
            let shared = Set(a.keys).intersection(b.keys)
                .sorted { min(a[$0] ?? 0, b[$0] ?? 0) > min(a[$1] ?? 0, b[$1] ?? 0) }
            for term in shared.prefix(4 - chips.count) {
                chips.append(ConnectionWhy(kind: .term, text: term))
            }
        }
        return chips
    }

    /// `[[Name]]` wikilink targets in a sanitised body — people links only
    /// (`[[memo:…]]` note-links excluded). Mac-side input builder.
    static func wikiNames(inSanitised body: String?) -> Set<String> {
        guard let body else { return [] }
        var names = Set<String>()
        var search = body.startIndex
        while let open = body.range(of: "[[", range: search..<body.endIndex),
              let close = body.range(of: "]]", range: open.upperBound..<body.endIndex) {
            let inner = String(body[open.upperBound..<close.lowerBound])
            if !inner.hasPrefix("memo:"), inner.count < 60 {
                names.insert(String(inner.split(separator: "|").first ?? ""))
            }
            search = close.upperBound
        }
        names.remove("")
        return names
    }

    private static let stopWords: Set<String> = [
        "about", "after", "again", "because", "before", "being", "could", "every",
        "first", "going", "little", "maybe", "other", "really", "should", "something",
        "their", "there", "these", "thing", "things", "think", "though", "today",
        "wanna", "where", "which", "while", "would", "gonna", "still", "actually"]

    static func contentWordCounts(_ body: String) -> [String: Int] {
        var counts: [String: Int] = [:]
        for word in body.lowercased().split(whereSeparator: { !$0.isLetter }) {
            guard word.count >= 5, !stopWords.contains(String(word)) else { continue }
            counts[String(word), default: 0] += 1
        }
        return counts
    }
}
