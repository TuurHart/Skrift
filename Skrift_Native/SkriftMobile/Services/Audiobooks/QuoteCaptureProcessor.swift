import AVFoundation
import Foundation

/// A sentence derived from a transcript window, shown as a selectable line on
/// the text-capture screen. Times are LOCAL to the audio the words came from
/// (the window buffer, or the book file for sidecar sentences), not the book.
struct BufferSentence: Sendable, Equatable {
    var text: String
    /// First word timing (local time).
    var start: TimeInterval
    /// Last word timing (local time).
    var end: TimeInterval
    /// Slice of word timings for this sentence (local).
    var words: [WordTiming]
}

/// The result of building one confirmed capture: the quote text, its audio (a
/// temp .m4a the saver moves into recordings), and the word timings rebased
/// onto that audio (karaoke sidecar).
///
/// `bufferAudioURL` is a temp file whose lifetime is tied to the capture flow
/// (cleaned up by the caller on dismiss). The saver must NOT use it; it always
/// uses `audioURL`.
struct QuoteCaptureOutput: Sendable {
    var quote: String
    /// Span in BOOK time (for the "12:05 → 12:38" label + chapter lookup).
    var spanStart: TimeInterval
    var spanEnd: TimeInterval
    var audioURL: URL
    var duration: TimeInterval
    var wordTimings: [WordTiming]
    /// The audio the quote was carved from. Temp — cleaned up when the capture
    /// flow is dismissed (caller-side cleanup). Non-optional; always present.
    var bufferAudioURL: URL
}

enum QuoteCaptureError: LocalizedError {
    case exportFailed
    case noSpeech
    /// The memo for the quote could not be created.
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .saveFailed:
            return "Couldn’t build that quote — try a different selection"
        case .exportFailed:
            return "Couldn’t extract that span from the book’s audio."
        case .noSpeech:
            return "No speech was recognized in that span — adjust the markers and try again."
        }
    }
}

/// Quote-capture output builders: transcribe a window on demand (never the
/// whole book), then cut the chosen sentences to a quote clip.
@MainActor
struct QuoteCaptureProcessor {
    var transcriber: any Transcribing = TranscriberFactory.make()

    // MARK: - Text capture: transcribe a window for the sentence-select screen

    /// A transcribed playhead window for `TextCaptureView` — the sentences to
    /// show + the temp audio kept alive (for the 1.5× preview). Times in
    /// `sentences` are LOCAL to `bufferURL` (0 = `windowStart`, file-local).
    struct WindowTranscript: Sendable {
        var sentences: [BufferSentence]
        var bufferURL: URL
        /// File-local start of the window — add to a sentence's local time to get
        /// file-local time; add the file's global origin for book time.
        var windowStart: TimeInterval
    }

    /// Transcribe `[windowStart, windowEnd]` (FILE-LOCAL) of `bookAudio` and
    /// return its sentences for the text-capture select screen. The caller
    /// owns `bufferURL`'s lifetime (clean up on dismiss) — it's reused for the
    /// in-screen preview. The user's selection goes to `buildOutput(from:...)`.
    func transcribeWindowForDisplay(bookAudio: URL,
                                    windowStart: TimeInterval,
                                    windowEnd: TimeInterval) async throws -> WindowTranscript {
        let bufferURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("textwin_\(UUID().uuidString).m4a")
        try await Self.exportSpan(of: bookAudio, start: windowStart, end: windowEnd, to: bufferURL)
        let result = try await transcriber.transcribe(audioURL: bufferURL, imageManifest: [])
        // No pre-snap — the view pre-selects the last sentence and the user adjusts.
        let sentences = Self.buildSentences(from: result.wordTimings)
        return WindowTranscript(sentences: sentences, bufferURL: bufferURL, windowStart: windowStart)
    }

    /// Build a capture output DIRECTLY from a text-mode window selection — NO
    /// re-transcription (the window was already transcribed for display, and the
    /// user picked whole sentences, so there's nothing to re-snap). Exports the
    /// selected sentences' span from the window buffer as the quote audio. This is
    /// why text mode skips the trim sheet: the quote is already sentence-exact.
    func buildOutput(from window: WindowTranscript, lo: Int, hi: Int,
                     fileOrigin: TimeInterval) async throws -> QuoteCaptureOutput {
        // Sentence times are window-local; book time = local + window start + file origin.
        try await buildSelectionOutput(
            sentences: window.sentences, lo: lo, hi: hi, audio: window.bufferURL,
            bookOffset: window.windowStart + fileOrigin, bufferAudioURL: window.bufferURL)
    }

