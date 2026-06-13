import Foundation

// Wave-2 text-capture: the per-book transcript sidecar (design
// `mocks/text-capture-DESIGN.md` §4/§6/§13). A whole-book pre-transcribe so
// text-capture is INSTANT and works ANYWHERE in a chapter — not just near the
// playhead. The sidecar IS the resume state (each chunk saved as it lands).
//
// TIME BASIS = (fileIndex, file-local seconds). Capture is confined to ONE
// chapter file — the same invariant `QuoteCaptureProcessor` enforces
// (a span never crosses a file boundary). Each file gets its own sidecar so a
// capture only ever reads the file it's in, and the atomic per-file write keeps
// the write small on a long m4b.
//
// We store WORD-TIMINGS (not pre-split sentences): the capture screen derives
// sentences with the SAME `QuoteCaptureProcessor.buildSentences` the wave-1
// window path uses, so a chunked spot and an un-chunked spot render identically.

/// One file's transcript: word-timings (file-local) covering `[0, coveredUpTo]`.
/// `coveredUpTo` is the resume frontier — the file-local second the chunker has
/// transcribed AND saved up to. Words past it don't exist yet.
struct FileTranscript: Codable, Equatable, Sendable {
    /// Bumped if the on-disk shape (or how the times are produced) changes —
    /// older sidecars then read as stale and are re-transcribed. v2 = the
    /// sample-accurate (drift-free) chunk extraction fix (2026-06-13); v1
    /// sidecars drift late deep in long chapters, so they must be redone.
    static let currentSchema = 2

    var schema: Int = currentSchema
    /// Which file of the book this covers (`Audiobook.files` index).
    var fileIndex: Int
    /// Staleness key — the audio file's `size:mtime` when transcribed. A
    /// re-import (different signature) invalidates this transcript.
    var signature: String
    /// File-local seconds transcribed + saved so far (the resume frontier).
    var coveredUpTo: TimeInterval
    /// All recognised words so far, file-local times, in order.
    var words: [WordTiming]

    init(fileIndex: Int, signature: String, coveredUpTo: TimeInterval = 0,
         words: [WordTiming] = [], schema: Int = currentSchema) {
        self.schema = schema
        self.fileIndex = fileIndex
        self.signature = signature
        self.coveredUpTo = coveredUpTo
        self.words = words
    }

    // MARK: - Pure queries (host-less, unit-tested)

    /// True when `[0, time]` has been transcribed — i.e. a capture window that
    /// ENDS at `time` can be served entirely from this sidecar. A small epsilon
    /// absorbs float drift at a chunk boundary.
    func isCovered(upTo time: TimeInterval) -> Bool {
        time <= coveredUpTo + 0.05
    }

    /// Words whose time span overlaps `[start, end]` (file-local) — the material
    /// the capture screen turns into tappable sentences. Ordered.
    func words(inWindow start: TimeInterval, end: TimeInterval) -> [WordTiming] {
        guard end > start else { return [] }
        return words.filter { $0.end > start && $0.start < end }
    }

    /// Append a freshly-transcribed-and-fused chunk: its words (already
    /// file-local, already seam-spliced by the chunker so they begin at the last
    /// frontier) plus the new frontier. Idempotent in practice — the job always
    /// resumes from `coveredUpTo`, so a chunk never overlaps saved words; a chunk
    /// that lands at or behind the frontier (a stale/interrupted retry) is
    /// ignored so a torn half-chunk can't corrupt the saved transcript.
    func appending(_ chunkWords: [WordTiming], upTo newFrontier: TimeInterval) -> FileTranscript {
        guard newFrontier > coveredUpTo else { return self }
        var copy = self
        copy.words.append(contentsOf: chunkWords)
        copy.coveredUpTo = newFrontier
        return copy
    }
}
