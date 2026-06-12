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
    ///
    /// Deliberately does NOT touch the `AVAudioSession`: `prepareToPlay()` acquires
    /// the audio hardware (an implicit activation) and the `.playback` category is
    /// non-mixable, so doing either here stopped other apps' audio (Spotify) the
    /// moment a memo was merely OPENED. The session is claimed in `play()` only.
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
        self.player = player
        self.url = url
        duration = player.duration
        currentTime = 0
        hasAudio = true
    }

    func togglePlay() { isPlaying ? pause() : play() }

    func play() {
        guard let player else { return }
        // Mutual exclusion: pause the audiobook if it's playing so only one
        // audio source is active at a time. AudiobookSession uses AVPlayer
        // (spokenAudio category) and this player uses AVAudioPlayer (playback
        // category) — they compete for the same non-mixable session, so
        // whichever starts second would interrupt the first through the OS
        // interruption mechanism anyway. Pausing explicitly avoids the
        // AVAudioSession interruption callback path and the half-second
        // stutter it produces. The reverse direction (book play pausing this
        // player) is a follow-up: AudiobookSession.play() does NOT currently
        // pause AudioPlayerModel, so memo-playback → book-start can still
        // sound simultaneously. That direction requires AudiobookSession to
        // hold a reference to the active AudioPlayerModel — not done here to
        // respect the lane boundary (DO NOT TOUCH AudiobookSession.play()).
        if AudiobookSession.shared.isPlaying {
            AudiobookSession.shared.pause()
        }
        activateSession()
        player.rate = rate
        guard player.play() else {
            print("[Skrift] Playback failed to start: \(url?.lastPathComponent ?? "?")")
            deactivateSession()
            return
        }
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
        deactivateSession()
    }

    // MARK: - Audio session (claimed on Play, released on stop/finish)

    /// Whether WE hold the audio session. Activating it interrupts other apps'
    /// audio, so it happens strictly when the user presses Play — never on
    /// load/note-open — and the flag keeps `deactivateSession()` from stomping a
    /// session someone else (e.g. the append recorder) owns.
    private var sessionActive = false

    private func activateSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback)
            try session.setActive(true)
            sessionActive = true
        } catch {
            // play() still runs (it activates implicitly); log the why in case it fails too.
            print("[Skrift] Audio session activation failed: \(error)")
        }
    }

    /// Release the session so other audio (e.g. music) resumes where it paused.
    private func deactivateSession() {
        guard sessionActive else { return }
        sessionActive = false
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        } catch {
            print("[Skrift] Audio session deactivation failed: \(error)")
        }
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
            self.deactivateSession()   // hand the session back so e.g. music resumes
        }
    }
}
