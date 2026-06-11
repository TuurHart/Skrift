import AVFoundation
import Foundation

/// The result of processing one confirmed capture span: the sentence-snapped
/// quote, its trimmed audio (a temp .m4a the saver moves into recordings), and
/// the word timings rebased onto that trimmed audio (karaoke sidecar).
struct QuoteCaptureOutput: Sendable {
    var quote: String
    /// Snapped span in BOOK time (for the "12:05 → 12:38" label + chapter lookup).
    var spanStart: TimeInterval
    var spanEnd: TimeInterval
    var audioURL: URL
    var duration: TimeInterval
    var wordTimings: [WordTiming]
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
@MainActor
struct QuoteCaptureProcessor {
    var transcriber: any Transcriber = TranscriberFactory.make()

    func process(bookAudio: URL, span: CaptureSpan.Span, bookDuration: TimeInterval) async throws -> QuoteCaptureOutput {
        let buffer = CaptureSpan.transcriptionBuffer(for: span, duration: bookDuration)
        let tempDir = FileManager.default.temporaryDirectory
        let bufferURL = tempDir.appendingPathComponent("quotebuf_\(UUID().uuidString).m4a")
        defer { try? FileManager.default.removeItem(at: bufferURL) }

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
        guard !snapped.text.isEmpty else { throw QuoteCaptureError.noSpeech }

        // Trim the quote audio to the snapped span (from the small buffer file,
        // not the whole book).
        let quoteURL = tempDir.appendingPathComponent("quote_\(UUID().uuidString).m4a")
        try await Self.exportSpan(of: bufferURL, start: snapped.start, end: snapped.end, to: quoteURL)

        // Rebase timings onto the trimmed audio (t = 0 at the snapped start).
        let rebased = snapped.words.map {
            WordTiming(word: $0.word, start: max(0, $0.start - snapped.start), end: max(0, $0.end - snapped.start))
        }

        return QuoteCaptureOutput(
            quote: snapped.text,
            spanStart: buffer.start + snapped.start,
            spanEnd: buffer.start + snapped.end,
            audioURL: quoteURL,
            duration: max(0, snapped.end - snapped.start),
            wordTimings: rebased
        )
    }

    /// Export `[start → end]` of `url`'s audio to an .m4a at `dest`
    /// (`AVAssetExportSession` with a `timeRange` — the only part of the book
    /// that's ever read).
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
