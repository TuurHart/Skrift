import Foundation

// Wave-2 text-capture: chunk-seam fusion (design `mocks/text-capture-DESIGN.md`
// §6). FluidAudio's `transcribe` takes no time range, so the job exports each
// chunk to a temp .m4a (the `QuoteCaptureProcessor.exportSpan` pattern) and
// transcribes it. The seam between consecutive chunks must not split a word or
// duplicate one.
//
// STRATEGY (simpler + more robust than overlap-agreement): each chunk is
// transcribed from the previous frontier, but we KEEP only its COMPLETE
// sentences and set the new frontier to the start of its last (possibly partial)
// sentence. The next chunk re-transcribes that trailing sentence from a clean
// sentence start. So every kept word comes from a chunk where it's whole, the
// seam always lands on a sentence boundary (the existing `SentenceSnap` tech),
// and nothing is duplicated. "Cut at the longest pause" falls out for free —
// sentence ends are the long silences.
enum ChunkFusion {
    /// A transcribed chunk reduced to the words to KEEP and the frontier the next
    /// chunk starts from.
    struct Fused: Equatable {
        var kept: [WordTiming]
        /// File-local second the next chunk starts at (and the saved coverage).
        var newFrontier: TimeInterval
    }

    /// Reduce one transcribed chunk to its keepable words + the next frontier.
    ///
    /// - Parameters:
    ///   - chunkWords: the chunk's words in FILE-LOCAL time (caller has already
    ///     offset them by `chunkStart`).
    ///   - chunkStart / chunkEnd: the chunk's file-local span.
    ///   - isFinal: true when this chunk reaches the file's end (keep everything;
    ///     there's no tail to re-transcribe).
    ///   - minProgress: smallest acceptable frontier advance. If cutting at the
    ///     last sentence boundary would advance less than this (a sentence longer
    ///     than most of the chunk), keep the whole chunk and advance to its end
    ///     instead — prevents a pathological tiny-step loop on run-on speech.
    static func fuse(chunkWords: [WordTiming],
                     chunkStart: TimeInterval,
                     chunkEnd: TimeInterval,
                     isFinal: Bool,
                     minProgress: TimeInterval) -> Fused {
        // Silence / no speech in this chunk → keep nothing but still advance past
        // it, or the job would re-transcribe the same silence forever.
        guard !chunkWords.isEmpty else {
            return Fused(kept: [], newFrontier: max(chunkEnd, chunkStart))
        }
        if isFinal {
            return Fused(kept: chunkWords, newFrontier: max(chunkEnd, chunkWords.last?.end ?? chunkEnd))
        }

        let starts = SentenceSnap.sentenceStartIndices(chunkWords)
        // Need at least two sentence starts to have a COMPLETE sentence to keep
        // and a trailing one to re-transcribe. With ≤1, keep all + advance to end.
        guard starts.count >= 2 else {
            return Fused(kept: chunkWords, newFrontier: chunkEnd)
        }
        let lastStart = starts[starts.count - 1]
        let frontier = chunkWords[lastStart].start
        // Guard against a tiny advance (one giant sentence filling the chunk).
        guard frontier - chunkStart >= minProgress else {
            return Fused(kept: chunkWords, newFrontier: chunkEnd)
        }
        return Fused(kept: Array(chunkWords[0..<lastStart]), newFrontier: frontier)
    }
}
