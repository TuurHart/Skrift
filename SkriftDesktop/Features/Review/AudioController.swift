import SwiftUI
import AVFoundation

/// Drives the note's audio transport. Tolerant of a missing file (demo notes /
/// pre-ingest) — the toolbar still renders; playback is just inert until a real
/// `processed.wav`/`original.m4a` exists at `path`.
@MainActor
@Observable
final class AudioController {
    var isPlaying = false
    var currentTime: Double = 0
    var rate: Float = 1

    private var player: AVAudioPlayer?
    private var ticker: Timer?

    private static let rateSteps: [Float] = [0.75, 1, 1.25, 1.5, 2]

    func load(path: String) {
        stop()
        currentTime = 0
        guard !path.isEmpty, FileManager.default.fileExists(atPath: path),
              let p = try? AVAudioPlayer(contentsOf: URL(fileURLWithPath: path)) else {
            player = nil
            return
        }
        p.enableRate = true
        p.rate = rate
        p.prepareToPlay()
        player = p
    }

    func playPause() {
        guard let p = player else { return }
        if isPlaying {
            p.pause(); isPlaying = false; stopTicker()
        } else {
            p.rate = rate; p.play(); isPlaying = true; startTicker()
        }
    }

    func seek(to t: Double) {
        guard let p = player else { return }
        let clamped = max(0, min(p.duration, t))
        p.currentTime = clamped
        currentTime = clamped
    }

    func skip(_ delta: Double) {
        guard let p = player else { return }
        seek(to: p.currentTime + delta)
    }

    func cycleRate() {
        let i = Self.rateSteps.firstIndex(of: rate) ?? 1
        rate = Self.rateSteps[(i + 1) % Self.rateSteps.count]
        player?.rate = rate
    }

    private func startTicker() {
        stopTicker()
        ticker = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let p = self.player else { return }
                self.currentTime = p.currentTime
                if !p.isPlaying && self.isPlaying { self.isPlaying = false; self.stopTicker() }
            }
        }
    }

    private func stopTicker() { ticker?.invalidate(); ticker = nil }

    private func stop() {
        player?.stop()
        isPlaying = false
        stopTicker()
    }
}
