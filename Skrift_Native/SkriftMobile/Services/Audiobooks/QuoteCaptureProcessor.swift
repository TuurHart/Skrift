import AVFoundation
import Foundation

/// Sentences derived from the buffer transcript for sentence-level trimming on
/// the capture sheet. Times are LOCAL to the buffer audio (not the book).
struct BufferSentence: Sendable, Equatable {
    var text: String
    /// First word timing (buffer-local time).
    var start: TimeInterval
    /// Last word timing (buffer-local time).
    var end: TimeInterval
    /// Slice of word timings for this sentence (buffer-local).
    var words: [WordTiming]
    /// Whether this sentence falls within the initially snapped span
    /// (true → starts "in" the quote; false → context-only on first render).
    var isInInitialSpan: Bool
}

/// The result of processing one confirmed capture span: the sentence-snapped
/// quote, its trimmed audio (a temp .m4a the saver moves into recordings), and
/// the word timings rebased onto that trimmed audio (karaoke sidecar).
///
/// The buffer audio URL and sentences are retained for sentence-level trimming
/// on the capture sheet — they are temp files whose lifetime is tied to the
/// capture flow. The saver must NOT use them; it always uses `audioURL`.
struct QuoteCaptureOutput: Sendable {
    var quote: String
    /// Snapped span in BOOK time (for the "12:05 → 12:38" label + chapter lookup).
    var spanStart: TimeInterval
    var spanEnd: TimeInterval
    var audioURL: URL
    var duration: TimeInterval
    var wordTimings: [WordTiming]

    // MARK: - Sentence-trim data (retained for the capture sheet)

    /// All sentences found in the ±20 s buffer, in order. The capture sheet
    /// shows these as tappable segments (bright = in, grey = context).
    /// Empty when the engine returned no word timings.
    var bufferSentences: [BufferSentence]
    /// The buffer audio file (span ± 20 s). Temp — cleaned up when the capture
    /// flow is dismissed (the `defer` in `QuoteCaptureProcessor.process` is
    /// replaced by caller-side cleanup). Non-optional; always present.
    var bufferAudioURL: URL
    /// Time offset of the buffer's start relative to FILE-LOCAL time.
    /// `bufferLocalTime + bufferOffset = fileLocalTime`.
    var bufferOffset: TimeInterval
}

enum QuoteCaptureError: LocalizedError {
    case exportFailed
    case noSpeech

    var errorDescription: String? {
        switch self {
        case .exportFailed:
            return "Couldn’t extract that span from the book’s audio."
        case .noSpeech:
            return "No speech was recognized in that span — adjust the markers and try again."
        }
    }
}

/// Span-on-demand transcription (LOCKED: never the whole book): export the
/// marked span ± 20 s to a temp file, run it through the existing on-device
/// `Transcriber` (Parakeet), sentence-snap both edges OUTWARD, then trim the
/// quote audio to the snapped span.
///
/// Times here are LOCAL to `bookAudio` — for a multi-file book the flow passes
/// the ONE file the capture falls in (`bookDuration` = that file's length) and
/// a span already rebased into it; a span can never cross a file boundary.
@MainActor
struct QuoteCaptureProcessor {
    var transcriber: any Transcriber = TranscriberFactory.make()

