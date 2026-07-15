import os

/// A cheap, thread-safe signal that a transcription is using the Neural Engine RIGHT NOW.
///
/// Both the ASR (Parakeet) and the P8 "Related notes" embedder (EmbeddingGemma-300M) run on the
/// ANE. The embedder's cold load is ~2 MINUTES, and a related-notes refresh fires as you type — so
/// on a device (2026-07-15) a 13-second clip waited ~2 min because the embedder cold-loaded on the
/// shared ANE and starved the transcriber. The transcriber raises this flag while it works, and the
/// embedder checks it and YIELDS its cold load until the flag clears — the ANE stays free for ASR.
enum TranscriptionActivity {
    private static let depth = OSAllocatedUnfairLock(initialState: 0)

    /// Balanced-pair around a transcription (re-entrant — a counter, not a bool).
    static func begin() { depth.withLock { $0 += 1 } }
    static func end()   { depth.withLock { $0 = max(0, $0 - 1) } }

    static var isActive: Bool { depth.withLock { $0 > 0 } }
}
