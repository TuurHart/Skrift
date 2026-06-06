import Foundation
import AVFoundation
import CoreML
import FluidAudio

/// Result of transcribing one file. `text` carries `[[img_NNN]]` markers when a
/// photo manifest was supplied; `wordTimings` feed the per-file sidecar + karaoke.
struct TranscriptionResult: Sendable {
    let text: String
    let confidence: Double
    let durationMs: Int
    let wordTimings: [WordTiming]
    let markersInjected: Bool
}

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
actor TranscriptionService {
    static let shared = TranscriptionService()

    private var asr: AsrManager?
    private var models: AsrModels?
    private var loadTask: Task<Void, Error>?
    private var isTranscribing = false

    private init() {}

    var isModelReady: Bool { asr != nil }

    /// Load Parakeet v3 (multilingual incl. EN+NL). First call downloads from HF.
    func ensureLoaded() async throws {
        if asr != nil { return }
        if let loadTask { try await loadTask.value; return }
        let task = Task<Void, Error> {
            let cfg = MLModelConfiguration()
            cfg.computeUnits = .cpuAndNeuralEngine
            let loaded = try await AsrModels.downloadAndLoad(configuration: cfg, version: .v3, progressHandler: { _ in })
            let manager = AsrManager(config: .default)
            try await manager.loadModels(loaded)
            self.models = loaded
            self.asr = manager
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
        Task { await manager?.cleanup() }
    }

    func transcribe(audioURL: URL, imageManifest: [ImageManifestEntry] = []) async throws -> TranscriptionResult {
        isTranscribing = true
        defer { isTranscribing = false }
        try await ensureLoaded()
        guard let asr else { throw ASRError.notInitialized }

        let rms = Self.averageRMS(url: audioURL)
        let started = Date()
        var state = TdtDecoderState.make()
        let result = try await asr.transcribe(audioURL, decoderState: &state)
        let ms = Int(Date().timeIntervalSince(started) * 1000)

        let trimmed = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let wordCount = trimmed.isEmpty
            ? 0
            : trimmed.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).count
        if BPEMerge.shouldDropAsPhantom(rms: rms, wordCount: wordCount, isEmpty: trimmed.isEmpty) {
            return TranscriptionResult(text: "", confidence: Double(result.confidence),
                                       durationMs: ms, wordTimings: [], markersInjected: false)
        }

        let raw = (result.tokenTimings ?? []).map {
            RawToken(token: $0.token, startTime: $0.startTime, endTime: $0.endTime)
        }
        let words = BPEMerge.mergeBPETokens(raw)
        let wordTimings = words.map { WordTiming(word: $0.text, start: $0.start, end: $0.end) }

        var text = result.text
        var markersInjected = false
        if !imageManifest.isEmpty, !words.isEmpty {
            text = ImageMarkers.insert(transcript: text, words: words, manifest: imageManifest)
            markersInjected = true
        }
        return TranscriptionResult(text: text, confidence: Double(result.confidence),
                                   durationMs: ms, wordTimings: wordTimings, markersInjected: markersInjected)
    }

    /// Mean RMS amplitude across the file (chunked, never fully loaded). Drives the
    /// phantom-transcript guard. nil if unreadable.
    private static func averageRMS(url: URL) -> Float? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let cap: AVAudioFrameCount = 16384
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: cap) else { return nil }
        var sumSquares = 0.0
        var total = 0.0
        while (try? file.read(into: buffer, frameCount: cap)) != nil {
            let n = Int(buffer.frameLength)
            if n == 0 { break }
            guard let ch = buffer.floatChannelData else { break }
            let s = ch[0]
            var i = 0
            while i < n { let v = Double(s[i]); sumSquares += v * v; i += 1 }
            total += Double(n)
        }
        return total == 0 ? nil : Float((sumSquares / total).squareRoot())
    }
}
