import Foundation
import AVFoundation
import CoreML
import FluidAudio
import os

enum ASRError: LocalizedError {
    case notInitialized
    var errorDescription: String? { "ASR model is not loaded." }
}

/// On-device transcription via FluidAudio (Parakeet TDT v3). Models download from
/// HuggingFace on first use (~600 MB) and cache locally — matching the app's
/// HF-download distribution. Lives in `Engines/` (app target only) so FluidAudio
/// stays out of the host-less logic test target; the deterministic post-processing
/// (BPEMerge / ImageMarkers) is tested separately. Mirrors Shhhcribble + the phone's
/// TranscriptionService on FluidAudio `main`.
actor TranscriptionService: Transcribing {
    static let shared = TranscriptionService()

    private var asr: AsrManager?
    private var models: AsrModels?
    private var loadTask: Task<Void, Error>?
    private var isTranscribing = false

    /// Nonisolated, thread-safe mirror of `isModelReady` so the synchronous /health
    /// handler can read it without hopping onto the actor. Kept in sync with `asr`.
    private let ready = OSAllocatedUnfairLock(initialState: false)
    nonisolated var isModelReadySync: Bool { ready.withLock { $0 } }

    private init() {}

    var isModelReady: Bool { asr != nil }

    /// Load Parakeet v3 (multilingual incl. EN+NL). First call downloads from HF.
    func ensureLoaded(onProgress: @Sendable @escaping (Double) -> Void = { _ in }) async throws {
        if asr != nil { return }
        if let loadTask { try await loadTask.value; return }
        let task = Task<Void, Error> {
            let cfg = MLModelConfiguration()
            cfg.computeUnits = .cpuAndNeuralEngine
            let loaded = try await AsrModels.downloadAndLoad(configuration: cfg, version: .v3,
                                                             progressHandler: { onProgress($0.fractionCompleted) })
            let manager = AsrManager(config: .default)
            try await manager.loadModels(loaded)
            self.models = loaded
            self.asr = manager
            self.ready.withLock { $0 = true }
        }
        loadTask = task
        do { try await task.value; loadTask = nil }
        catch { loadTask = nil; throw error }
    }

    func unload() {
        guard !isTranscribing, loadTask == nil else { return }
        let manager = asr
        asr = nil
        models = nil
        ready.withLock { $0 = false }
        Task { await manager?.cleanup() }
    }

    func transcribe(audioURL: URL, imageManifest: [ImageManifestEntry] = []) async throws -> TranscriptionResult {
        isTranscribing = true
        defer { isTranscribing = false }
        try await ensureLoaded()
        guard let asr else { throw ASRError.notInitialized }

        let inputURL = Self.preprocessed(audioURL) ?? audioURL   // high-pass + normalize, else original
        let started = Date()
        var state = TdtDecoderState.make()
        let result = try await asr.transcribe(inputURL, decoderState: &state)
        let ms = Int(Date().timeIntervalSince(started) * 1000)

        // RMS decodes the entire file and is only consulted for tiny transcripts —
        // the shared guard computes it lazily (on the ORIGINAL, not the preprocessed file).
        if BPEMerge.shouldDropAsPhantom(text: result.text, rms: { AudioRMS.averageRMS(url: audioURL) }) {
            return TranscriptionResult(text: "", confidence: Double(result.confidence),
                                       durationMs: ms, wordTimings: [], markersInjected: false)
        }

        let raw = (result.tokenTimings ?? []).map {
            RawToken(token: $0.token, startTime: $0.startTime, endTime: $0.endTime)
        }
        var words = BPEMerge.mergeBPETokens(raw)
        var text = result.text

        // Custom-vocabulary rescore (Settings → Custom words). No-op without
        // words; never fails the transcription. Runs against the ORIGINAL audio
        // (the spotter resamples itself) and before image markers so markers
        // are placed against the corrected words.
        let customWords = SettingsStore.shared.load().customWords
        if !customWords.isEmpty,
           let boosted = await VocabularyBooster.shared.boost(
               text: text, tokenTimings: result.tokenTimings ?? [],
               audioURL: audioURL, words: customWords) {
            text = boosted.text
            if let aligned = BPEMerge.alignWords(original: words.map(\.text),
                                                 rescoredText: boosted.text) {
                words = zip(words, aligned).map {
                    TimedWord(text: $1, start: $0.start, end: $0.end)
                }
            }
        }

        let wordTimings = words.map { WordTiming(word: $0.text, start: $0.start, end: $0.end) }

        var markersInjected = false
        if !imageManifest.isEmpty, !words.isEmpty {
            text = ImageMarkers.insert(transcript: text, words: words, manifest: imageManifest)
            markersInjected = true
        }
        return TranscriptionResult(text: text, confidence: Double(result.confidence),
                                   durationMs: ms, wordTimings: wordTimings, markersInjected: markersInjected)
    }

    /// High-pass + normalize the original into a 16 kHz mono `processed.wav` next to
    /// it, per the user's `highpassFreqHz` setting (the afftdn denoiser has no native
    /// equivalent and was dropped — see A4). Returns nil (→ transcribe the original)
    /// when the high-pass is off or preprocessing fails.
    private static func preprocessed(_ original: URL) -> URL? {
        let hp = SettingsStore.shared.load().highpassFreqHz
        guard hp > 0 else { return nil }
        let out = original.deletingLastPathComponent().appendingPathComponent("processed.wav")
        return AudioPreprocessor.process(input: original, output: out, highpassHz: hp) ? out : nil
    }

}
