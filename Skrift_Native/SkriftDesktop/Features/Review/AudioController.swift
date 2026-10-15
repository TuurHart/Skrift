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
    /// Real duration of the loaded file (0 until it loads). Phone-metadata duration
    /// is only a label hint before load — locally-ingested audio has no metadata, so
    /// the transport gate + karaoke rely on this.
    var duration: Double = 0

    private var player: AVAudioPlayer?
    private var ticker: Timer?
    /// Bumped on every load so a slow async load that resolves after the user has
    /// already switched notes is ignored (no stale player).
    private var loadToken = 0
    @ObservationIgnored private var videoObserver: NSObjectProtocol?
    @ObservationIgnored private var fileChangeObserver: NSObjectProtocol?
    /// The file `load(path:)` was last pointed at.
    @ObservationIgnored private var loadedPath = ""

    /// Q453: posted on the main actor when a note's audio file was REPLACED IN PLACE at the
    /// same path (Add recording's splice, `MacAppendRecording.spliceAudio`). `object` is the
    /// path String. The open note's player re-opens it so playback runs past the old end.
    static let audioFileDidChange = Notification.Name("SkriftMacAudioFileDidChange")

    init() {
        // Pick 1 (mock Q384): a note's inline video starting pauses the note's own audio.
        videoObserver = NotificationCenter.default.addObserver(forName: NoteAttachment.inlineVideoStarted,
                                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.pause() }
        }
        fileChangeObserver = NotificationCenter.default.addObserver(forName: Self.audioFileDidChange,
                                                                    object: nil, queue: .main) { [weak self] note in
            guard let path = note.object as? String else { return }
            MainActor.assumeIsolated { self?.reloadIfSameFile(path: path) }
        }
    }

    deinit {
        if let videoObserver { NotificationCenter.default.removeObserver(videoObserver) }
        if let fileChangeObserver { NotificationCenter.default.removeObserver(fileChangeObserver) }
    }

    /// Q453: re-open the loaded file when `path` is it, keeping the position and the play state.
    func reloadIfSameFile(path: String) {
        guard !loadedPath.isEmpty,
              URL(fileURLWithPath: loadedPath).standardizedFileURL == URL(fileURLWithPath: path).standardizedFileURL,
              let fresh = try? AVAudioPlayer(contentsOf: URL(fileURLWithPath: path)), fresh.duration > 0 else { return }
        let wasPlaying = isPlaying
        let at = player?.currentTime ?? currentTime
        player?.stop()
        fresh.enableRate = true
        fresh.prepareToPlay()
        fresh.rate = rate
        fresh.currentTime = min(at, fresh.duration)
        player = fresh
        duration = fresh.duration
        currentTime = fresh.currentTime
        if wasPlaying { fresh.play() }
    }

    func pause() {
        guard isPlaying else { return }
        player?.pause(); isPlaying = false; stopTicker()
    }

    func load(path: String) {
        stop()
        player = nil
        currentTime = 0
        duration = 0
        loadToken += 1
        let token = loadToken
        loadedPath = path
        guard !path.isEmpty, FileManager.default.fileExists(atPath: path) else { return }
        let url = URL(fileURLWithPath: path)
        let wantRate = rate
        // AVAudioPlayer init + prepareToPlay can block ~1s for some files — keep it
        // off the main thread so switching notes stays snappy (N1). Assign back on
        // main only if this is still the latest requested load.
        Task.detached(priority: .userInitiated) {
            guard let p = try? AVAudioPlayer(contentsOf: url) else { return }
            p.enableRate = true
            p.prepareToPlay()
            await MainActor.run { [weak self] in
                guard let self, self.loadToken == token else { return }
                p.rate = wantRate
                self.player = p
                self.duration = p.duration
            }
        }
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
        rate = PlaybackRates.next(after: rate)   // C115: the one speed list
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
