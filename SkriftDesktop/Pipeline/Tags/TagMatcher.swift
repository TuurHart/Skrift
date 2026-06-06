import Foundation
import NaturalLanguage

/// Deterministic tag suggestions (no LLM). Ported from `enhancement.py`
/// (`match_tags_in_text` / `extract_spoken_hashtags`), swapping simplemma for
/// Apple's NLTagger lemmatizer (nl+en). Lemma parity differs slightly from
/// simplemma — acceptable since tags are review-time suggestions only (plan §6).
/// Pure (text + vault whitelist → suggestions); host-testable.
enum TagMatcher {

    /// Suggestion result: `matched` = vault tags whose word the user actually said
    /// often enough; `spoken` = explicit `#hashtags` not already in the vault list.
    struct Suggestions: Equatable, Sendable {
        var matched: [String]   // "old" — known vault tags
        var spoken: [String]    // "new" — spoken hashtags
    }

    static func suggest(text: String, whitelist: [String], minOccurrences: Int = 2,
                        maxMatched: Int = 10, maxSpoken: Int = 5) -> Suggestions {
        let lower = Set(whitelist.map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty })
        var matched = matchTags(in: text, matchable: Array(lower).sorted(), minOccurrences: minOccurrences)
        let matchedSet = Set(matched)
        var spoken = spokenHashtags(in: text).filter { !lower.contains($0) && !matchedSet.contains($0) }
        if matched.count > maxMatched { matched = Array(matched.prefix(maxMatched)) }
        if spoken.count > maxSpoken { spoken = Array(spoken.prefix(maxSpoken)) }
        return Suggestions(matched: matched, spoken: spoken)
    }

    /// Vault tags whose component lemmas EACH occur >= minOccurrences in the text.
    static func matchTags(in text: String, matchable: [String], minOccurrences: Int = 2) -> [String] {
        guard !text.isEmpty, !matchable.isEmpty else { return [] }
        var counts: [String: Int] = [:]
        for lemma in lemmatize(text) { counts[lemma, default: 0] += 1 }
        return matchable.filter { tag in
            let lemmas = tagLemmas(tag)
            return !lemmas.isEmpty && lemmas.allSatisfy { (counts[$0] ?? 0) >= minOccurrences }
        }
    }

    /// Explicit `#hashtags` literally in the text — committed directly (high
    /// precision). Lowercased, no leading '#', numeric-only dropped, deduped.
    static func spokenHashtags(in text: String) -> [String] {
        guard !text.isEmpty,
              let rx = try? NSRegularExpression(pattern: #"(?<!\w)#([^\W\d_][\w\-/]*)"#) else { return [] }
        let ns = text as NSString
        var seen = Set<String>()
        var out: [String] = []
        for m in rx.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let t = ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespaces).lowercased()
            if !t.isEmpty, !seen.contains(t) { seen.insert(t); out.append(t) }
        }
        return out
    }

    // MARK: - Lemmatization

    /// Lemma of every word (lowercased). NLTagger with the surface form as fallback.
    static func lemmatize(_ text: String) -> [String] {
        guard !text.isEmpty else { return [] }
        let tagger = NLTagger(tagSchemes: [.lemma])
        tagger.string = text
        var out: [String] = []
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .lemma,
                             options: [.omitWhitespace, .omitPunctuation, .omitOther]) { tag, range in
            if let lemma = tag?.rawValue, !lemma.isEmpty {
                out.append(lemma.lowercased())
            } else {
                let surface = text[range].lowercased()
                if !surface.isEmpty { out.append(surface) }
            }
            return true
        }
        return out
    }

    /// Lemmatize a (possibly multi-word/hyphenated) tag into its component lemmas.
    static func tagLemmas(_ tag: String) -> [String] {
        tag.split(whereSeparator: { $0 == " " || $0 == "-" || $0 == "_" || $0 == "/" })
            .flatMap { lemmatize(String($0)) }
            .filter { !$0.isEmpty }
    }
}
