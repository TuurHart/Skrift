import AVFoundation
import Combine
import Foundation

/// Records a memo to an `.m4a` file via `AVAudioRecorder`, with metering for the
/// waveform and pause/resume that tracks recording time (paused time excluded) —
/// matching the RN `useRecording` semantics.
///
/// In **mock mode** (enabled by `-seedTranscript`) it skips the mic entirely (no
/// permission prompt, no real audio) and just runs the timer + writes a
/// placeholder file, so the record→save→transcribe flow is hermetically
/// UI-testable. Real capture is verified on a physical device.
@MainActor
final class RecordingService: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var isPaused = false
    @Published private(set) var elapsed: TimeInterval = 0
    /// Smoothed input level, 0...1, for the waveform.
    @Published private(set) var level: Float = 0

    private let mock: Bool
    private var recorder: AVAudioRecorder?
    private var displayTimer: Timer?
    private var segmentStart: Date?
    private var accumulated: TimeInterval = 0
    private var tempURL: URL?

    init(mock: Bool = LaunchFlags.seedTranscript != nil) {
        self.mock = mock
    }

    func start() throws {
        guard !isRecording else { return }
        accumulated = 0
        elapsed = 0
        level = 0
        let url = AppPaths.recordingsDirectory.appendingPathComponent("rec_tmp_\(UUID().uuidString).m4a")
        tempURL = url

        if mock {
            FileManager.default.createFile(atPath: url.path, contents: Data())
        } else {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.allowBluetooth, .defaultToSpeaker])
            try session.setActive(true)
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44_100.0,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            ]
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.isMeteringEnabled = true
            recorder.record()
            self.recorder = recorder
        }

        isRecording = true
        isPaused = false
        segmentStart = Date()
        startTimer()
    }

    func pause() {
        guard isRecording, !isPaused else { return }
        recorder?.pause()
        accumulate()
        isPaused = true
    }

    func resume() {
        guard isRecording, isPaused else { return }
        recorder?.record()
        segmentStart = Date()
        isPaused = false
    }

    /// Stop and return the recorded file + final duration (recording time).
    func stop() -> (url: URL, duration: TimeInterval)? {
        guard isRecording else { return nil }
        accumulate()
        recorder?.stop()
        recorder = nil
        deactivateSession()
        stopTimer()
        isRecording = false
        isPaused = false
        let duration = elapsed
        guard let url = tempURL else { return nil }
        tempURL = nil
        return (url, duration)
    }

    /// Abort: stop, delete the temp file, reset.
    func cancel() {
        guard isRecording else { return }
        recorder?.stop()
        recorder = nil
        deactivateSession()
        stopTimer()
        if let url = tempURL { try? FileManager.default.removeItem(at: url) }
        tempURL = nil
        isRecording = false
        isPaused = false
        elapsed = 0
        level = 0
    }

    // MARK: - Private

    private func deactivateSession() {
        guard !mock else { return }
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    private func accumulate() {
        if let start = segmentStart {
            accumulated += Date().timeIntervalSince(start)
            segmentStart = nil
        }
    }

    private func startTimer() {
        displayTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            // The timer fires on the main run loop; we're already MainActor-isolated.
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    private func stopTimer() {
        displayTimer?.invalidate()
        displayTimer = nil
    }

    private func tick() {
        let live = segmentStart.map { Date().timeIntervalSince($0) } ?? 0
        elapsed = accumulated + (isPaused ? 0 : live)
        if mock {
            level = isPaused ? 0 : Float(0.35 + 0.25 * sin(elapsed * 6))
        } else if let recorder, !isPaused {
            recorder.updateMeters()
            level = Self.normalizedPower(recorder.averagePower(forChannel: 0))
        }
    }

    /// Map dBFS (-160...0) to 0...1, flooring quiet noise at -60 dB.
    private static func normalizedPower(_ db: Float) -> Float {
        let minDb: Float = -60
        if db <= minDb { return 0 }
        if db >= 0 { return 1 }
        return (db - minDb) / -minDb
    }
}
