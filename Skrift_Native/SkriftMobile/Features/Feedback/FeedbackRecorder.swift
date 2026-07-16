import AVFoundation
import Foundation

/// Standalone `AVAudioRecorder` for the feedback capture flow (ported from
/// Shhhcribble). Records a temp 16 kHz mono WAV; the caller transcribes it via
/// Skrift's `Transcribing`, then calls `discard()`. Separate from the main
/// `LiveRecordingService` — a one-shot batch flow with its own `.record` session.
@MainActor
final class FeedbackRecorder: ObservableObject {
    @Published var elapsed: TimeInterval = 0

    private var audioRecorder: AVAudioRecorder?
    private var timer: Timer?
    private var tempURL: URL?

    var finishedFileURL: URL? { tempURL }

    func start() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .default, options: [])
        try session.setActive(true)

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("feedback-\(UUID().uuidString).wav")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false,
        ]
        let r = try AVAudioRecorder(url: url, settings: settings)
        r.record()
        audioRecorder = r
        tempURL = url
        elapsed = 0

        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.elapsed += 0.1 }
        }
    }

    func stop() {
        audioRecorder?.stop()
        audioRecorder = nil
        timer?.invalidate()
        timer = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    func discard() {
        stop()
        if let url = tempURL { try? FileManager.default.removeItem(at: url) }
        tempURL = nil
        elapsed = 0
    }
}