    /// Wave-2 INSTANT capture: build the output from sidecar sentences (whose
    /// times are FILE-LOCAL — there is no per-capture window buffer). The quote
    /// audio is exported straight from the book file (design §2), and
    /// `bufferAudioURL` self-references the quote temp: text mode skips trim so
    /// it's never re-read, and the saver MOVES the quote away, so the flow's
    /// cleanup of that (now-absent) path is a harmless no-op. Crucially we never
    /// hand the BOOK FILE as `bufferAudioURL` — the flow deletes it on dismiss.
    func buildOutputFromSidecar(bookAudio: URL, sentences: [BufferSentence],
                                lo: Int, hi: Int, fileOrigin: TimeInterval) async throws -> QuoteCaptureOutput {
        try await buildSelectionOutput(
            sentences: sentences, lo: lo, hi: hi, audio: bookAudio,
            bookOffset: fileOrigin, bufferAudioURL: nil)
    }

    /// The shared bounds/slice/export/rebase block of both builders: validate
    /// `lo...hi`, carve the selected sentences' span out of `audio` (the same
    /// time basis as `sentences`), blockquote their text, and rebase their word
    /// timings to the new clip's t = 0. `bookOffset` maps the sentences' time
    /// basis to BOOK time. `bufferAudioURL` nil → the quote temp itself.
    private func buildSelectionOutput(
        sentences: [BufferSentence], lo: Int, hi: Int, audio: URL,
        bookOffset: TimeInterval, bufferAudioURL: URL?
    ) async throws -> QuoteCaptureOutput {
        guard sentences.indices.contains(lo), sentences.indices.contains(hi), lo <= hi else {
            throw QuoteCaptureError.noSpeech
        }
        let selected = Array(sentences[lo...hi])
        let selStart = selected[0].start
        let selEnd = selected[selected.count - 1].end
        guard selEnd > selStart else { throw QuoteCaptureError.noSpeech }

        let quoteURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("quote_\(UUID().uuidString).m4a")
        try await Self.exportSpan(of: audio, start: selStart, end: selEnd, to: quoteURL)

        let quote = QuoteFormatting.blockquote(selected.map(\.text).joined(separator: " "))
        let rebased = selected.flatMap(\.words).map {
            WordTiming(word: $0.word, start: max(0, $0.start - selStart), end: max(0, $0.end - selStart))
        }
        return QuoteCaptureOutput(
            quote: quote,
            spanStart: selStart + bookOffset, spanEnd: selEnd + bookOffset,
            audioURL: quoteURL,
            duration: max(0, selEnd - selStart),
            wordTimings: rebased,
            bufferAudioURL: bufferAudioURL ?? quoteURL
        )
    }

    /// Partition word timings into sentences.
    nonisolated static func buildSentences(from words: [WordTiming]) -> [BufferSentence] {
        guard !words.isEmpty else { return [] }
        let starts = SentenceSnap.sentenceStartIndices(words)
        var sentences: [BufferSentence] = []
        for (i, startIdx) in starts.enumerated() {
            let endIdx = i + 1 < starts.count ? starts[i + 1] - 1 : words.count - 1
            guard startIdx <= endIdx else { continue }
            let slice = Array(words[startIdx...endIdx])
            let sStart = slice[0].start
            let sEnd = slice[slice.count - 1].end
            let text = slice.map(\.word).joined(separator: " ")
            sentences.append(BufferSentence(text: text, start: sStart, end: sEnd, words: slice))
        }
        return sentences
    }

    /// Export `[start → end]` of `url`’s audio to an .m4a at `dest`
    /// (`AVAssetExportSession` with a `timeRange` — the only part of the book
    /// that’s ever read).
    static func exportSpan(of url: URL, start: TimeInterval, end: TimeInterval, to dest: URL) async throws {
        // Precise timing is load-bearing: the book audio is often a VBR MP3,
        // and the carved span's word-times must align to the source for the
        // read-along sidecar. Without the key the timeRange maps to imprecise
        // sample positions and the captured quote drifts late.
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        guard end > start,
              let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw QuoteCaptureError.exportFailed
        }
        export.timeRange = CMTimeRange(
            start: CMTime(seconds: max(0, start), preferredTimescale: 600),
            end: CMTime(seconds: end, preferredTimescale: 600)
        )
        try? FileManager.default.removeItem(at: dest)
        do {
            try await export.export(to: dest, as: .m4a)
        } catch {
            print("[Skrift] Quote span export failed: \(error)")
            throw QuoteCaptureError.exportFailed
        }
    }
}
