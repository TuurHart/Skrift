import Foundation

/// Sentence-end detection and the long-form pause threshold for live paragraph joins.
/// `LiveCaptionEngine` uses `endsSentence` and `longFormGap` to place paragraph joins at
/// pause-rotate boundaries mid-take; the resting note is paragraphed by `BodyV2.committed`.
enum Paragrapher {
    /// The Mac's long-form threshold — live joins (`LiveCaptionEngine.resolvedJoin`)
    /// AND the Mac file pass (`BatchRunner`), one constant so the draft and the resting
    /// note agree. Tuned on real Mac takes (2026-07-28): thinking aloud pauses ~0.7–1.5 s
    /// at nearly every sentence, so a paragraph needs a deliberate stop, not a breath.
    static let longFormGap: TimeInterval = 2.0

    /// True if `word` ends a sentence — `BodyV2Text.endsSentence`, the one closer set.
    static func endsSentence(_ word: String) -> Bool {
        BodyV2Text.endsSentence(Substring(word))
    }
}
