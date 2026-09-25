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
    /// Which language mode the LOADED manager was built for — flipping the setting has
    /// to REBUILD it (the config is baked in at `AsrManager(config:)`), exactly as the
    /// phone does. Without this the Mac would keep transcribing with the old config
    /// until relaunch.
    private var loadedMultilingual: Bool?

    // Live streaming session state now lives in the shared `LiveCaptionEngine`. This flag
    // is the service's own MIRROR of begin/end — kept here because `unload()` must refuse
    // to drop the model mid-stream (mirrors the phone's `TranscriptionService`).
    private var streaming = false

    /// Nonisolated, thread-safe mirror of `isModelReady` so the synchronous /health
    /// handler can read it without hopping onto the actor. Kept in sync with `asr`.
    private let ready = OSAllocatedUnfairLock(initialState: false)

    private init() {}

    var isModelReady: Bool { asr != nil }

    /// Load Parakeet v3 (multilingual incl. EN+NL). First call downloads from HF.
    func ensureLoaded(onProgress: @Sendable @escaping (Double) -> Void = { _ in }) async throws {
        // The language mode is baked into the manager's config, so a change must rebuild
        // it (mirrors the phone). Settings → Transcription; syncs from the other devices.
        let mode = ASRLanguageMode.from(
            multilingual: SettingsStore.shared.load().transcriptionIsMultilingual)
        if asr != nil, loadedMultilingual == mode.isMultilingual { return }
        if asr != nil {
            asr = nil; models = nil
            ready.withLock { $0 = false }
        }
        if let loadTask { try await loadTask.value; return }
        let task = Task<Void, Error> {
            let cfg = MLModelConfiguration()
            cfg.computeUnits = .cpuAndNeuralEngine
            let loaded = try await AsrModels.downloadAndLoad(configuration: cfg, version: .v3,
                                                             progressHandler: { onProgress($0.fractionCompleted) })
            // `melChunkContext` comes from the SHARED derivation — the Mac used to pass
            // `.default` (English-tuned) with no way to change it, which garbled Dutch.
            let manager = AsrManager(config: ASRConfig(melChunkContext: mode.melChunkContext))
            try await manager.loadModels(loaded)
            self.models = loaded
            self.asr = manager
            self.loadedMultilingual = mode.isMultilingual
            self.ready.withLock { $0 = true }
            // A caption stream that began before a slow load recovers the moment the model
            // lands — mirrors the phone's `ensureLoaded` (2026-07-28).
            if self.streaming { await self.live.setTranscriber(self.makeCaptionTranscriber()) }
        }
        loadTask = task
        do { try await task.value; loadTask = nil }
        catch { loadTask = nil; throw error }
    }

    func unload() {
        guard !isTranscribing, !streaming, loadTask == nil else { return }
        let manager = asr
        asr = nil
        models = nil
        loadedMultilingual = nil
        ready.withLock { $0 = false }
        // The engine must stop asking a manager that's gone — the closure's own `guard let
        // asr` is the backstop for the brief in-flight window (mirrors the phone).
        Task { await live.setTranscriber(nil) }
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

        // The tail (phantom guard → BPE merge → vocab rescore → timings → markers) is
        // the SHARED `ASRPostProcess` — one copy with the phone, so the order those
        // passes run in can't drift between the apps. RMS reads the ORIGINAL file, not
        // the preprocessed one, and only for a suspiciously tiny transcript.
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
                // The Mac's word list is its Settings; the spotter resamples the
                // ORIGINAL audio itself.
                let customWords = SettingsStore.shared.load().customWords
                guard !customWords.isEmpty else { return nil }
                return await VocabularyBooster.shared.boost(
                    text: text, tokenTimings: result.tokenTimings ?? [],
                    audioURL: audioURL, words: customWords)?.text
            })
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

    // MARK: - Live streaming (the Mac's live-recording surface, `LiveRecordingSession`)
    //
    // The engine itself — accumulate/snapshot/rotate/pace — moved VERBATIM to the shared
    // `LiveCaptionEngine` (2026-07-28): one physical copy of the phone's freeze-spiral
    // scars, so the two apps' captions cannot drift. This service remains the owner of the
    // ONE loaded `asr` manager and hands the engine a transcriber closure only while the
    // model is actually ready — never a second model in memory. Calls into `asr.transcribe`
    // serialise on the AsrManager's own executor even when interleaved. Mirrors the phone's
    // `TranscriptionService` streaming section file-for-file; `os.Logger` stands in for the
    // phone's `DevLog` (iOS-only).

    private static let liveLog = Logger(subsystem: "com.skrift.desktop", category: "live")
    /// PAUSE-triggered settling, 20 s ceiling: on the m2 surface settled = editable = white,
    /// and the research verdict (`LANES-2026-07-28/RESEARCH_DICTATION.md`) is that phrase
    /// boundaries — not a clock — are what makes Apple-style dictation feel right; every
    /// production streaming stack uses VAD as the primary commit signal with a window as the
    /// fallback. So: a breath settles the phrase, and the ceiling only catches the person who
    /// never stops talking. It sat at 7 s while the timer was still primary; with pauses
    /// primary that short a ceiling FIRED mid-sentence (Tuur's ROUND 10 "cuts up the
    /// sentence… because the seven seconds have passed"), so it rose to 20 s — an M4
    /// re-transcribes even that window fast enough, and a real speaker breathes long before
    /// it. The phone stays timer-only at its thermally-tuned default 25 s.
    private let live = LiveCaptionEngine(rotationInterval: 20, pauseTriggered: true,
                                         log: { TranscriptionService.liveLog.notice("\($0, privacy: .public)") })

    /// Begin a live session: clear prior state and kick off the model load so the first
    /// buffers transcribe as soon as it's ready.
    func beginStream() async {
        streaming = true
        await live.begin()
        try? await ensureLoaded()
        if asr != nil { await live.setTranscriber(makeCaptionTranscriber()) }
    }

    /// Append a captured buffer. The caller hands off an OWNED copy — `MacRecorder`'s
    /// sample-buffer callback copies off its own queue before this actor hop, because its
    /// buffer's backing storage moves on to the next callback.
    func feedStream(_ ownedBuffer: AVAudioPCMBuffer) async {
        await live.feed(ownedBuffer)
    }

    /// Best-effort full transcript right now: committed chunks + a live re-transcribe of
    /// the accumulated buffer. Overlapping calls short-circuit.
    func liveCaption() async -> String {
        await live.caption()
    }

    /// The caption split at its REAL finalized boundary — see
    /// `LiveCaptionEngine.captionParts`.
    func liveCaptionParts() async -> (full: String, committed: String) {
        await live.captionParts()
    }

    /// `finish`, split at the ownership boundary — see `LiveCaptionEngine.finishParts`.
    /// Named (not a plain `finishStream`) because the Mac's edited-take finalize needs the
    /// split `finalTail`; the phone never uses either — its stop always re-ASRs the whole
    /// file, so it only keeps a plain `finishStream()` for completeness.
    func finishStreamParts() async -> (stitched: String, finalTail: String) {
        streaming = false
        return await live.finishParts()
    }

    /// Drop all live state (called on stop/cancel).
    func endStream() async {
        streaming = false
        await live.end()
    }

    /// The engine's one ASR call, built over THIS service's loaded manager. The closure
    /// re-checks `asr` at call time — the model can unload (idle timeout) mid-stream, and a
    /// throw here reads to the engine exactly like a `nil` transcriber.
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
