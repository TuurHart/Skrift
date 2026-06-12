import AVFoundation
import Foundation

/// Preview playback player for the Hybrid capture adjust screen.
///
/// Replaces the old grain-scrubber design. Instead of short "grains" triggered
/// by handle drags, this player provides CONTINUOUS playback of the chapter
/// audio at a settable rate (1×, 1.5×, 2×). The waveform strip IS the audio
/// feedback — no grains needed.
///
/// Key contract:
/// - `prepare(url:)` — point at the chapter file (idempotent, no audio session
///   activation — opening the capture screen must never move AirPods off the
///   user's Mac).
/// - `play(from:)` — seek to `time` and start playing. Safe to call while
///   ALREADY PLAYING (the chip-spam mechanism the spec requires): the new seek
///   interrupts the current position and playback resumes from the new one.
/// - `pause()` / `stop()` — pause without discarding position.
/// - `rate` — 1.0, 1.5, or 2.0; applied immediately when set while playing.
/// - `addPeriodicTimeObserver(interval:handler:)` — drive the strip playhead.
///
/// `@MainActor` so all AVPlayer calls and published state changes originate on
/// the main thread.
@MainActor
final class CapturePreviewPlayer {
    private var player: AVPlayer?
    private var url: URL?
    private var sessionActivated = false

    /// Playback rate. Applied to a running player immediately; stored for the
    /// next `play(from:)` call when paused.
    var rate: Double = 1.5 {
        didSet {
            if let player, player.timeControlStatus == .playing {
                player.rate = Float(rate)
            }
        }
    }

    // MARK: - Setup

    /// Point the player at `url` (the chapter audio file). Idempotent: calling
    /// again with the same URL is a no-op. Must NOT activate the audio session.
    func prepare(url: URL) {
        guard url != self.url else { return }
        stop()
        let item = AVPlayerItem(asset: AVURLAsset(url: url))
        player = AVPlayer(playerItem: item)
        player?.automaticallyWaitsToMinimizeStalling = false
        self.url = url
    }

    // MARK: - Transport

    /// Seek to `time` (seconds into the file) and start / resume playback at
    /// `rate`. Safe to call while already playing — the seek repositions and
    /// playback continues from the new point without an explicit pause first.
    /// This is the mechanism behind the "spam-to-find-start" chip interaction.
    func play(from time: TimeInterval) {
        guard let player else { return }
        activateSessionIfNeeded()
        // Pause first so we can set the rate after the seek completes (setting
        // rate before the seek sometimes causes AVPlayer to ignore it).
        player.pause()
        let target = CMTime(seconds: max(0, time), preferredTimescale: 600)
        player.seek(
            to: target,
            toleranceBefore: .zero,
            toleranceAfter: CMTime(seconds: 0.04, preferredTimescale: 600)
        ) { [weak self, weak player] finished in
            guard finished, let self, let player else { return }
            player.rate = Float(self.rate)
        }
    }

    /// Pause playback without discarding the current position.
    func pause() {
        player?.pause()
    }

    /// Pause and release any pending state. Alias for `pause()` — kept for
    /// callsite parity with the old GrainPlayer API.
    func stop() {
        player?.pause()
    }

    // MARK: - State queries

    /// True while the player is playing (or in the process of seeking-to-play).
    var isPlaying: Bool {
        guard let player else { return false }
        return player.timeControlStatus == .playing
            || player.timeControlStatus == .waitingToPlayAtSpecifiedRate
    }

    /// Current playback position in the file (seconds). Returns 0 when no
    /// player has been prepared.
    var currentTime: TimeInterval {
        guard let t = player?.currentItem?.currentTime() else { return 0 }
        return CMTimeGetSeconds(t)
    }

    // MARK: - Time observer

    /// Register a periodic time observer that fires `handler` on the main queue
    /// every `interval` seconds. The caller MUST keep the returned token alive
    /// and call `removeTimeObserver(_:)` on deinit / onDisappear.
    ///
    /// The handler is called on `.main`; write to `@Published` properties
    /// directly — no actor hopping needed.
    func addPeriodicTimeObserver(
        interval: TimeInterval,
        handler: @escaping (TimeInterval) -> Void
    ) -> Any? {
        guard let player else { return nil }
        let cmInterval = CMTime(seconds: max(0.05, interval), preferredTimescale: 600)
        return player.addPeriodicTimeObserver(forInterval: cmInterval, queue: .main) { time in
            handler(CMTimeGetSeconds(time))
        }
    }

    /// Remove a token previously returned by `addPeriodicTimeObserver`.
    func removeTimeObserver(_ token: Any) {
        player?.removeTimeObserver(token)
    }

    // MARK: - Audio session

    private func activateSessionIfNeeded() {
        guard !sessionActivated else { return }
        sessionActivated = true
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .spokenAudio)
            try session.setActive(true)
        } catch {
            print("[Skrift] CapturePreviewPlayer audio session activation failed: \(error)")
        }
    }
}

// MARK: - Legacy GrainPlayer shim
//
// Grains are RETIRED in the Hybrid design — this stub keeps any stale callsites
// compiling. Remove in a follow-up cleanup pass.

@MainActor
final class GrainPlayer {
    func prepare(url: URL) {}
    func playGrain(at time: TimeInterval, length: TimeInterval = 0.45) {}
    func stop() {}
}
