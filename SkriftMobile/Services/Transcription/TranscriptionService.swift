import AVFoundation
import CoreML
import FluidAudio
import Foundation
import UIKit

/// Result of transcribing one memo. `wordTimings` go to the per-memo sidecar;
/// `text` carries `[[img_NNN]]` markers when a photo manifest was supplied.
struct TranscriptionResult: Sendable {
    let text: String
    let confidence: Double
    let durationMs: Int
    let wordTimings: [WordTiming]
    let markersInjected: Bool
}

/// Abstraction so the recording flow can be driven by a seeded transcript in UI
/// tests (the Simulator has no Neural Engine and FluidAudio pulls ~600MB). The
/// real engine runs only on device.
protocol Transcriber: Sendable {
    func transcribe(audioURL: URL, imageManifest: [ImageManifestEntry]) async throws -> TranscriptionResult
}

extension Transcriber {
    func transcribe(audioURL: URL) async throws -> TranscriptionResult {
        try await transcribe(audioURL: audioURL, imageManifest: [])
    }
}

/// On-device ASR via FluidAudio (Parakeet TDT v3). Ported from the RN
/// `ParakeetModule.swift`, adapted to FluidAudio `main` (`loadModels`,
/// `transcribe(url, decoderState:)`, `ASRResult.tokenTimings`). Carries the two
/// native fixes from the RN module: model teardown on memory pressure, and the
/// RMS/word-count silence guard. The BPE→word merge + `[[img_NNN]]` insertion are
/// bit-for-bit ports of the desktop `_insert_image_markers`.
actor TranscriptionService: Transcriber {
    static let shared = TranscriptionService()

    private var asr: AsrManager?
    private var models: AsrModels?
    private var loadTask: Task<Void, Error>?
    private var isTranscribing = false
    private var memoryObserver: NSObjectProtocol?

    private init() {}

    var isModelReady: Bool { asr != nil }

    // MARK: - Model lifecycle

    func ensureLoaded() async throws {
        installMemoryObserverIfNeeded()
        if asr != nil { return }
        if let loadTask {
            try await loadTask.value
            return
        }
        let task = Task<Void, Error> {
            let mlConfig = MLModelConfiguration()
            let useANE = UserDefaults.standard.object(forKey: "useANE") as? Bool ?? true
            mlConfig.computeUnits = useANE ? .cpuAndNeuralEngine : .cpuOnly
            // v3 = multilingual (English + Dutch + 23 more). First call downloads
            // ~600MB from HuggingFace, cached locally thereafter.
            let loaded = try await AsrModels.downloadAndLoad(
                configuration: mlConfig,
                version: .v3,
                progressHandler: { _ in }
            )
            let manager = AsrManager(config: .default)
            try await manager.loadModels(loaded)
            self.models = loaded
            self.asr = manager
        }
        loadTask = task
        do {
            try await task.value
            loadTask = nil
        } catch {
            loadTask = nil
            throw error
        }
    }

    /// Release the ~600MB model + CoreML weights. No-op while transcribing or
    /// loading (the in-flight call holds its own reference). Reloads from the
    /// on-disk cache on the next transcribe.
    func unload() {
        guard !isTranscribing, loadTask == nil else { return }
        let manager = asr
        asr = nil
        models = nil
        Task { await manager?.cleanup() }
    }

    private func installMemoryObserverIfNeeded() {
        guard memoryObserver == nil else { return }
        memoryObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { await TranscriptionService.shared.unload() }
        }
    }

    // MARK: - Transcription

    func transcribe(audioURL: URL, imageManifest: [ImageManifestEntry]) async throws -> TranscriptionResult {
        isTranscribing = true
        defer { isTranscribing = false }
        try await ensureLoaded()
        guard let asr else {
            throw ASRError.notInitialized
        }

        let rms = Self.averageRMS(url: audioURL)
        let started = Date()
        var state = TdtDecoderState.make()
        let result = try await asr.transcribe(audioURL, decoderState: &state)
        let ms = Int(Date().timeIntervalSince(started) * 1000)

        // Silence/phantom guard: TDT can hallucinate a short phantom transcript on
        // (near-)silent audio. Drop empty, or tiny-AND-low-energy. Gated on a tiny
        // word count so real speech is never dropped. Threshold tuned on device.
        let trimmed = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let wordCount = trimmed.isEmpty
            ? 0
            : trimmed.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).count
        let lowEnergy = rms.map { $0 < 0.0075 } ?? false
        if trimmed.isEmpty || (lowEnergy && wordCount <= 3) {
            return TranscriptionResult(text: "", confidence: Double(result.confidence),
                                       durationMs: ms, wordTimings: [], markersInjected: false)
        }

        let words = Self.mergeBPETokens(result.tokenTimings ?? [])
        let wordTimings = words.map { WordTiming(word: $0.text, start: $0.start, end: $0.end) }

        var text = result.text
        var markersInjected = false
        if !imageManifest.isEmpty, !words.isEmpty {
            text = Self.insertImageMarkers(transcript: text, words: words, manifest: imageManifest)
            markersInjected = true
        }
        return TranscriptionResult(text: text, confidence: Double(result.confidence),
                                   durationMs: ms, wordTimings: wordTimings, markersInjected: markersInjected)
    }

    // MARK: - Helpers (ported verbatim from the RN ParakeetModule)

    private struct Word {
        let text: String
        let start: TimeInterval
        let end: TimeInterval
        var charStart: Int = 0
        var charEnd: Int = 0
    }

    /// Mean RMS amplitude across the file, chunked so a long recording is never
    /// fully loaded into memory. nil if unreadable.
    private static func averageRMS(url: URL) -> Float? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let format = file.processingFormat
        let frameCapacity: AVAudioFrameCount = 16384
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCapacity) else { return nil }
        var sumSquares: Double = 0
        var totalFrames: Double = 0
        while true {
            do {
                try file.read(into: buffer, frameCount: frameCapacity)
            } catch {
                break
            }
            let n = Int(buffer.frameLength)
            if n == 0 { break }
            guard let channels = buffer.floatChannelData else { break }
            let samples = channels[0]
            var i = 0
            while i < n {
                let s = Double(samples[i])
                sumSquares += s * s
                i += 1
            }
            totalFrames += Double(n)
        }
        if totalFrames == 0 { return nil }
        return Float((sumSquares / totalFrames).squareRoot())
    }

    /// Merge BPE sub-word tokens into whole words. A token whose raw text starts
    /// with a space begins a new word; others are continuations.
    private static func mergeBPETokens(_ tokens: [TokenTiming]) -> [Word] {
        var words: [Word] = []
        var pending: (text: String, start: TimeInterval, end: TimeInterval)?

        for token in tokens {
            let raw = token.token
            if raw.isEmpty { continue }
            let isNewWord = raw.hasPrefix(" ") || pending == nil
            let clean = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if clean.isEmpty { continue }
            let s = max(0.0, token.startTime)
            let e = max(s, token.endTime)

            if isNewWord {
                if let p = pending, !p.text.trimmingCharacters(in: .whitespaces).isEmpty {
                    words.append(Word(text: p.text.trimmingCharacters(in: .whitespaces), start: p.start, end: p.end))
                }
                pending = (text: clean, start: s, end: e)
            } else {
                pending?.text.append(clean)
                pending?.end = e
            }
        }
        if let p = pending, !p.text.trimmingCharacters(in: .whitespaces).isEmpty {
            words.append(Word(text: p.text.trimmingCharacters(in: .whitespaces), start: p.start, end: p.end))
        }
        return words
    }

    /// Insert `[[img_NNN]]` markers at the word whose start time is closest to each
    /// photo's offset. Works in UTF-16 indices (NSString) the whole way, matching
    /// the desktop `_insert_image_markers`. Numbering ascends by offset.
    private static func insertImageMarkers(transcript: String, words: [Word], manifest: [ImageManifestEntry]) -> String {
        guard !words.isEmpty, !manifest.isEmpty else { return transcript }

        var indexedWords = words
        let nsTranscript = transcript as NSString
        var scanPos = 0
        let totalLen = nsTranscript.length
        let totalDuration = max(1.0, words.last?.end ?? 1.0)

        for i in indexedWords.indices {
            let needle = indexedWords[i].text as NSString
            var found = -1
            if scanPos < totalLen {
                let searchRange = NSRange(location: scanPos, length: totalLen - scanPos)
                let r = nsTranscript.range(of: needle as String, options: [], range: searchRange)
                if r.location != NSNotFound {
                    found = r.location
                    indexedWords[i].charStart = found
                    indexedWords[i].charEnd = found + needle.length
                    scanPos = found + needle.length
                }
            }
            if found == -1 {
                let estimated = Int(Double(totalLen) * indexedWords[i].start / totalDuration)
                let clamped = min(max(0, estimated), totalLen)
                indexedWords[i].charStart = clamped
                indexedWords[i].charEnd = clamped
            }
        }

        let sortedManifest = manifest.sorted { $0.offsetSeconds < $1.offsetSeconds }
        var insertions: [(pos: Int, marker: String)] = []
        for (i, entry) in sortedManifest.enumerated() {
            let offset = entry.offsetSeconds
            var bestIdx = 0
            var bestDiff = abs(indexedWords[0].start - offset)
            for (wi, w) in indexedWords.enumerated() {
                let diff = abs(w.start - offset)
                if diff < bestDiff {
                    bestDiff = diff
                    bestIdx = wi
                }
            }
            let pos = indexedWords[bestIdx].charEnd
            let marker = "\n\n[[img_\(String(format: "%03d", i + 1))]]\n\n"
            insertions.append((pos, marker))
        }

        var result = transcript
        for (pos, marker) in insertions.sorted(by: { $0.pos > $1.pos }) {
            let nsResult = result as NSString
            let safePos = min(max(0, pos), nsResult.length)
            let prefix = nsResult.substring(to: safePos)
            let suffix = nsResult.substring(from: safePos)
            result = prefix + marker + suffix
        }
        return result
    }
}

/// Deterministic transcriber for UI tests, fed by the `-seedTranscript` launch
/// arg. Produces evenly-spaced word timings so the sidecar + downstream code see
/// a realistic shape without the Neural Engine.
struct SeededTranscriber: Transcriber {
    let text: String

    func transcribe(audioURL: URL, imageManifest: [ImageManifestEntry]) async throws -> TranscriptionResult {
        let pieces = text.split(separator: " ")
        let words = pieces.enumerated().map { index, word in
            WordTiming(word: String(word), start: Double(index) * 0.3, end: Double(index) * 0.3 + 0.25)
        }
        return TranscriptionResult(text: text, confidence: 1.0, durationMs: 0,
                                   wordTimings: words, markersInjected: false)
    }
}

enum TranscriberFactory {
    /// Seeded in tests (`-seedTranscript`), real FluidAudio engine otherwise.
    static func make() -> any Transcriber {
        if let seed = LaunchFlags.seedTranscript {
            return SeededTranscriber(text: seed)
        }
        return TranscriptionService.shared
    }
}
