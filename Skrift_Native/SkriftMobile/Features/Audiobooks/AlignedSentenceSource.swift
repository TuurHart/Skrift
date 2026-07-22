import Foundation

/// The per-sentence-fallback selection layer for the read-along + capture UIs
/// (📖 spike 6, `LANES-2026-07-21C/BASE.md`). Turns one file's alignment
/// sidecar into the sentence list `ReadAlongView` and `MergedCaptureView`
/// render: the published book's own text where the alignment trusts its own
/// match, the ASR transcript's words where it doesn't — INCLUDING the words in
/// alignment HOLES (spans no aligned sentence covers: `assembleSentences` drops
/// zero-timed sentences, and narration can carry text the book never had) — and
/// nothing at all when the alignment isn't usable yet, where callers fall back
/// to their existing ASR-only sentence builder. The display is a UNION of book
/// text and transcript, never a replacement (Odyssey device finding 2026-07-22:
/// spoken sentences vanished from the read-along because the aligner missed
/// them — the audio plays them, so the screen must show them).
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

    /// Below this many consecutive uncovered ASR words, a hole in the aligned
    /// stream is boundary fuzz (a word whose times straddle two sentences'
    /// spans) and stays silent; at or above it, the words are real narration
    /// the aligned sentences are missing — rendered as ASR text so spoken
    /// audio never plays against a blank screen.
    static let gapFillMinWords = 3

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
    /// - Transcript words NO aligned sentence covers (`uncoveredWordRanges`,
    ///   runs of ≥ `gapFillMinWords`) → ASR sentences via the same builder.
    ///   These are the aligner's holes: dropped zero-timed sentences, spoken
    ///   text the book never had (credits, asides), a partially-matched
    ///   sentence's untimed tail.
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
        let gapFill: [BufferSentence] = uncoveredWordRanges(
            sentences: alignment.sentences, wordCount: transcriptWords.count
        )
        .filter { $0.count >= gapFillMinWords }
        .flatMap {
            QuoteCaptureProcessor.buildSentences(
                from: Array(transcriptWords[$0]),
                snappedStart: snappedStart, snappedEnd: snappedEnd
            )
        }
        return (mapped + gapFill).sorted { $0.start < $1.start }
    }

    /// Maximal transcript-index runs `[0, wordCount)` that NO aligned sentence's
    /// `[wordStart, wordEnd)` splice range covers — the aligner's holes. Every
    /// sentence counts as covering its range regardless of confidence (a trusted
    /// sentence REPRESENTS those spoken words as book text; an untrusted one
    /// renders them verbatim), so gap fill can never duplicate text either path
    /// already shows. Ranges are clamped defensively (a stale splice never traps).
    static func uncoveredWordRanges(sentences: [AlignedSentence], wordCount: Int) -> [Range<Int>] {
        guard wordCount > 0 else { return [] }
        let covered = sentences
            .map { (lo: max(0, min($0.wordStart, wordCount)), hi: max(0, min($0.wordEnd, wordCount))) }
            .filter { $0.hi > $0.lo }
            .sorted { $0.lo < $1.lo }
        var gaps: [Range<Int>] = []
        var cursor = 0
        for span in covered {
            if span.lo > cursor { gaps.append(cursor..<span.lo) }
            cursor = max(cursor, span.hi)
        }
        if cursor < wordCount { gaps.append(cursor..<wordCount) }
        return gaps
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
