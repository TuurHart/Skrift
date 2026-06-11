import AVFoundation
import Foundation

/// Snippet audio scrubbing for the capture micro-scrubber (v1 of the locked
/// design): as a marker handle settles, play a short grain (~half a second) of
/// the book at the scrub position so you can hear where you are. A second,
/// dedicated AVPlayer on the same file — the session's player stays paused at
/// the capture position. DaVinci-style varispeed scrubbing is the v2 polish.
@MainActor
final class GrainPlayer {
    private var player: AVPlayer?
    private var url: URL?
    private var stopTask: Task<Void, Never>?

    /// Point the grain player at the book's audio (idempotent).
    func prepare(url: URL) {
        guard url != self.url else { return }
        stop()
        player = AVPlayer(playerItem: AVPlayerItem(asset: AVURLAsset(url: url)))
        player?.automaticallyWaitsToMinimizeStalling = false
        self.url = url
    }

    /// Play `length` seconds at `time`. A new grain cancels the previous one.
    func playGrain(at time: TimeInterval, length: TimeInterval = 0.45) {
        guard let player else { return }
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
}