    func process(bookAudio: URL, span: CaptureSpan.Span, bookDuration: TimeInterval) async throws -> QuoteCaptureOutput {
        let buffer = CaptureSpan.transcriptionBuffer(for: span, duration: bookDuration)
        let tempDir = FileManager.default.temporaryDirectory
        let bufferURL = tempDir.appendingPathComponent("quotebuf_\(UUID().uuidString).m4a")
        // NOTE: bufferURL is NOT deferred-removed here — the capture sheet
        // needs it for sentence-level audio re-trimming. The caller
        // (QuoteCaptureFlowView) removes it on dismiss.

        try await Self.exportSpan(of: bookAudio, start: buffer.start, end: buffer.end, to: bufferURL)

        let result = try await transcriber.transcribe(audioURL: bufferURL, imageManifest: [])

        // Marker times relative to the buffered audio.
        let relIn = span.start - buffer.start
        let relOut = span.end - buffer.start

        let snapped: SentenceSnap.Snapped
        if let s = SentenceSnap.snap(words: result.wordTimings, proposedIn: relIn, proposedOut: relOut) {
            snapped = s
        } else {
            // No word timings (e.g. an engine without timings) — keep the raw
            // span and the whole recognized text rather than failing.
            let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            snapped = SentenceSnap.Snapped(start: relIn, end: relOut, text: text, words: [])
        }
        guard !snapped.text.isEmpty else {
            try? FileManager.default.removeItem(at: bufferURL)
            throw QuoteCaptureError.noSpeech
        }

        // Trim the quote audio to the snapped span (from the small buffer file,
        // not the whole book).
        let quoteURL = tempDir.appendingPathComponent("quote_\(UUID().uuidString).m4a")
        try await Self.exportSpan(of: bufferURL, start: snapped.start, end: snapped.end, to: quoteURL)

        // Rebase timings onto the trimmed audio (t = 0 at the snapped start).
        let rebased = snapped.words.map {
            WordTiming(word: $0.word, start: max(0, $0.start - snapped.start), end: max(0, $0.end - snapped.start))
        }

        // Build the sentence list for the trim sheet from buffer-local word timings.
        let bufferSentences = Self.buildSentences(
            from: result.wordTimings,
            snappedStart: snapped.start,
            snappedEnd: snapped.end
        )

        return QuoteCaptureOutput(
            quote: snapped.text,
            spanStart: buffer.start + snapped.start,
            spanEnd: buffer.start + snapped.end,
            audioURL: quoteURL,
            duration: max(0, snapped.end - snapped.start),
            wordTimings: rebased,
            bufferSentences: bufferSentences,
            bufferAudioURL: bufferURL,
            bufferOffset: buffer.start
        )
    }

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
    /// return its sentences for the text-capture select screen. Reuses the same
    /// export + transcribe + sentence-partition path as `process`. The caller
    /// owns `bufferURL`'s lifetime (clean up on dismiss) — it's reused for the
    /// in-screen preview. The selection the user makes becomes a span the flow
    /// runs through `process` exactly like the audio mode, so the downstream
    /// (sheet/save/sync/export) is untouched.
    func transcribeWindowForDisplay(bookAudio: URL,
                                    windowStart: TimeInterval,
                                    windowEnd: TimeInterval) async throws -> WindowTranscript {
        let bufferURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("textwin_\(UUID().uuidString).m4a")
        try await Self.exportSpan(of: bookAudio, start: windowStart, end: windowEnd, to: bufferURL)
        let result = try await transcriber.transcribe(audioURL: bufferURL, imageManifest: [])
        // No pre-snap — the view pre-selects the last sentence and the user
        // adjusts; isInInitialSpan is unused here (passed 0,0).
        let sentences = Self.buildSentences(from: result.wordTimings, snappedStart: 0, snappedEnd: 0)
        return WindowTranscript(sentences: sentences, bufferURL: bufferURL, windowStart: windowStart)
    }

    /// Build a capture output DIRECTLY from a text-mode window selection — NO
    /// re-transcription (the window was already transcribed for display, and the
    /// user picked whole sentences, so there's nothing to re-snap). Exports the
    /// selected sentences' span from the window buffer as the quote audio. This is
    /// why text mode skips the trim sheet: the quote is already sentence-exact.
    func buildOutput(from window: WindowTranscript, lo: Int, hi: Int,
                     fileOrigin: TimeInterval) async throws -> QuoteCaptureOutput {
        guard window.sentences.indices.contains(lo), window.sentences.indices.contains(hi), lo <= hi,
              let bookSpan = TextCaptureMath.globalSpan(
                sentences: window.sentences, lo: lo, hi: hi,
                windowStart: window.windowStart, fileOrigin: fileOrigin)
        else { throw QuoteCaptureError.noSpeech }

        let selected = Array(window.sentences[lo...hi])
        let selStart = selected[0].start                 // window-local
        let selEnd = selected[selected.count - 1].end
        guard selEnd > selStart else { throw QuoteCaptureError.noSpeech }

        // Quote audio = the selected span carved from the window buffer.
        let quoteURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("quote_\(UUID().uuidString).m4a")
        try await Self.exportSpan(of: window.bufferURL, start: selStart, end: selEnd, to: quoteURL)

        let quote = QuoteFormatting.blockquote(selected.map(\.text).joined(separator: " "))
        let rebased = selected.flatMap(\.words).map {
            WordTiming(word: $0.word, start: max(0, $0.start - selStart), end: max(0, $0.end - selStart))
        }
        return QuoteCaptureOutput(
            quote: quote,
            spanStart: bookSpan.start, spanEnd: bookSpan.end,
            audioURL: quoteURL,
            duration: max(0, selEnd - selStart),
            wordTimings: rebased,
            bufferSentences: window.sentences,   // retained; trim is skipped for text captures
            bufferAudioURL: window.bufferURL,
            bufferOffset: window.windowStart
        )
    }

