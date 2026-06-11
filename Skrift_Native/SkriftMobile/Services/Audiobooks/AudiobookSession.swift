import AVFoundation
import Combine
import Foundation
import MediaPlayer
import UIKit

/// The one active audiobook listening session (CROSS-LANE CONTRACT C3): a
/// `@MainActor` singleton whose `isActive` flag gates the conditional
/// mini-player — true while a book session exists (playing OR paused with a
/// book loaded), false otherwise. Other surfaces reference ONLY
/// `AudiobookSession.shared.isActive` + `AudiobookMiniPlayerBar()`.
///
/// One book at a time "moves in" (Bound model): opening a book ends the
/// previous session. AVPlayer (not AVAudioPlayer) so a 15 h m4b streams from
/// disk instead of loading whole, with speed + background playback + the
/// lock-screen transport (MPNowPlayingInfoCenter / MPRemoteCommandCenter).
@MainActor
final class AudiobookSession: ObservableObject {
    static let shared = AudiobookSession()

    /// C3: a book session is active (playing or paused-with-book-loaded).
    @Published var isActive: Bool = false
    @Published private(set) var book: Audiobook?
    @Published private(set) var isPlaying = false
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var rate: Double = 1.0
    /// Wall-clock the sleep timer fires (nil = off / end-of-chapter mode).
    @Published private(set) var sleepUntil: Date?
    /// Sleep at the end of the current chapter.
    @Published private(set) var sleepAtChapterEnd = false

    // nonisolated: plain Sendable constants — referenced from non-main contexts
    // (remote-command handler closures) without an actor hop.
    nonisolated static let rates: [Double] = [0.75, 1.0, 1.25, 1.5, 1.75, 2.0]
    nonisolated static let skipInterval: TimeInterval = 15

    let store: AudiobookLibraryStore

    private var player: AVPlayer?
    private var timeObserverToken: Any?
    private var lastPersist = Date.distantPast
    private var sleepTimer: Timer?
    private var commandsConfigured = false
    private var interruptionObserver: NSObjectProtocol?
    private var coverImage: UIImage?
    /// Chapter index when the end-of-chapter sleep was armed.
    private var sleepChapterIndex: Int?

    init(store: AudiobookLibraryStore = .shared) {
        self.store = store
    }

    var duration: TimeInterval { book?.duration ?? 0 }

    // MARK: - Session lifecycle

    /// Load a book (seeking to its resume position) and mark the session
    /// active. Re-opening the already-loaded book is a no-op (so the player
    /// screen can be re-entered freely).
    func open(_ newBook: Audiobook, autoplay: Bool = false) {
        if book?.id == newBook.id, player != nil {
            if autoplay, !isPlaying { play() }
            return
        }
        persistProgress(force: true)   // the outgoing book keeps its position
        closePlayer()

        let url = store.audioURL(of: newBook)
        guard FileManager.default.fileExists(atPath: url.path) else {
            print("[Skrift] Audiobook audio missing: \(url.lastPathComponent)")
            return
        }
        let avPlayer = AVPlayer(playerItem: AVPlayerItem(asset: AVURLAsset(url: url)))
        avPlayer.automaticallyWaitsToMinimizeStalling = false
        player = avPlayer
        book = newBook
        rate = newBook.playbackRate
        currentTime = min(newBook.position, newBook.duration)
        coverImage = store.coverURL(of: newBook).flatMap { UIImage(contentsOfFile: $0.path) }
        seek(to: currentTime)
        isActive = true

        installTimeObserver(on: avPlayer)
        configureRemoteCommandsIfNeeded()
        installInterruptionObserverIfNeeded()
        updateNowPlaying()
        if autoplay { play() }
    }

    /// End the listening session: persist progress, release the player + audio
    /// session, drop the mini-player. The book stays in the library.
    func endSession() {
        persistProgress(force: true)
        closePlayer()
        book = nil
        coverImage = nil
        isActive = false
        clearSleep()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        deactivateAudioSession()
    }

    // MARK: - Transport

    func play() {
        guard let player, book != nil else { return }
        activateAudioSession()
        player.playImmediately(atRate: Float(rate))
        isPlaying = true
        persistProgress(force: true)
        updateNowPlaying()
    }

    func pause() {
        guard let player else { return }
        player.pause()
        isPlaying = false
        persistProgress(force: true)
        updateNowPlaying()
    }

    func togglePlay() { isPlaying ? pause() : play() }

    func skip(_ delta: TimeInterval) { seek(to: currentTime + delta) }

    func seek(to time: TimeInterval) {
        guard let player else { return }
        let clamped = max(0, min(time, duration))
        currentTime = clamped
        player.seek(
            to: CMTime(seconds: clamped, preferredTimescale: 600),
            toleranceBefore: .zero, toleranceAfter: .zero
        )
        updateNowPlaying()
    }

    func setRate(_ newRate: Double) {
        rate = newRate
        if var b = book {
            b.playbackRate = newRate
            book = b
            store.updateRate(id: b.id, rate: newRate)
        }
        if isPlaying { player?.rate = Float(newRate) }
        updateNowPlaying()
    }

    // MARK: - Sleep timer

