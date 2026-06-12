import AVFoundation
import Foundation

/// Snippet audio scrubbing for the capture micro-scrubber (v1 of the locked
/// design): while a marker handle is being dragged, play short grains
/// (~half a second) of the book at the scrub position so you can hear where
/// you are. A second, dedicated AVPlayer on the same file — the session's
/// player stays paused at the capture position. DaVinci-style varispeed
/// scrubbing is the v2 polish.
///
/// Capture round 2 (device finding 2026-06-12): grains sound ONLY while a
/// finger actively drags — the view calls `stop()` the moment the drag ends —
/// and NOTHING here touches the audio route until the first grain actually
/// plays. `prepare(url:)` only builds the player; the AVAudioSession is
/// activated lazily inside `playGrain` (first drag). Opening the capture
/// screen used to yank the user's AirPods off their Mac.
@MainActor
final class GrainPlayer {
    private var player: AVPlayer?
    private var url: URL?
    private var stopTask: Task<Void, Never>?
    private var sessionActivated = false

    /// Point the grain player at the book's audio (idempotent). Builds the
    /// player only — must NOT activate the audio session (route stays put
    /// until the first drag).
    func prepare(url: URL) {
        guard url != self.url else { return }
        stop()
        player = AVPlayer(playerItem: AVPlayerItem(asset: AVURLAsset(url: url)))
        player?.automaticallyWaitsToMinimizeStalling = false
        self.url = url
    }

    /// Play `length` seconds at `time`. A new grain cancels the previous one.
    /// The FIRST grain claims the audio session — this is the one deliberate
    /// route grab, tied to an actual finger drag.
    func playGrain(at time: TimeInterval, length: TimeInterval = 0.45) {
        guard let player else { return }
        activateSessionIfNeeded()
        stopTask?.cancel()
        player.pause()
        player.seek(
            to: CMTime(seconds: max(0, time), preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: CMTime(seconds: 0.05, preferredTimescale: 600)
        ) { [weak player] finished in
            guard finished else { return }
            player?.play()   // AVPlayer transport is thread-safe
        }
        stopTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(length))
            guard !Task.isCancelled else { return }
            self?.player?.pause()
        }
    }

    func stop() {
        stopTask?.cancel()
        stopTask = nil
        player?.pause()
    }

    /// Same category/mode the book session uses, so the takeover (when it
    /// finally happens) is seamless with playback.
    private func activateSessionIfNeeded() {
        guard !sessionActivated else { return }
        sessionActivated = true
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .spokenAudio)
            try session.setActive(true)
        } catch {
            print("[Skrift] Grain audio session activation failed: \(error)")
        }
    }
}