    /// Partition buffer word timings into sentences, marking each as initially
    /// "in" the quote if it overlaps the snapped span.
    nonisolated static func buildSentences(
        from words: [WordTiming],
        snappedStart: TimeInterval,
        snappedEnd: TimeInterval
    ) -> [BufferSentence] {
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
            // A sentence is "in" if its time window overlaps the snapped span.
            let isIn = sEnd > snappedStart && sStart < snappedEnd
            sentences.append(BufferSentence(
                text: text,
                start: sStart,
                end: sEnd,
                words: slice,
                isInInitialSpan: isIn
            ))
        }
        return sentences
    }

    // MARK: - Apply trim (sentence-level, from the capture sheet)

    /// The result of `applyTrim` — everything the sheet needs to update the
    /// memo's audio file, transcript, duration, and word-timings sidecar.
    struct TrimResult: Sendable {
        /// New audio (a temp .m4a); caller moves it onto the memo's audio file
        /// (same filename, atomic replace) and removes this temp on failure.
        let audioURL: URL
        /// New C1 blockquote transcript (included sentence text joined and
        /// wrapped in "> " markers).
        let transcript: String
        /// New duration (seconds), equal to `spanEnd - spanStart`.
        let duration: TimeInterval
        /// Word timings rebased to the new audio’s t = 0.
        let wordTimings: [WordTiming]
    }

    /// Re-derive the memo’s audio, transcript, and word timings from the
    /// user’s sentence-trim choices.
    ///
    /// - Parameters:
    ///   - output:          The original `QuoteCaptureOutput` from the flow.
    ///   - included:        One flag per `output.bufferSentences`. Must have
    ///                      the same count; at least one must be `true`.
    ///   - initialIncluded: The original flags (`.isInInitialSpan`) used for
    ///                      the no-op check. When equal to `included`, returns
    ///                      `nil` — nothing to do.
    ///
    /// Reads from `output.bufferAudioURL` (the ±20 s buffer kept
    /// alive by the capture flow for exactly this purpose).
    /// `@MainActor` so it can call `exportSpan` (which inherits MainActor
    /// from the struct). The CPU work is negligible; the actual audio export
    /// suspends on the background AVAssetExportSession queue.
    static func applyTrim(
        output: QuoteCaptureOutput,
        included: [Bool],
        initialIncluded: [Bool]
    ) async throws -> TrimResult? {
        guard included.count == output.bufferSentences.count else { return nil }

        // No-op when nothing changed from the initial snap.
        if included == initialIncluded { return nil }

        // Build the active sentence list.
        let active = zip(output.bufferSentences, included)
            .filter(\.1).map(\.0)
        guard !active.isEmpty else { return nil }

        // Audio span in buffer-local time (BufferSentence.start/end are
        // local to bufferAudioURL, so no offset adjustment needed).
        let spanStart = active[0].start
        let spanEnd   = active[active.count - 1].end
        guard spanEnd > spanStart else { return nil }

        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("trim_\(UUID().uuidString).m4a")
        try await exportSpan(of: output.bufferAudioURL,
                             start: spanStart, end: spanEnd, to: dest)
        let newDuration = max(0, spanEnd - spanStart)

        // Transcript: join included sentence text and wrap in "> " blockquote.
        let joined = active.map(\.text).joined(separator: " ")
        let newTranscript = QuoteFormatting.blockquote(joined)

        // Word timings: collect from all included sentences, rebase to t = 0.
        let allWords = active.flatMap(\.words)
        let newTimings = allWords.map {
            WordTiming(word: $0.word,
                       start: max(0, $0.start - spanStart),
                       end:   max(0, $0.end   - spanStart))
        }

        return TrimResult(
            audioURL:   dest,
            transcript: newTranscript,
            duration:   newDuration,
            wordTimings: newTimings
        )
    }

    /// Returns `true` when `included` exactly matches the initial sentence-snap
    /// state (i.e. trim has not changed). Pure — safe in tests.
    nonisolated static func isUnchangedTrim(
        included: [Bool],
        sentences: [BufferSentence]
    ) -> Bool {
        guard included.count == sentences.count else { return true }
        return zip(included, sentences).allSatisfy { flag, s in flag == s.isInInitialSpan }
    }

    /// Export `[start → end]` of `url`’s audio to an .m4a at `dest`
    /// (`AVAssetExportSession` with a `timeRange` — the only part of the book
    /// that’s ever read).
    static func exportSpan(of url: URL, start: TimeInterval, end: TimeInterval, to dest: URL) async throws {
        let asset = AVURLAsset(url: url)
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
