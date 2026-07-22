import Foundation

/// The per-sentence-fallback selection layer for the read-along + capture UIs
/// (📖 spike 6, `LANES-2026-07-21C/BASE.md`). Turns one file's alignment
/// sidecar into the sentence list `ReadAlongView` and `MergedCaptureView`
/// render: the published book's own text where the alignment trusts its own
/// match, the ASR transcript's words where it doesn't, and nothing at all when
/// the alignment isn't usable yet — callers then fall back to their existing
/// ASR-only sentence builder.
///
/// Pure — no I/O, no store reads, no MainActor (mirrors
/// `QuoteCaptureProcessor.buildSentences`'s `nonisolated static`, so it's
/// callable from anywhere and trivially unit-testable). Callers resolve the
/// `FileAlignment?` + its freshness via `BookAlignmentStore` first and pass the
/// results in.
enum AlignedSentenceSource {
    /// Per-sentence confidence floor (BASE.md contract, quoted by both lanes):
    /// below this, an `AlignedSentence`'s book text isn't trustworthy enough to
    /// show — that sentence falls back to the ASR words it was spliced from.
    /// At exactly the floor, the book text IS trusted (`>=`, not `>`).
    static let confidenceFloor = 0.5

    /// The read-along/capture sentence list for one file.
    ///
    /// Returns `nil` unless an alignment exists, is fresh, and its file-level
    /// verdict is `.aligned` (a `.partial`/`.rejected` file isn't trustworthy
    /// enough to build a sentence list from at all — the caller's existing
    /// ASR-only builder owns it entirely). Otherwise maps every
    /// `AlignedSentence` to one or more `BufferSentence`s:
    ///
    /// - `confidence >= confidenceFloor` → the aligned book text verbatim,
    ///   `isInInitialSpan` computed with the exact same formula
    ///   `QuoteCaptureProcessor.buildSentences` uses, so the two sources agree
    ///   on "in the quote" whichever one a caller ends up rendering.
    /// - `confidence < confidenceFloor` → the aligned sentence's own text is
    ///   NOT trustworthy; instead the transcript words it was spliced from
    ///   (`transcriptWords[wordStart..<wordEnd]`) are re-partitioned through
    ///   the same `QuoteCaptureProcessor.buildSentences` the ASR-only path
    ///   uses, so a mis-segmented splice still yields well-formed sentence(s)
    ///   — never one raw undifferentiated block, never a garbled partial line
    ///   when the indices don't line up (an empty/out-of-range slice
    ///   contributes nothing).
    ///
    /// The result is always sorted by `start` and deterministic, regardless of
    /// the input array's order or how many sentences one low-confidence splice
    /// fans out into.
    static func sentences(
        alignment: FileAlignment?,
        isFresh: Bool,
        transcriptWords: [WordTiming],
        snappedStart: TimeInterval,
        snappedEnd: TimeInterval
    ) -> [BufferSentence]? {
        guard let alignment, isFresh,
              alignment.verdict == AlignmentCore.Verdict.aligned.rawValue
        else { return nil }

        let mapped: [BufferSentence] = alignment.sentences.flatMap { sentence -> [BufferSentence] in
            guard sentence.confidence >= confidenceFloor else {
                return asrFallback(
                    for: sentence, transcriptWords: transcriptWords,
                    snappedStart: snappedStart, snappedEnd: snappedEnd
                )
            }
            return [BufferSentence(
                text: sentence.text,
                start: sentence.start,
                end: sentence.end,
                words: sentence.words,
                isInInitialSpan: sentence.end > snappedStart && sentence.start < snappedEnd
            )]
        }
        return mapped.sorted { $0.start < $1.start }
    }

    /// One low-confidence `AlignedSentence`'s ASR replacement — clamps
    /// `wordStart..<wordEnd` into `transcriptWords` (defensive against a
    /// stale/out-of-range splice; never traps) and re-partitions that slice
    /// into sentence(s) via the existing builder.
    private static func asrFallback(
        for sentence: AlignedSentence,
        transcriptWords: [WordTiming],
        snappedStart: TimeInterval,
        snappedEnd: TimeInterval
    ) -> [BufferSentence] {
        let lo = max(0, min(sentence.wordStart, transcriptWords.count))
        let hi = max(lo, min(sentence.wordEnd, transcriptWords.count))
        guard hi > lo else { return [] }
        let slice = Array(transcriptWords[lo..<hi])
        return QuoteCaptureProcessor.buildSentences(
            from: slice, snappedStart: snappedStart, snappedEnd: snappedEnd
        )
    }
}