    enum SleepOption: Equatable {
        case off
        case minutes(Int)
        case endOfChapter
    }

    func setSleep(_ option: SleepOption) {
        clearSleep()
        switch option {
        case .off:
            break
        case .minutes(let m):
            let fire = Date().addingTimeInterval(TimeInterval(m) * 60)
            sleepUntil = fire
            let timer = Timer(fire: fire, interval: 0, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.sleepFired() }
            }
            RunLoop.main.add(timer, forMode: .common)
            sleepTimer = timer
        case .endOfChapter:
            sleepAtChapterEnd = true
            sleepChapterIndex = book?.chapterIndex(at: currentTime)
        }
    }

    /// "Sleep · off" / "Sleep · 12m" / "Sleep · ch. end" for the player chip.
    var sleepLabel: String {
        if sleepAtChapterEnd { return "Sleep · ch. end" }
        guard let sleepUntil else { return "Sleep · off" }
        let remaining = max(0, sleepUntil.timeIntervalSinceNow)
        return "Sleep · \(max(1, Int((remaining / 60).rounded())))m"
    }

    private func sleepFired() {
        pause()
        clearSleep()
    }

    private func clearSleep() {
        sleepTimer?.invalidate()
        sleepTimer = nil
        sleepUntil = nil
        sleepAtChapterEnd = false
        sleepChapterIndex = nil
    }

    // MARK: - Periodic tick

    private func installTimeObserver(on player: AVPlayer) {
        timeObserverToken = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated { self?.tick(CMTimeGetSeconds(time)) }
        }
    }

    private func tick(_ time: TimeInterval) {
        guard time.isFinite else { return }
        currentTime = time

        guard isPlaying else { return }
        persistProgress()   // throttled inside
        // End-of-chapter sleep: pause the moment the chapter index moves on.
        if sleepAtChapterEnd, let armed = sleepChapterIndex,
           let now = book?.chapterIndex(at: time), now != armed {
            sleepFired()
        }
        // End of book: stop cleanly at the final position.
        if duration > 0, time >= duration - 0.25 {
            pause()
        }
    }

    /// Write the resume position through to the library store. Unforced calls
    /// (the playback tick) throttle to one write per 5 s; transport actions
    /// force an immediate write.
    private func persistProgress(force: Bool = false) {
        guard let book else { return }
        if !force, Date().timeIntervalSince(lastPersist) < 5 { return }
        lastPersist = Date()
        store.updateProgress(id: book.id, position: currentTime)
        if let refreshed = store.book(id: book.id) {
            self.book = refreshed
        }
    }

    private func closePlayer() {
        if let token = timeObserverToken {
            player?.removeTimeObserver(token)
            timeObserverToken = nil
        }
        player?.pause()
        player = nil
        isPlaying = false
    }

    // MARK: - Audio session

    private var audioSessionActive = false

    private func activateAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .spokenAudio)
            try session.setActive(true)
            audioSessionActive = true
        } catch {
            print("[Skrift] Audiobook audio session activation failed: \(error)")
        }
    }

    private func deactivateAudioSession() {
        guard audioSessionActive else { return }
        audioSessionActive = false
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        } catch {
            print("[Skrift] Audiobook audio session deactivation failed: \(error)")
        }
    }

    private func installInterruptionObserverIfNeeded() {
        guard interruptionObserver == nil else { return }
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { note in
            let began = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt)
                .flatMap(AVAudioSession.InterruptionType.init) == .began
            Task { @MainActor in
                if began, AudiobookSession.shared.isPlaying {
                    AudiobookSession.shared.pause()
                }
            }
        }
    }

    // MARK: - Lock-screen transport (Now Playing + remote commands)

    private func configureRemoteCommandsIfNeeded() {
        guard !commandsConfigured else { return }
        commandsConfigured = true
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.addTarget { _ in
            Task { @MainActor in AudiobookSession.shared.play() }
            return .success
        }
        center.pauseCommand.addTarget { _ in
            Task { @MainActor in AudiobookSession.shared.pause() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { _ in
            Task { @MainActor in AudiobookSession.shared.togglePlay() }
            return .success
        }
        center.skipBackwardCommand.preferredIntervals = [NSNumber(value: Self.skipInterval)]
        center.skipBackwardCommand.addTarget { _ in
            Task { @MainActor in AudiobookSession.shared.skip(-Self.skipInterval) }
            return .success
        }
        center.skipForwardCommand.preferredIntervals = [NSNumber(value: Self.skipInterval)]
        center.skipForwardCommand.addTarget { _ in
            Task { @MainActor in AudiobookSession.shared.skip(Self.skipInterval) }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { event in
            guard let position = (event as? MPChangePlaybackPositionCommandEvent)?.positionTime else {
                return .commandFailed
            }
            Task { @MainActor in AudiobookSession.shared.seek(to: position) }
            return .success
        }
    }

    private func updateNowPlaying() {
        guard let book else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: book.title,
            MPMediaItemPropertyArtist: book.author,
            MPMediaItemPropertyPlaybackDuration: book.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? rate : 0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
        ]
        if let line = book.chapterLine(at: currentTime) {
            info[MPMediaItemPropertyAlbumTitle] = line
        }
        if let image = coverImage {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
