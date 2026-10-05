import Foundation

/// Q317 (perf, iPhone 13): opening a book decoded the multi-MB transcript and alignment
/// sidecars on the main actor (`ReadAlongModel.reloadIfNeeded` 536 ms, FileTranscript decode
/// 357 ms in the trace; D-B1a/b/d). This is the one place that does the decode, and it runs
/// it on a detached task: the read-along and the capture screen `await` it and publish the
/// result. One transcript decode per call (the alignment freshness check reuses it).
enum BookSidecarLoader {

    /// What the read-along needs for one file at one playhead.
    struct ReadAlong: Sendable, Equatable {
        /// The sentence list: true text where aligned, else the ASR-only builder.
        var sentences: [BufferSentence]
        /// The transcript's coverage frontier (file-local seconds).
        var coveredUpTo: TimeInterval
    }

    /// Test seam: where the last decode ran. Written by `readAlong`, read by tests.
    final class Probe: @unchecked Sendable {
        private let lock = NSLock()
        private var main: Bool?
        private var n = 0
        func record(onMainThread: Bool) { lock.lock(); main = onMainThread; n += 1; lock.unlock() }
        var lastRanOnMainThread: Bool? { lock.lock(); defer { lock.unlock() }; return main }
        var decodeCount: Int { lock.lock(); defer { lock.unlock() }; return n }
    }
    static let probe = Probe()

    /// nil = this spot is not covered by a fresh transcript (the "transcribe to read along" state).
    /// Runs on a background executor.
    static func readAlong(directory: URL, bookID: UUID, fileIndex: Int, audioURL: URL,
                          fileLocal: TimeInterval) async -> ReadAlong? {
        await Task.detached(priority: .userInitiated) {
            probe.record(onMainThread: Thread.isMainThread)
            return readAlongSync(directory: directory, bookID: bookID, fileIndex: fileIndex,
                                 audioURL: audioURL, fileLocal: fileLocal)
        }.value
    }

    /// The capture screen's sidecar read (`MergedCaptureView.load`): the sentence list around
    /// the capture window, or nil when the sidecar does not cover `winEnd` (then the caller
    /// transcribes live). Off the main actor.
    static func captureSentences(directory: URL, bookID: UUID, fileIndex: Int, audioURL: URL,
                                 winStart: TimeInterval, winEnd: TimeInterval) async -> [BufferSentence]? {
        await Task.detached(priority: .userInitiated) {
            probe.record(onMainThread: Thread.isMainThread)
            let store = BookTranscriptStore(directory: directory)
            guard let ft = store.fileTranscript(bookID: bookID, fileIndex: fileIndex, audioURL: audioURL),
                  ft.isCovered(upTo: winEnd) else { return nil }
            // True text first: the aligned list is keyed off the FULL file transcript (its
            // splice indices are into `ft.words`), then trimmed to the capture window.
            if let aligned = BookAlignmentStore(directory: directory)
                .alignedSentences(bookID: bookID, fileIndex: fileIndex, transcript: ft) {
                return aligned.filter { $0.end > winStart - 30 && $0.start < winEnd + 150 }
            }
            // Window the words BEFORE sentence-building (pads keep edge sentences intact).
            return QuoteCaptureProcessor.buildSentences(
                from: ft.words(inWindow: winStart - 30, end: winEnd + 150))
        }.value
    }

    /// Whether a fresh sidecar already covers `end` (the player's pre-warm check) — the
    /// cached frontier, not a words decode; a cold cache decodes once, off the main actor.
    static func sidecarCovers(directory: URL, bookID: UUID, fileIndex: Int, audioURL: URL,
                              end: TimeInterval) async -> Bool {
        await Task.detached(priority: .utility) {
            let store = BookTranscriptStore(directory: directory)
            let sig = store.signature(forFileAt: audioURL)
            guard let f = store.frontierStats(bookID: bookID, fileIndex: fileIndex, expectedSignature: sig)
            else { return false }
            return FileTranscript.isCovered(frontier: f.covered, upTo: end)
        }.value
    }

    /// The synchronous body (never call it from the main actor).
    nonisolated static func readAlongSync(directory: URL, bookID: UUID, fileIndex: Int, audioURL: URL,
                                          fileLocal: TimeInterval) -> ReadAlong? {
        let store = BookTranscriptStore(directory: directory)
        guard let ft = store.fileTranscript(bookID: bookID, fileIndex: fileIndex, audioURL: audioURL),
              ft.isCovered(upTo: fileLocal) else { return nil }
        let aligned = BookAlignmentStore(directory: directory)
            .alignedSentences(bookID: bookID, fileIndex: fileIndex, transcript: ft)
        let sentences = aligned ?? QuoteCaptureProcessor.buildSentences(from: ft.words)
        return ReadAlong(sentences: sentences, coveredUpTo: ft.coveredUpTo)
    }
}
