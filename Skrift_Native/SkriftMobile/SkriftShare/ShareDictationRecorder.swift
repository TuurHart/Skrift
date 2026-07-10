import Foundation
import AVFoundation

/// Lightweight voice-note recorder for the share sheet.
///
/// The extension ONLY records — Parakeet (~600 MB) cannot load inside a share
/// extension's memory ceiling (~120 MB), so transcription happens in the main
/// app when the inbox drains (`CaptureDictation`). AVAudioRecorder + AAC keeps
/// the extension footprint tiny.
///
/// States: idle → recording → recorded (re-tap mic to replace, ✕ to discard).
@MainActor
@Observable
final class ShareDictationRecorder {

    enum State: Equatable {
        case idle
        case denied               // mic permission refused (the EXTENSION's own TCC entry)
        case failed               // permission fine, but the session/recorder couldn't start
        case recording
        case recorded(duration: TimeInterval)
    }

    private(set) var state: State = .idle
    /// Live elapsed seconds while recording (timer-driven for the UI label).
    private(set) var elapsed: TimeInterval = 0

    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private let fileURL: URL

    init() {
        fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("dictation_\(UUID().uuidString).m4a")
    }

    /// The recorded audio, nil unless state == .recorded.
    var recordedData: Data? {
        guard case .recorded = state else { return nil }
        return try? Data(contentsOf: fileURL)
    }

    func toggleRecord() {
        switch state {
        case .recording:
            stop()
        case .idle, .recorded, .denied, .failed:
            // Re-tap after a take replaces it (one dictation per capture, v1).
            start()
        }
    }

    func discard() {
        stop(discarding: true)
        try? FileManager.default.removeItem(at: fileURL)
        state = .idle
        elapsed = 0
    }

    private func start() {
        // Diagnose, don't collapse: round-1 device finding showed "mic is off"
        // while the app's mic worked — the extension has its OWN permission
        // entry, and session failures were mislabeled as permission denials.
        CaptureInbox.extLog("dictation: start; perm=\(AVAudioApplication.shared.recordPermission.rawValue)")
        AVAudioApplication.requestRecordPermission { [weak self] granted in
            Task { @MainActor in
                guard let self else { return }
                guard granted else {
                    CaptureInbox.extLog("dictation: permission DENIED")
                    self.state = .denied
                    return
                }
                self.beginRecording()
            }
        }
    }

    private func beginRecording() {
        let session = AVAudioSession.sharedInstance()
        do {
            // Pure .record category — round-2 devlog showed permission GRANTED
            // ('grnt') yet record() returning false with .playAndRecord; a
            // record-only session is the one config share extensions are most
            // likely to be allowed. If this still fails, round 4 hides the button.
            try session.setCategory(.record, mode: .default)
            try session.setActive(true)
            // Mono 22.05 kHz AAC — small files, plenty for ASR (Parakeet resamples).
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 22_050,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
            ]
            try? FileManager.default.removeItem(at: fileURL)
            let rec = try AVAudioRecorder(url: fileURL, settings: settings)
            guard rec.record() else {
                CaptureInbox.extLog("dictation: recorder.record() returned false")
                state = .failed
                return
            }
            recorder = rec
            elapsed = 0
            state = .recording
            CaptureInbox.extLog("dictation: recording started")
            timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self, case .recording = self.state else { return }
                    self.elapsed = self.recorder?.currentTime ?? self.elapsed
                }
            }
        } catch {
            CaptureInbox.extLog("dictation: session/recorder threw: \(error)")
            state = .failed
        }
    }

    private func stop(discarding: Bool = false) {
        timer?.invalidate(); timer = nil
        guard let rec = recorder else { return }
        let duration = rec.currentTime
        rec.stop()
        recorder = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        if !discarding {
            // Sub-second takes are accidental taps — treat as discard.
            if duration >= 1.0 {
                state = .recorded(duration: duration)
            } else {
                try? FileManager.default.removeItem(at: fileURL)
                state = .idle
                elapsed = 0
            }
        }
    }
}
