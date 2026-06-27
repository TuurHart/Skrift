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
        // Preferred seam: cut at the last COMPLETE sentence and re-transcribe the
        // trailing one next chunk. Needs ≥2 sentence starts (one complete + a
        // trailing partial) AND enough advance to avoid a tiny-step loop.
        if starts.count >= 2 {
            let lastStart = starts[starts.count - 1]
            let frontier = chunkWords[lastStart].start
            if frontier - chunkStart >= minProgress {
                return Fused(kept: Array(chunkWords[0..<lastStart]), newFrontier: frontier)
            }
        }
        // Fallback: no usable sentence boundary in the chunk's back half (a run-on
        // sentence filling the chunk, e.g. the long "creative genius…" sentence).
        // We CANNOT just keep every word up to the arbitrary `chunkEnd` cut: that
        // cut lands MID-WORD, so the boundary word is transcribed from TRUNCATED
        // audio (mis-decoded + terminating period lost — "session" → "summer") yet
        // kept here, while the next chunk drops it (it starts before chunkEnd). The
        // orphaned, period-less word then merges the two sentences it straddles
        // (device bug 2026-06-27). So mirror the sentence redo-tail at WORD
        // granularity: drop the final word and rewind the frontier to its start, so
        // the next chunk re-transcribes it whole (its audio is uncut there).
        let lastIdx = chunkWords.count - 1
        if lastIdx >= 1 {
            let wordFrontier = chunkWords[lastIdx].start
            if wordFrontier - chunkStart >= minProgress {
                return Fused(kept: Array(chunkWords[0..<lastIdx]), newFrontier: wordFrontier)
            }
        }
        // Even the last-word rewind wouldn't make minimal progress (a few words
        // bunched early then silence) → accept the cut to guarantee forward motion.
        return Fused(kept: chunkWords, newFrontier: chunkEnd)
    }
}
