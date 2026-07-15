import Foundation

/// One rescorer replacement, decoupled from FluidAudio's `WordReplacement` so the
/// booster's trust decision is host-testable (no models). Each app maps its own
/// rescore output → these.
struct VocabularyReplacement: Equatable, Sendable {
    let originalWord: String
    let replacementWord: String?
    let shouldReplace: Bool
}

/// The trusted-boost decision — SHARED phone↔Mac. Both boosters ran the identical
/// spot→rescore→**trust→apply** tail: take the `shouldReplace` rows, resolve each
/// canonical's user aliases, and keep the boost ONLY when there is ≥1 applied
/// replacement and EVERY one is trusted (`VocabularyTrust`). A single distant
/// spotter-rescue (e.g. "hello"→"Tuur") drops the WHOLE boost → the clean
/// unboosted transcript. The CTC spot + rescore ENGINES (and the DEBUG tuning
/// knobs) stay app-side; this is only the pure decision they share.
enum VocabularyBoostCore {

    /// The applied `(original, canonical, aliases)` triples: the `shouldReplace`
    /// rows that carry a real replacement word, each paired with that canonical's
    /// aliases (looked up app-side via `aliasesFor`, keeping FluidAudio's vocab
    /// context out of the shared core).
    static func appliedReplacements(_ replacements: [VocabularyReplacement],
                                    aliasesFor: (String) -> [String])
        -> [(original: String, canonical: String, aliases: [String])] {
        replacements.filter(\.shouldReplace).compactMap { r in
            guard let canon = r.replacementWord else { return nil }
            return (r.originalWord, canon, aliasesFor(canon))
        }
    }

    /// Keep a boost ONLY when there is ≥1 applied replacement and EVERY one is
    /// trusted (original string-similar to its canonical, or a user-alias hit).
    static func allTrusted(_ applied: [(original: String, canonical: String, aliases: [String])]) -> Bool {
        guard !applied.isEmpty else { return false }
        return applied.allSatisfy {
            VocabularyTrust.isTrusted(original: $0.original, canonical: $0.canonical, aliases: $0.aliases)
        }
    }
}
