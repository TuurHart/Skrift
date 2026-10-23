import Foundation
import AVFoundation

/// The parts of "record a voice memo" that are the SAME on every app.
///
/// Deliberately narrow. The phone's `LiveRecordingService` is 1508 lines, and most of it is
/// `AVAudioSession` — route changes, HFP flips, interruption recovery, the whole AirPods saga.
/// **None of that type exists on macOS**, so the session half genuinely cannot be shared and
/// pretending otherwise would mean a fake abstraction over two different problems. What CAN be
/// shared is everything that decides how a recording SOUNDS, what it's CALLED, and how it
/// READS on screen — and those are exactly the things that would drift into "the Mac's memos
/// are 44.1 kHz and the phone's are 48" if each app kept its own copy.
enum RecordingCore {

    /// The encoder settings every Skrift recording is written with. AAC in an m4a, at the
    /// input's own rate and channel count — resampling on the way in only adds artefacts for
    /// the ASR to trip over, and FluidAudio does its own conversion anyway.
    static func encoderSettings(for format: AVAudioFormat) -> [String: Any] {
        [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
    }

    /// A recording's filename. `memo_<uuid>.m4a` — the phone's convention since the native
    /// rewrite, and the shape `MemoSaver`, `AppPaths` and the Mac's ingest all already expect.
    static func filename(id: UUID = UUID(), ext: String = "m4a") -> String {
        "memo_\(id.uuidString).\(ext)"
    }

    /// Input level 0…1 for the meter, from one capture buffer. The `× 12` is a measured
    /// loudness scale, not a guess — speech RMS at a comfortable distance lands around 0.08,
    /// which this maps to a bar near full height. Shared so the Mac's waveform moves like the
    /// phone's instead of looking dead or permanently clipped.
    static func level(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let ch = buffer.floatChannelData?[0] else { return 0 }
        let n = Int(buffer.frameLength)
        guard n > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<n { sum += ch[i] * ch[i] }
        return min(1, (sum / Float(n)).squareRoot() * 12)
    }

    /// `m:ss` (or `h:mm:ss` past an hour) for the running timer. One rule, so a 3-minute memo
    /// doesn't read "3:07" on one app and "03:07" on another.
    static func elapsedLabel(_ seconds: TimeInterval) -> String {
        let t = max(0, Int(seconds))
        let (h, m, s) = (t / 3600, (t % 3600) / 60, t % 60)
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }

    /// The recording clock: seconds of TAKE, the timeline the audio file and its word times
    /// live on. It runs only while the take captures — a user pause and an interruption (call,
    /// Siri, alarm: the system owns the mic, nothing lands in the file) each stop it, and it
    /// runs again once neither holds (C149). Photo offsets read it, so a picture snapped after
    /// a call lands where it was taken instead of the call's length later.
    struct Clock {
        private var banked: TimeInterval = 0
        private var runningSince: Date?
        private var started = false
        private(set) var isPaused = false
        private(set) var isInterrupted = false

        init() {}

        mutating func start(at now: Date = Date()) {
            banked = 0
            started = true
            isPaused = false
            isInterrupted = false
            runningSince = now
        }

        mutating func setPaused(_ on: Bool, at now: Date = Date()) {
            isPaused = on
            settle(at: now)
        }

        mutating func setInterrupted(_ on: Bool, at now: Date = Date()) {
            isInterrupted = on
            settle(at: now)
        }

        mutating func stop(at now: Date = Date()) {
            settle(at: now)
            if let since = runningSince { banked += now.timeIntervalSince(since) }
            runningSince = nil
            started = false
        }

        /// Seconds of take at `now`.
        func reading(at now: Date = Date()) -> TimeInterval {
            banked + (runningSince.map { max(0, now.timeIntervalSince($0)) } ?? 0)
        }

        private mutating func settle(at now: Date) {
            let runs = started && !isPaused && !isInterrupted
            if runs, runningSince == nil {
                runningSince = now
            } else if !runs, let since = runningSince {
                banked += max(0, now.timeIntervalSince(since))
                runningSince = nil
            }
        }
    }

    /// A rolling window of levels for the live waveform, newest last. Fixed width so the bars
    /// scroll rather than rescale — a meter that re-fits its own history reads as noise.
    struct Meter {
        private(set) var bars: [Float]
        let width: Int

        init(width: Int = 12) {
            self.width = width
            self.bars = Array(repeating: 0, count: width)
        }

        mutating func push(_ level: Float) {
            bars.removeFirst()
            bars.append(min(1, max(0, level)))
        }

        /// Bar height as a fraction of the track — floored so a silent moment still draws a
        /// hairline instead of a gap, which reads as "stopped" rather than "quiet".
        func height(at i: Int) -> Double {
            guard i >= 0, i < bars.count else { return 0.12 }
            return 0.12 + Double(bars[i]) * 0.88
        }
    }
}
