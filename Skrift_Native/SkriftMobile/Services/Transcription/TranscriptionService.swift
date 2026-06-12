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

    // Live streaming session state (record-screen captions). See the
    // "Live streaming" section below.
    private var streamBuffers: [AVAudioPCMBuffer] = []
    private var committedChunks: [String] = []
    private var streamStartedAt: Date?
    private var lastRotationAt: Date?
    private var rotating = false
    private var snapshotRunning = false
    private var streaming = false
    /// Force-commit the accumulated buffer to a committed chunk after this long,
    /// bounding live-buffer memory on long recordings (Shhhcribble uses a VAD
    /// speech-end trigger too; we keep just the time-based hard cap for now).
    private static let rotationInterval: TimeInterval = 25
    /// Hard ceiling on the live buffer (≈90 s at 48 kHz). `rotateIfNeeded`
    /// normally trims at 25 s, but it bails when the model isn't loaded — so
    /// this cap (enforced in `feedStream`, model-independent) stops the buffer
    /// running away while the model is downloading/loading or after a
    /// memory-warning `unload()`.
    private static let maxStreamFrames: AVAudioFrameCount = 48_000 * 90

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
            await MainActor.run { ModelLoadStatus.shared.set(.preparing(nil)) }
            let mlConfig = MLModelConfiguration()
            let useANE = UserDefaults.standard.object(forKey: "useANE") as? Bool ?? true
            mlConfig.computeUnits = useANE ? .cpuAndNeuralEngine : .cpuOnly
            // v3 = multilingual (English + Dutch + 23 more). First call downloads
            // ~600MB from HuggingFace, cached locally thereafter.
            let loaded = try await AsrModels.downloadAndLoad(
                configuration: mlConfig,
                version: .v3,
                progressHandler: { progress in
                    Task { @MainActor in
                        switch progress.phase {
                        case .downloading: ModelLoadStatus.shared.set(.downloading(progress.fractionCompleted))
                        // .compiling / .listing — surface as "Preparing N%" so the
                        // slow cold CoreML compile shows progress, not a frozen label.
                        default: ModelLoadStatus.shared.set(.preparing(progress.fractionCompleted))
                        }
                    }
                }
            )
            let manager = AsrManager(config: .default)
            try await manager.loadModels(loaded)
            self.models = loaded
            self.asr = manager
            await MainActor.run { ModelLoadStatus.shared.set(.ready) }
        }
        loadTask = task
        do {
            try await task.value
            loadTask = nil
        } catch {
            loadTask = nil
            await MainActor.run { ModelLoadStatus.shared.set(.failed) }
            throw error
        }
    }

    /// Release the ~600MB model + CoreML weights. No-op while transcribing or
    /// loading (the in-flight call holds its own reference). Reloads from the
    /// on-disk cache on the next transcribe.
    func unload() {
        guard !isTranscribing, !streaming, loadTask == nil else { return }
        let manager = asr
        asr = nil
        models = nil
        // Memory-pressure unload: the model is still cached on disk, so reflect
        // "will reload" rather than a false "not downloaded".
        Task { @MainActor in
            ModelLoadStatus.shared.set(ModelLoadStatus.shared.everDownloaded ? .preparing(nil) : .idle)
        }
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

        var words = Self.mergeBPETokens(result.tokenTimings ?? [])
        var text = result.text

        // Custom-vocabulary rescore (Settings → Custom words). No-op without
        // words; never fails the transcription. Runs BEFORE image markers so
        // markers are placed against the corrected words.
        if let boosted = await VocabularyBooster.shared.boost(
            text: text, tokenTimings: result.tokenTimings ?? [], audioURL: audioURL) {
            text = boosted.text
            if let aligned = VocabularyBooster.alignWords(original: words.map(\.text),
                                                          rescoredText: boosted.text) {
                words = zip(words, aligned).map {
                    ImageMarkers.TimedWord(text: $1, start: $0.start, end: $0.end)
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

    // MARK: - Helpers (ported verbatim from the RN ParakeetModule)

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
    private static func mergeBPETokens(_ tokens: [TokenTiming]) -> [ImageMarkers.TimedWord] {
        var words: [ImageMarkers.TimedWord] = []
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
                    words.append(ImageMarkers.TimedWord(text: p.text.trimmingCharacters(in: .whitespaces), start: p.start, end: p.end))
                }
                pending = (text: clean, start: s, end: e)
            } else {
                pending?.text.append(clean)
                pending?.end = e
            }
        }
        if let p = pending, !p.text.trimmingCharacters(in: .whitespaces).isEmpty {
            words.append(ImageMarkers.TimedWord(text: p.text.trimmingCharacters(in: .whitespaces), start: p.start, end: p.end))
        }
        return words
    }

    // MARK: - Live streaming (record-screen captions)
    //
    // A faithful port of Shhhcribble's `TextEngine` feed/liveSnapshot/finalize,
    // minus the VAD-triggered rotation (time-based hard cap only) and minus the
    // vocabulary/filler passes (Skrift sends the RAW transcript; the Mac
    // copy-edits). It shares the one loaded `asr` manager with the file path —
    // never a second model in memory. Calls into `asr.transcribe` serialise on
    // the AsrManager's own executor even when interleaved, so the snapshot +
    // rotation guards just avoid redundant work, not data races.
    //
    // DEVICE-OWED: the Simulator has no Neural Engine, so the record screen
    // drives a mock caption instead (see `LiveRecordingService`). This path is
    // only exercised on a physical device. The authoritative transcript (with
    // word timings + image markers) still comes from the one-shot file pass
    // after stop — the live caption is display-only.

    /// Begin a live session: clear prior state and kick off the model load so
    /// the first buffers transcribe as soon as it's ready.
    func beginStream() async {
        streamBuffers.removeAll(keepingCapacity: true)
        committedChunks.removeAll()
        streamStartedAt = Date()
        lastRotationAt = nil
        rotating = false
        streaming = true
        try? await ensureLoaded()
    }

    /// Append a captured buffer. The caller hands off an **owned** copy — the
    /// record tap copies off the audio thread before this actor hop, because the
    /// tap's backing storage is reused under us.
    func feedStream(_ ownedBuffer: AVAudioPCMBuffer) {
        guard streaming else { return }
        streamBuffers.append(ownedBuffer)
        // Safety net: if the model isn't trimming yet (loading/failed/unloaded),
        // drop the oldest buffers so memory can't run away. The .m4a on disk
        // still has the full audio (the authoritative one-shot pass uses that);
        // only the live-caption prefix is sacrificed, which is empty anyway
        // while `asr == nil`.
        var total = streamBuffers.reduce(AVAudioFrameCount(0)) { $0 + $1.frameLength }
        while total > Self.maxStreamFrames, streamBuffers.count > 1 {
            total -= streamBuffers.removeFirst().frameLength
        }
    }

    /// Best-effort full transcript right now: committed chunks + a live
    /// re-transcribe of the accumulated buffer. Overlapping calls short-circuit.
    func liveCaption() async -> String {
        await liveCaptionParts().full
    }

    /// The caption split at its REAL finalized boundary: `committed` = rotated
    /// chunks that will NEVER change again; everything after is the live chunk,
    /// re-transcribed wholesale each poll (volatile). This is the true signal
    /// the caption's solid-vs-volatile colouring needs — the old trailing-N-words
    /// approximation visibly lied ("white text is supposed to be non-changing
    /// but it also changes", 2026-06-10 device finding).
    func liveCaptionParts() async -> (full: String, committed: String) {
        await rotateIfNeeded()
        let committed = committedText()
        guard let asr, !streamBuffers.isEmpty else { return (committed, committed) }
        if snapshotRunning { return (committed, committed) }
        snapshotRunning = true
        defer { snapshotRunning = false }
        guard let merged = Self.concatenate(buffers: streamBuffers) else { return (committed, committed) }
        var state = TdtDecoderState.make()
        do {
            let tail = try await asr.transcribe(merged, decoderState: &state).text
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if tail.isEmpty { return (committed, committed) }
            let full = committed.isEmpty ? tail : committed + " " + tail
            return (full, committed)
        } catch {
            return (committed, committed)
        }
    }

    /// Stitched transcribe of the remaining buffer + committed chunks. Provided
    /// for completeness; the authoritative transcript is the one-shot file pass,
    /// so the record flow calls `endStream()` instead.
    func finishStream() async -> String {
        var finalSegment = ""
        if let asr, !streamBuffers.isEmpty, let merged = Self.concatenate(buffers: streamBuffers) {
            var state = TdtDecoderState.make()
            finalSegment = ((try? await asr.transcribe(merged, decoderState: &state).text) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let stitched = (committedChunks + [finalSegment]).filter { !$0.isEmpty }.joined(separator: " ")
        endStream()
        return stitched
    }

    /// Drop all live state (called on stop/cancel).
    func endStream() {
        streamBuffers.removeAll(keepingCapacity: false)
        committedChunks.removeAll(keepingCapacity: false)
        streamStartedAt = nil
        lastRotationAt = nil
        rotating = false
        streaming = false
    }

    private func committedText() -> String { committedChunks.joined(separator: " ") }

    /// Time-based chunk rotation: once the live buffer spans `rotationInterval`,
    /// transcribe it into a committed chunk and clear it, bounding memory.
    private func rotateIfNeeded() async {
        guard !rotating, let asr, !streamBuffers.isEmpty else { return }
        let started = lastRotationAt ?? streamStartedAt ?? Date()
        guard Date().timeIntervalSince(started) > Self.rotationInterval else { return }
        rotating = true
        let snapshot = streamBuffers
        streamBuffers.removeAll(keepingCapacity: true)
        defer { rotating = false }
        guard let merged = Self.concatenate(buffers: snapshot) else { return }
        var state = TdtDecoderState.make()
        if let text = try? await asr.transcribe(merged, decoderState: &state).text {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { committedChunks.append(trimmed) }
        }
        lastRotationAt = Date()
    }

    // MARK: - Buffer helpers (ported from Shhhcribble TextEngine)

    private static func copyBuffer(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let dst = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength) else { return nil }
        dst.frameLength = buffer.frameLength
        let channels = Int(buffer.format.channelCount)
        let frames = Int(buffer.frameLength)
        if let src = buffer.floatChannelData, let out = dst.floatChannelData {
            for ch in 0..<channels { memcpy(out[ch], src[ch], frames * MemoryLayout<Float>.size) }
        }
        return dst
    }

    private static func concatenate(buffers: [AVAudioPCMBuffer]) -> AVAudioPCMBuffer? {
        guard let first = buffers.first else { return nil }
        let format = first.format
        let total = buffers.reduce(AVAudioFrameCount(0)) { $0 + $1.frameLength }
        guard total > 0, let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: total) else { return nil }
        out.frameLength = total
        let channels = Int(format.channelCount)
        var offset = 0
        for buf in buffers {
            let frames = Int(buf.frameLength)
            if let src = buf.floatChannelData, let dst = out.floatChannelData {
                for ch in 0..<channels { memcpy(dst[ch] + offset, src[ch], frames * MemoryLayout<Float>.size) }
            }
            offset += frames
        }
        return out
    }
}

/// Deterministic transcriber for UI tests, fed by the `-seedTranscript` launch
/// arg. Produces evenly-spaced word timings so the sidecar + downstream code see
/// a realistic shape without the Neural Engine.
struct SeededTranscriber: Transcriber {
    let text: String

    func transcribe(audioURL: URL, imageManifest: [ImageManifestEntry]) async throws -> TranscriptionResult {
        let pieces = text.split(separator: " ")
        let timedWords = pieces.enumerated().map { index, word in
            ImageMarkers.TimedWord(text: String(word), start: Double(index) * 0.3, end: Double(index) * 0.3 + 0.25)
        }
        var outText = text
        var markersInjected = false
        if !imageManifest.isEmpty, !timedWords.isEmpty {
            outText = ImageMarkers.insert(transcript: text, words: timedWords, manifest: imageManifest)
            markersInjected = true
        }
        let wordTimings = timedWords.map { WordTiming(word: $0.text, start: $0.start, end: $0.end) }
        return TranscriptionResult(text: outText, confidence: 1.0, durationMs: 0,
                                   wordTimings: wordTimings, markersInjected: markersInjected)
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
