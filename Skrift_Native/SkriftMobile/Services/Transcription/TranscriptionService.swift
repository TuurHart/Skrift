import AVFoundation
import CoreML
import FluidAudio
import Foundation
import UIKit

// `TranscriptionResult` + the `Transcribing` protocol (with the spill-to-WAV
// buffer default) are SHARED (Shared/Pipeline/TranscribingContract.swift) — this
// file keeps only the FluidAudio engine + the seeded/sim transcriber. The sim
// runs seeded because it has no Neural Engine and FluidAudio pulls ~600MB.

/// On-device ASR via FluidAudio (Parakeet TDT v3). Ported from the RN
/// `ParakeetModule.swift`, adapted to FluidAudio `main` (`loadModels`,
/// `transcribe(url, decoderState:)`, `ASRResult.tokenTimings`). Carries the two
/// native fixes from the RN module: model teardown on memory pressure, and the
/// RMS/word-count silence guard. The BPE→word merge + `[[img_NNN]]` insertion are
/// bit-for-bit ports of the desktop `_insert_image_markers`.
actor TranscriptionService: Transcribing {
    static let shared = TranscriptionService()

    private var asr: AsrManager?
    private var models: AsrModels?
    private var loadTask: Task<Void, Error>?
    private var isTranscribing = false
    private var memoryObserver: NSObjectProtocol?
    /// The language mode (`transcriptionMultilingual`) the loaded manager was built
    /// with, so `ensureLoaded` rebuilds when the user flips the Settings toggle.
    private var loadedMultilingual = false

    // Live streaming session state now lives in the shared `LiveCaptionEngine`
    // (see the "Live streaming" section below). This flag is the service's own
    // MIRROR of begin/end — kept here because `unload()` is synchronous and must
    // refuse to drop the model mid-stream without an async hop to the engine.
    private var streaming = false

    private init() {}

    // MARK: - Model lifecycle

    func ensureLoaded() async throws {
        installMemoryObserverIfNeeded()
        // Transcription mode (Settings): English (the v3 default, clean English seams)
        // vs Multilingual (melChunkContext off — stops the v3 decoder drifting to its
        // English prior on non-English audio). Default = English. Flipping it drops
        // the loaded manager so the next transcribe rebuilds with the right config.
        // Reads the SHARED store, so the key name and the config derivation are the same
        // ones the Mac uses (`ASRLanguageMode`) — they used to be inlined per app, which
        // is how the Mac ended up permanently English-tuned.
        let multilingual = ASRLanguageStore.isMultilingual()
        if asr != nil, multilingual == loadedMultilingual { return }
        if asr != nil { asr = nil; models = nil }   // mode changed → rebuild below
        if let loadTask {
            try await loadTask.value
            return
        }
        let task = Task<Void, Error> {
            await MainActor.run { ModelLoadStatus.shared.set(.preparing(nil)) }
            let mlConfig = MLModelConfiguration()
            mlConfig.computeUnits = .cpuAndNeuralEngine
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
            // Language mode (A/B-tested via the desktop `-asrsweep` harness on real
            // audio): Multilingual sets melChunkContext:false — on Dutch (a 3-min
            // spoken-Wikipedia clip) the default (mel=on) drifts to its English prior
            // and garbles non-English (wrong years 1666/"twaalftig" vs 1986/1283,
            // mangled place-names), which mel=off fixes; it's language-agnostic so it
            // helps any non-English language v3 supports. The cost is a small English
            // chunk-seam dup, so English mode keeps mel=on (the v3 default). dualDecode
            // stays off (byte-identical but ~2.7× slower in both tests).
            let manager = AsrManager(config: ASRConfig(
                melChunkContext: ASRLanguageMode.from(multilingual: multilingual).melChunkContext))
            try await manager.loadModels(loaded)
            self.models = loaded
            self.asr = manager
            self.loadedMultilingual = multilingual
            // A caption stream that began before a slow load recovers the moment the
            // model lands — the old code's per-poll `guard let asr` gave this for free.
            if self.streaming { await self.live.setTranscriber(self.makeCaptionTranscriber()) }
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
        // The engine must stop asking a manager that's gone. (The closure's own
        // `guard let asr` is the backstop for the brief in-flight window.)
        Task { await live.setTranscriber(nil) }
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
        TranscriptionActivity.begin()   // the embedder yields the ANE while this runs
        defer { isTranscribing = false; TranscriptionActivity.end() }
        try await ensureLoaded()
        guard let asr else {
            throw ASRError.notInitialized
        }

        let started = Date()
        var state = TdtDecoderState.make()
        let result = try await asr.transcribe(audioURL, decoderState: &state)
        let ms = Int(Date().timeIntervalSince(started) * 1000)

        // The tail (phantom guard → BPE merge → vocab rescore → timings → markers) is
        // the SHARED `ASRPostProcess` — one copy with the Mac. RMS decodes the ENTIRE
        // file, so it stays lazy: only a suspiciously tiny transcript pays for it.
        return await ASRPostProcess.finish(
            rawText: result.text,
            tokens: (result.tokenTimings ?? []).map {
                RawToken(token: $0.token, startTime: $0.startTime, endTime: $0.endTime)
            },
            confidence: Double(result.confidence),
            durationMs: ms,
            imageManifest: imageManifest,
            rms: { AudioRMS.averageRMS(url: audioURL) },
            rescore: { text in
                // The phone's word list is the synced `CustomVocabularyStore`, which
                // the booster reads itself.
                await VocabularyBooster.shared.boost(
                    text: text, tokenTimings: result.tokenTimings ?? [],
                    audioURL: audioURL)
            })
    }

    /// Direct PCM transcribe (the whole-book chunk path): same engine, same
    /// BPE merge and phantom guard as the file path, minus the temp-file
    /// round-trip and the vocab/marker passes (see the protocol note).
    func transcribe(buffer: AVAudioPCMBuffer) async throws -> TranscriptionResult {
        isTranscribing = true
        TranscriptionActivity.begin()   // the embedder yields the ANE while this runs
        defer { isTranscribing = false; TranscriptionActivity.end() }
        try await ensureLoaded()
        guard let asr else { throw ASRError.notInitialized }

        let started = Date()
        var state = TdtDecoderState.make()
        let result = try await asr.transcribe(buffer, decoderState: &state)
        let ms = Int(Date().timeIntervalSince(started) * 1000)

        // Same shared tail, minus the vocab/marker passes (see the protocol note):
        // a book chunk has no photos, and the rescore runs on the whole book instead.
        return await ASRPostProcess.finish(
            rawText: result.text,
            tokens: (result.tokenTimings ?? []).map {
                RawToken(token: $0.token, startTime: $0.startTime, endTime: $0.endTime)
            },
            confidence: Double(result.confidence),
            durationMs: ms,
            rms: { AudioRMS.rms(of: buffer) },
            rescore: { _ in nil })
    }

    // (RMS energy for the phantom guard lives in the shared `AudioRMS`, and BPE
    // token→word merging in the shared `BPEMerge` — one copy each with the Mac.)

    // MARK: - Live streaming (record-screen captions)
    //
    // The engine itself — accumulate/snapshot/rotate/pace, Shhhcribble's TextEngine
    // lineage minus VAD rotation and vocab passes — moved VERBATIM to the shared
    // `LiveCaptionEngine` (2026-07-28, for the Mac's live-recording surface): one
    // physical copy of the freeze-spiral scars, so the two apps' captions cannot
    // drift. This service remains the owner of the ONE loaded `asr` manager and
    // hands the engine a transcriber closure only while the model is actually
    // ready — never a second model in memory. Calls into `asr.transcribe`
    // serialise on the AsrManager's own executor even when interleaved.
    //
    // DEVICE-OWED: the Simulator has no Neural Engine, so the record screen
    // drives a mock caption instead (see `LiveRecordingService`). This path is
    // only exercised on a physical device. The authoritative transcript (with
    // word timings + image markers) still comes from the one-shot file pass
    // after stop — the live caption is display-only.

    private let live = LiveCaptionEngine(log: { DevLog.log($0) })

    /// Begin a live session: clear prior state and kick off the model load so
    /// the first buffers transcribe as soon as it's ready.
    func beginStream() async {
        streaming = true
        await live.begin()
        try? await ensureLoaded()
        if asr != nil { await live.setTranscriber(makeCaptionTranscriber()) }
    }

    /// Append a captured buffer. The caller hands off an **owned** copy — the
    /// record tap copies off the audio thread before this actor hop, because the
    /// tap's backing storage is reused under us.
    func feedStream(_ ownedBuffer: AVAudioPCMBuffer) async {
        await live.feed(ownedBuffer)
    }

    /// The caption split at its REAL finalized boundary — see
    /// `LiveCaptionEngine.captionParts` (the 2026-06-10 device finding lives on
    /// its doc comment now).
    func liveCaptionParts() async -> (full: String, committed: String) {
        await live.captionParts()
    }

    /// Drop all live state (called on stop/cancel).
    func endStream() async {
        streaming = false
        await live.end()
    }

    /// The engine's one ASR call, built over THIS service's loaded manager. The closure
    /// re-checks `asr` at call time — the model can unload (memory warning) mid-stream,
    /// and a throw here reads to the engine exactly like the old `guard let asr`.
    private func makeCaptionTranscriber() -> LiveCaptionEngine.Transcribe {
        { [weak self] merged in
            guard let self else { throw ASRError.notInitialized }
            return try await self.transcribeCaptionWindow(merged)
        }
    }

    private func transcribeCaptionWindow(_ merged: AVAudioPCMBuffer) async throws -> String {
        guard let asr else { throw ASRError.notInitialized }
        var state = TdtDecoderState.make()
        return try await asr.transcribe(merged, decoderState: &state).text
    }
}

/// Deterministic transcriber for UI tests, fed by the `-seedTranscript` launch
/// arg. Produces evenly-spaced word timings so the sidecar + downstream code see
/// a realistic shape without the Neural Engine.
struct SeededTranscriber: Transcribing {
    let text: String

    func transcribe(audioURL: URL, imageManifest: [ImageManifestEntry]) async throws -> TranscriptionResult {
        let pieces = text.split(separator: " ")
        let timedWords = pieces.enumerated().map { index, word in
            TimedWord(text: String(word), start: Double(index) * 0.3, end: Double(index) * 0.3 + 0.25)
        }
        let wordTimings = timedWords.map { WordTiming(word: $0.text, start: $0.start, end: $0.end) }
        var outText = text
        var markersInjected = false
        if !imageManifest.isEmpty, !timedWords.isEmpty {
            // Same placement as the real engine (`ASRPostProcess`): body v2, committed once.
            outText = BodyV2.committed(BodyV2.Input(text: text, words: wordTimings, manifest: imageManifest,
                                                    source: .speech))
            markersInjected = true
        }
        return TranscriptionResult(text: outText, confidence: 1.0, durationMs: 0,
                                   wordTimings: wordTimings, markersInjected: markersInjected)
    }
}

enum TranscriberFactory {
    /// Seeded in tests (`-seedTranscript`), real FluidAudio engine otherwise.
    static func make() -> any Transcribing {
        if let seed = LaunchFlags.seedTranscript {
            return SeededTranscriber(text: seed)
        }
        return TranscriptionService.shared
    }
}
