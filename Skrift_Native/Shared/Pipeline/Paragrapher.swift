import Foundation

/// Sentence-end detection and the long-form pause threshold for live paragraph joins.
///
/// `LiveCaptionEngine` leans on `endsSentence` and `longFormGap` to place paragraph
/// joins at pause-rotate boundaries mid-take. The stored-transcript paragrapher (v1)
/// and its 0.65s `defaultGap` are gone: body v2 (`BodyV2.committed`) paragraphs the
/// resting note. The v1 splitter survives only as a fixture inside
/// `BodyNormaliseMigrationTests`.
enum Paragrapher {
    /// The Mac's long-form threshold — live joins (`LiveCaptionEngine.resolvedJoin`)
    /// AND the Mac file pass (`BatchRunner`), one constant so the draft and the
    /// resting note agree. Tuur's first real Mac takes (ROUND 11, 2026-07-28):
    /// thinking aloud pauses ~0.7–1.5 s at nearly every sentence, so a 0.65 s gap
    /// shredded the note into one-line paragraphs ("a lot of gaps in there"). On the
    /// Mac a paragraph needs a DELIBERATE stop, not a breath.
    static let longFormGap: TimeInterval = 2.0

    /// True if `word` ends a sentence — `BodyV2Text.endsSentence`, the one closer set.
    static func endsSentence(_ word: String) -> Bool {
        BodyV2Text.endsSentence(Substring(word))
    }
}
