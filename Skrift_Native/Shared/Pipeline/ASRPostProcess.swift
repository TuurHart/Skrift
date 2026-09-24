import Foundation

/// The deterministic tail EVERY transcription shares, on both apps: phantom guard →
/// BPE token merge → optional custom-vocab rescore (+ re-align) → word timings →
/// `[[img_NNN]]` markers.
///
/// **Why this exists.** The engine itself (FluidAudio/Parakeet) and every individual
/// rule here were already single-sourced — `BPEMerge`, `AudioRMS`, `ImageMarkers`,
/// `TranscribingContract`. What was still twinned was the ORCHESTRATION: the same
/// ~35 lines, in the same order, in each app's `TranscriptionService`. That's the
/// drift-prone part, because the ORDER is load-bearing and invisible: the vocab
/// rescore must run BEFORE markers (so markers land against corrected words), the
/// phantom guard must run BEFORE any of it (a silent file has no words to place), and
/// the re-align must follow the rescore or timings detach from their words. A future
/// change to one app's order would not look like a bug in a diff.
///
/// Deliberately FluidAudio-free: it takes the neutral `RawToken`/`TimedWord` types, so
/// it compiles into the host-less test bundle (which never links the engine) and can be
/// tested on plain values — the same reason `BPEMerge` has its own token type.
enum ASRPostProcess {

    /// Run the tail. `rms` and `rescore` are closures so the heavy work stays lazy and
    /// app-specific: RMS decodes the whole file and is only consulted for a suspiciously
    /// tiny transcript, and the rescore needs each app's own engine-typed token timings
    /// plus its own word source (the Mac's Settings list, the phone's synced store).
    ///
    /// `rescore` returns the corrected text, or nil for "no change / not applicable".
    static func finish(rawText: String,
                       tokens: [RawToken],
                       confidence: Double,
                       durationMs: Int,
                       imageManifest: [ImageManifestEntry] = [],
                       rms: () -> Float?,
                       rescore: (String) async -> String?) async -> TranscriptionResult {
        // 1. Silence/phantom guard FIRST — a near-silent file yields a hallucinated
        //    word or two, and nothing downstream should run on it.
        if BPEMerge.shouldDropAsPhantom(text: rawText, rms: rms) {
            return TranscriptionResult(text: "", confidence: confidence,
                                       durationMs: durationMs, wordTimings: [],
                                       markersInjected: false)
        }

        var words = BPEMerge.mergeBPETokens(tokens)
        var text = rawText

        // 2. Custom-vocabulary rescore, BEFORE markers so markers are placed against
        //    the corrected words. Re-align so each timing keeps its word.
        if let boosted = await rescore(text) {
            text = boosted
            if let aligned = BPEMerge.alignWords(original: words.map(\.text),
                                                 rescoredText: boosted) {
                words = zip(words, aligned).map {
                    TimedWord(text: $1, start: $0.start, end: $0.end)
                }
            }
        }

        let wordTimings = words.map { WordTiming(word: $0.text, start: $0.start, end: $0.end) }

        // 3. Photo markers last — they need final words to anchor to. Body v2 (C10): the
        //    speech body is committed once, here, so a picture is its own paragraph from
        //    the start (no v1 inline marker + later snap).
        var markersInjected = false
        if !imageManifest.isEmpty, !words.isEmpty {
            text = BodyV2.committed(BodyV2.Input(text: text, words: wordTimings, manifest: imageManifest,
                                                 source: .speech))
            markersInjected = true
        }
        return TranscriptionResult(text: text, confidence: confidence, durationMs: durationMs,
                                   wordTimings: wordTimings, markersInjected: markersInjected)
    }
}
