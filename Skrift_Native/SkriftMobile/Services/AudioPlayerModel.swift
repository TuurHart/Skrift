import AVFoundation
import Combine
import Foundation

/// Local playback for Memo detail: load a memo's `.m4a`, play/pause, scrub, ±10s,
/// and cycle speed (1× / 1.5× / 2×). A missing/empty file (e.g. seeded demo memos
/// in the sim) loads to a disabled zero-duration state rather than crashing.
@MainActor
final class AudioPlayerModel: NSObject, ObservableObject {
    @Published private(set) var isPlaying = false
    @Published var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var rate: Float = 1
    @Published private(set) var hasAudio = false

    private var player: AVAudioPlayer?
    private var timer: Timer?
    private(set) var url: URL?

    private static let rates: [Float] = [1, 1.5, 2]

    /// Point the player at a memo's audio (or clear it). No-op if it's already
    /// loaded, so swiping back to a page doesn't restart it.
    func load(_ url: URL?) {
        if url == self.url { return }
        stopAndClear()
        guard let url, FileManager.default.fileExists(atPath: url.path),
              let player = try? AVAudioPlayer(contentsOf: url), player.duration > 0 else {
            hasAudio = false
            return
        }
        player.delegate = self
        player.enableRate = true
        player.rate = rate
        player.prepareToPlay()
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        self.player = player
        self.url = url
        duration = player.duration
        currentTime = 0
        hasAudio = true
    }

    func togglePlay() { isPlaying ? pause() : play() }

    func play() {
        guard let player else { return }
        try? AVAudioSession.sharedInstance().setActive(true)
        player.rate = rate
        player.play()
        isPlaying = true
        startTimer()
    }

    func pause() {
        player?.pause()
        isPlaying = false
        stopTimer()
    }

    func seek(to time: TimeInterval) {
        guard let player else { return }
        let clamped = max(0, min(time, duration))
        player.currentTime = clamped
        currentTime = clamped
    }

    func skip(_ delta: TimeInterval) { seek(to: currentTime + delta) }

    func cycleRate() {
        let next = Self.rates[(Self.rates.firstIndex(of: rate).map { $0 + 1 } ?? 0) % Self.rates.count]
        rate = next
        if isPlaying { player?.rate = next }
    }

    func stopAndClear() {
        player?.stop()
        player = nil
        url = nil
        isPlaying = false
        currentTime = 0
        duration = 0
        hasAudio = false
        stopTimer()
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let player = self.player else { return }
                self.currentTime = player.currentTime
            }
        }
    }

    private func stopTimer() { timer?.invalidate(); timer = nil }
}

extension AudioPlayerModel: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.isPlaying = false
            self.currentTime = 0
            self.stopTimer()
        }
    }
}
