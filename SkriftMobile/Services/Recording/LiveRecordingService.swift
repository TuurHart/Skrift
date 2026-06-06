import AVFoundation
import Combine
import Foundation

/// Drives a recording with a single `AVAudioEngine` tap that does three things at
/// once: writes the `.m4a` (for upload + playback + the authoritative one-shot
/// re-transcribe), computes the live mic level for the waveform, and feeds the
/// streaming `TranscriptionService` for the caption-first UI. Pause excludes
/// paused time from the duration and stops writing/feeding.
///
/// In **mock mode** (`-seedTranscript`) there's no engine, no mic, no model: a
/// timer advances the clock, fakes a level, and *progressively reveals* the
/// seeded transcript as the live caption — so the caption-first record screen is
/// fully UI-testable on the Simulator (which has no Neural Engine). Real capture,
/// the live ASR caption, and the file write are device-owed.
@MainActor
final class LiveRecordingService: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var isPaused = false
    @Published private(set) var elapsed: TimeInterval = 0
    /// Smoothed input level, 0...1.
    @Published private(set) var level: Float = 0
    /// Rolling level history (newest last) for the live waveform bars.
    @Published private(set) var waveform: [Float] = []
    /// Best-effort live transcript shown caption-first while recording.
    @Published private(set) var liveCaption: String = ""

    /// Whether live captioning is on (Settings toggle; default on). Off = record
    /// + waveform only, transcript comes from the one-shot pass after stop.
    var liveTranscription: Bool

    private let mock: Bool
    private static let waveformBars = 40

    private var engine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var tempURL: URL?

    // Mirrored, audio-thread-readable copies of the gating state. The tap runs
    // on a real-time thread; reading MainActor-isolated @Published vars there
    // would be a data race, so we mirror what the tap needs.
    private nonisolated(unsafe) var tapPaused = false
    private nonisolated(unsafe) var tapLive = true

    private var displayTimer: Timer?
    private var captionTimer: Timer?
    private var segmentStart: Date?
    private var accumulated: TimeInterval = 0

    // Mock-only progressive caption state.
    private var mockWords: [String] = []
    private var mockRevealed = 0

    init(mock: Bool = LaunchFlags.seedTranscript != nil,
         liveTranscription: Bool = UserDefaults.standard.object(forKey: "liveTranscription") as? Bool ?? true) {
        self.mock = mock
        self.liveTranscription = liveTranscription
    }

    func start() throws {
        guard !isRecording else { return }
        accumulated = 0
        elapsed = 0
        level = 0
        waveform = []
        liveCaption = ""
        let url = AppPaths.recordingsDirectory.appendingPathComponent("rec_tmp_\(UUID().uuidString).m4a")
        tempURL = url

        tapPaused = false
        tapLive = liveTranscription

        if mock {
            FileManager.default.createFile(atPath: url.path, contents: Data())
            mockWords = (LaunchFlags.seedTranscript ?? "").split(separator: " ").map(String.init)
            mockRevealed = 0
        } else {
            try startEngine(writingTo: url)
            if liveTranscription {
                Task { await TranscriptionService.shared.beginStream() }
                startCaptionPolling()
            }
        }

        isRecording = true
        isPaused = false
        segmentStart = Date()
        startDisplayTimer()
    }

    func pause() {
        guard isRecording, !isPaused else { return }
        accumulate()
        isPaused = true
        tapPaused = true
        if !mock { engine?.pause() }
    }

    func resume() {
        guard isRecording, isPaused else { return }
        if !mock { try? engine?.start() }
        segmentStart = Date()
        isPaused = false
        tapPaused = false
    }

    struct Result { let url: URL; let duration: TimeInterval; let liveCaption: String }

    func stop() -> Result? {
        guard isRecording else { return nil }
        accumulate()
        stopTimers()
        if !mock {
            engine?.inputNode.removeTap(onBus: 0)
            engine?.stop()
            engine = nil
            audioFile = nil
            try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
            if liveTranscription { Task { await TranscriptionService.shared.endStream() } }
        }
        isRecording = false
        isPaused = false
        let caption = liveCaption
        let duration = elapsed
        guard let url = tempURL else { return nil }
        tempURL = nil
        return Result(url: url, duration: duration, liveCaption: caption)
    }

    func cancel() {
        guard isRecording else { return }
        stopTimers()
        if !mock {
            engine?.inputNode.removeTap(onBus: 0)
            engine?.stop()
            engine = nil
            audioFile = nil
            try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
            if liveTranscription { Task { await TranscriptionService.shared.endStream() } }
        }
        if let url = tempURL { try? FileManager.default.removeItem(at: url) }
        tempURL = nil
        isRecording = false
        isPaused = false
        elapsed = 0
        level = 0
        waveform = []
        liveCaption = ""
    }

    // MARK: - Real engine

    private func startEngine(writingTo url: URL) throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.allowBluetooth, .defaultToSpeaker])
        try session.setActive(true)

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings)
        self.audioFile = file

        // Real-time audio thread: do the buffer-bound work synchronously here
        // (the tap reuses its backing storage, so the buffer is only valid for
        // the callback) — gate on pause, write the file, measure the level, copy
        // for the stream. Only value-typed results hop to the main actor.
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            guard let self, !self.tapPaused else { return }
            try? file.write(from: buffer)
            let lvl = Self.rms(buffer)
            let owned = self.tapLive ? Self.copyBuffer(buffer) : nil
            Task { @MainActor [weak self] in
                guard let self, self.isRecording, !self.isPaused else { return }
                self.level = lvl
                self.pushWaveform(lvl)
            }
            if let owned {
                Task { await TranscriptionService.shared.feedStream(owned) }
            }
        }
        try engine.start()
        self.engine = engine
    }

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

    private func startCaptionPolling() {
        captionTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isRecording, !self.isPaused else { return }
                Task {
                    let caption = await TranscriptionService.shared.liveCaption()
                    if !caption.isEmpty { self.liveCaption = caption }
                }
            }
        }
    }

    private static func rms(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let ch = buffer.floatChannelData?[0] else { return 0 }
        let n = Int(buffer.frameLength)
        guard n > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<n { sum += ch[i] * ch[i] }
        let rms = (sum / Float(n)).squareRoot()
        return min(1, rms * 12)   // scale like Shhhcribble's AudioInput
    }

    // MARK: - Timers / shared

    private func startDisplayTimer() {
        displayTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    private func stopTimers() {
        displayTimer?.invalidate(); displayTimer = nil
        captionTimer?.invalidate(); captionTimer = nil
    }

    private func tick() {
        let live = segmentStart.map { Date().timeIntervalSince($0) } ?? 0
        elapsed = accumulated + (isPaused ? 0 : live)
        if mock { mockTick() }
    }

    /// Fake level + progressive caption reveal so the caption-first UI is
    /// testable without a mic or the Neural Engine.
    private func mockTick() {
        guard !isPaused else { level = 0; return }
        level = Float(0.35 + 0.3 * abs(sin(elapsed * 5)))
        pushWaveform(level)
        // Reveal ~1 word every 0.3s of elapsed time.
        let shouldReveal = min(mockWords.count, Int(elapsed / 0.3) + 1)
        if shouldReveal > mockRevealed {
            mockRevealed = shouldReveal
            liveCaption = mockWords.prefix(mockRevealed).joined(separator: " ")
        }
    }

    private func pushWaveform(_ value: Float) {
        waveform.append(value)
        if waveform.count > Self.waveformBars { waveform.removeFirst(waveform.count - Self.waveformBars) }
    }

    private func accumulate() {
        if let start = segmentStart {
            accumulated += Date().timeIntervalSince(start)
            segmentStart = nil
        }
    }
}
