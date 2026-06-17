import Foundation

/// Risk-tiering for the OPT-OUT name-linker (NAMING_MODEL.md decision 4 + the
/// NON-NEGOTIABLE common-word/short-name FP guards). Opt-out auto-*writes* `[[ ]]`
/// links to the exported file, which AMPLIFIES the #1 documented failure of
/// deterministic matching — a common word that doubles as a first name
/// ("I **will** call" vs the roster's "Will") getting falsely linked. So a bare
/// first name only auto-commits when it's *distinctive*; the FP-prone subset is
/// downgraded to a dotted **suggestion** (committed on click in review).
///
/// Pure + deterministic + LLM-free → portable to the phone. The stoplist is
/// deliberately conservative: it lists clear common-word/given-name collisions in
/// the user's English+Dutch usage. Erring toward INCLUSION is safe (a distinctive
/// person who happens to be on it costs one click), erring toward OMISSION is not
/// (a false link silently lands in a 50-year archive). Tunable in chunk 5.
enum NameStoplist {
    /// Single-token first names that are also common English/Dutch words — auto-linking
    /// them risks a false positive, so they're suggested (dotted) rather than committed.
    /// Lowercased; matched whole-word. Capitalization is the secondary FP-guard the
    /// Sanitiser layers on top (a lowercase "will" stays plain; a capitalized "Will"
    /// becomes a suggestion).
    static let commonWords: Set<String> = [
        // English given-name / common-word collisions
        "will", "mark", "rose", "grace", "hope", "drew", "bill", "dawn", "joy",
        "faith", "may", "june", "april", "art", "rich", "sunny", "sky", "ray",
        "daisy", "ivy", "holly", "summer", "autumn", "pearl", "ruby", "jade",
        "hazel", "olive", "robin", "jay", "dale", "dean", "earl", "miles", "max",
        "rosemary", "melody", "angel", "chase", "field", "reed", "brook", "brooke",
        "wade", "frank", "patience", "honor", "star", "sage", "fern", "heath",
        // Dutch given-name / common-word collisions (user writes EN+NL)
        "wil", "roos", "lente", "floor", "lot", "fleur", "bloem", "guus", "storm",
        "loes", "mees", "duif", "vlinder",
    ]

    /// Minimum length for a single-token alias to auto-commit. Tokens this short
    /// ("Jo", "Ed", "Al", "Bo") collide too easily to safely auto-write; they go
    /// dotted-suggested instead. (Our vocab-booster memory flags ≤3–4-char names as
    /// FP-prone — [[project_vocab_booster]] — the same hazard in the naming path.)
    static let minAutoCommitLength = 3

    /// True when a single-token alias is too FP-prone to AUTO-COMMIT (link without a
    /// click): a common-word collision or a ≤2-char token. Multi-token full names
    /// ("Jack Hutton") are always distinctive → never FP-prone. The Sanitiser also
    /// treats an alias shared by 2+ roster people as suggest-only (ambiguity, decision
    /// 9) — that's orthogonal to this per-alias common-word check.
    static func isFpProne(_ alias: String) -> Bool {
        let t = alias.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return false }
        // A full name (any internal whitespace) is a distinctive multi-token match.
        if t.contains(where: \.isWhitespace) { return false }
        if t.count < minAutoCommitLength { return true }
        return commonWords.contains(t.lowercased())
    }
}
