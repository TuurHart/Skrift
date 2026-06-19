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
    /// Asymmetric skip (mock/spec: back 15 to re-hear, forward 30 to skip ahead).
    nonisolated static let skipBack: TimeInterval = 15
    nonisolated static let skipForward: TimeInterval = 30
    /// The compact mini-player keeps a symmetric 15s skip (it's a quick re-listen,
    /// not the redesigned full-player transport).
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
    /// Which of the book's files is loaded in the player (multi-file books
    /// play as ONE continuous book; `currentTime` stays GLOBAL).
    private var currentFileIndex = 0
    /// Fires when the loaded file plays to its end → auto-advance.
    private var itemEndObserver: NSObjectProtocol?

    init(store: AudiobookLibraryStore = .shared) {
        self.store = store
    }

    var duration: TimeInterval { book?.duration ?? 0 }

    // MARK: - Session lifecycle

    /// Load a book (seeking to its resume position — for a multi-file book,
    /// into the right FILE) and mark the session active. Re-opening the
    /// already-loaded book is a no-op (so the player screen can be re-entered
    /// freely).
    func open(_ newBook: Audiobook, autoplay: Bool = false) {
        if book?.id == newBook.id, player != nil {
            if autoplay, !isPlaying { play() }
            return
        }
        persistProgress(force: true)   // the outgoing book keeps its position
        closePlayer()

        // Cross-device resume: a CloudKit carrier may hold a further-along position
        // from another device that hasn't reconciled into library.json yet. Adopt it
        // when it's newer (and write it back so the store + future opens agree), so
        // opening on the iPad lands where you left off on the phone — even before
        // reconcile runs. A late-arriving newer position is handled by
        // adoptSyncedPosition() on CloudKit import.
        let startBook = newerSyncedBook(than: newBook) ?? newBook
        if startBook.modifiedAt > newBook.modifiedAt { store.update(startBook) }   // converge library.json
        let resume = min(startBook.position, startBook.duration)
        let location = startBook.fileLocation(at: resume)
        let url = store.audioURL(of: startBook, fileIndex: location.index)
        guard FileManager.default.fileExists(atPath: url.path) else {
            print("[Skrift] Audiobook audio missing: \(url.lastPathComponent)")
            return
        }
        let item = AVPlayerItem(asset: AVURLAsset(url: url))
        let avPlayer = AVPlayer(playerItem: item)
        avPlayer.automaticallyWaitsToMinimizeStalling = false
        player = avPlayer
        currentFileIndex = location.index
        observeItemEnd(of: item)
        book = startBook
        rate = startBook.playbackRate
        currentTime = resume
        coverImage = store.coverURL(of: newBook).flatMap { UIImage(contentsOfFile: $0.path) }
        seek(to: currentTime)
        isActive = true

        installTimeObserver(on: avPlayer)
        configureRemoteCommandsIfNeeded()
        installInterruptionObserverIfNeeded()
        updateNowPlaying()
        if autoplay { play() }
    }

    /// The CloudKit carrier's `Audiobook` if it holds a STRICTLY newer state than
    /// `local` (a further-along resume position from another device). Pure — the
    /// caller decides whether to write it back. nil if absent / not newer.
    private func newerSyncedBook(than local: Audiobook) -> Audiobook? {
        guard let rec = NotesRepository.shared.audiobookRecord(bookID: local.id),
              let synced = try? JSONDecoder().decode(Audiobook.self, from: rec.blob),
              synced.modifiedAt > local.modifiedAt else { return nil }
        return synced
    }

    /// Jump to a newer resume position that arrived from another device AFTER the
    /// book was opened — the cold-launch case where the CloudKit import lands a few
    /// seconds after you tapped the book. No-op while playing or when the delta is
    /// tiny, so we never yank you mid-listen. Called from `CloudSyncMonitor` on a
    /// CloudKit import.
    func adoptSyncedPosition() {
        guard let b = book, !isPlaying,
              let synced = newerSyncedBook(than: b),
              abs(synced.position - currentTime) > 5 else { return }
        store.update(synced)
        book = synced
        rate = synced.playbackRate
        seek(to: min(synced.position, synced.duration))
    }

    /// End the listening session: persist progress, release the player + audio
    /// session, drop the mini-player. The book stays in the library.
    func endSession() {
        cancelIdleEnd()
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
        // Mutual exclusion (reverse direction): starting the book pauses any
        // playing memo — AudioPlayerModel.play() does the same to this session.
        AudioPlayerModel.nowPlaying?.pause()
        activateAudioSession()
        player.playImmediately(atRate: Float(rate))
        isPlaying = true
        cancelIdleEnd()
        persistProgress(force: true)
        updateNowPlaying()
    }

    func pause() {
        guard let player else { return }
        player.pause()
        isPlaying = false
        scheduleIdleEnd()
        persistProgress(force: true)
        updateNowPlaying()
    }

    // MARK: - Idle auto-end (user 2026-06-11: "I'm always listening to one book
    // or another — the player will be there always"). A session paused this long
    // quietly ends so the mini-player disappears; nothing is lost (progress is
    // persisted per book, reopening from the Library resumes exactly).
    static let idleEndDelay: TimeInterval = 2 * 60 * 60
    private var idleEndTimer: Timer?

    private func scheduleIdleEnd() {
        idleEndTimer?.invalidate()
        idleEndTimer = Timer.scheduledTimer(withTimeInterval: Self.idleEndDelay, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isActive, !self.isPlaying else { return }
                self.endSession()
            }
        }
    }

    private func cancelIdleEnd() {
        idleEndTimer?.invalidate()
        idleEndTimer = nil
    }

    func togglePlay() { isPlaying ? pause() : play() }

    /// Siri / App Shortcut entry: resume the most recently played book (loads it
    /// if no session is active) and play. No-op when the library is empty —
    /// or while a memo recording is live (session priority: starting playback
    /// would tear the mic's audio session down).
    func resumeLastPlayed() {
        if LiveRecordingService.isRecordingActive { return }
        if book != nil { play(); return }
        guard let recent = store.sortedByRecent.first else { return }
        open(recent, autoplay: true)
    }

    func skip(_ delta: TimeInterval) { seek(to: currentTime + delta) }

    /// Seek to a GLOBAL book time. On a multi-file book this may swap the
    /// loaded file (e.g. the chapter menu, ⟲15 across a part boundary, or the
    /// lock-screen position scrubber).
    func seek(to time: TimeInterval) {
        guard let player, let book else { return }
        let clamped = max(0, min(time, duration))
        currentTime = clamped
        let location = book.fileLocation(at: clamped)
        if location.index != currentFileIndex {
            loadFile(at: location.index, of: book, offset: location.offset, resumePlayback: isPlaying)
        } else {
            player.seek(
                to: CMTime(seconds: location.offset, preferredTimescale: 600),
                toleranceBefore: .zero, toleranceAfter: .zero
            )
        }
        updateNowPlaying()
    }

    /// Swap the player onto file `index`, seeking to `offset` inside it. Keeps
    /// the transport state: `resumePlayback` restarts at the session rate.
    private func loadFile(at index: Int, of book: Audiobook, offset: TimeInterval, resumePlayback: Bool) {
        guard let player else { return }
        let url = store.audioURL(of: book, fileIndex: index)
        guard FileManager.default.fileExists(atPath: url.path) else {
            print("[Skrift] Audiobook part missing: \(url.lastPathComponent)")
            pause()
            return
        }
        let item = AVPlayerItem(asset: AVURLAsset(url: url))
        currentFileIndex = index
        player.replaceCurrentItem(with: item)
        observeItemEnd(of: item)
        player.seek(
            to: CMTime(seconds: max(0, offset), preferredTimescale: 600),
            toleranceBefore: .zero, toleranceAfter: .zero
        )
        if resumePlayback { player.playImmediately(atRate: Float(rate)) }
    }

    /// Re-aim the end-of-file notification at the CURRENT item (a stale
    /// observer on a replaced item would advance at the wrong moment).
    private func observeItemEnd(of item: AVPlayerItem) {
        if let itemEndObserver {
            NotificationCenter.default.removeObserver(itemEndObserver)
            self.itemEndObserver = nil
        }
        itemEndObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.currentFileEnded() }
        }
    }

    /// One part finished: auto-advance into the next file (the book plays as
    /// one continuous stream), or stop cleanly after the last file.
    private func currentFileEnded() {
        guard let book else { return }
        let next = currentFileIndex + 1
        guard next < book.files.count else {
            pause()   // end of the book
            return
        }
        let starts = book.fileStartTimes
        currentTime = starts.indices.contains(next) ? starts[next] : currentTime
        loadFile(at: next, of: book, offset: 0, resumePlayback: isPlaying)
        persistProgress(force: true)
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
            MainActor.assumeIsolated { self?.tick(itemTime: CMTimeGetSeconds(time)) }
        }
    }

    /// `itemTime` is the loaded FILE's clock; `currentTime` stays global
    /// (file start + item time).
    private func tick(itemTime: TimeInterval) {
        guard itemTime.isFinite else { return }
        let starts = book?.fileStartTimes ?? []
        let base = starts.indices.contains(currentFileIndex) ? starts[currentFileIndex] : 0
        let time = base + itemTime
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

    /// Re-read the loaded book's record after an out-of-band edit ("Edit book
    /// details"): title/author/cover refresh everywhere the session feeds
    /// (player, mini-player, lock-screen Now Playing) — playback position and
    /// transport state stay untouched.
    func refreshFromStore() {
        guard let current = book, let refreshed = store.book(id: current.id) else { return }
        book = refreshed
        coverImage = store.coverURL(of: refreshed).flatMap { UIImage(contentsOfFile: $0.path) }
        updateNowPlaying()
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
        if let itemEndObserver {
            NotificationCenter.default.removeObserver(itemEndObserver)
            self.itemEndObserver = nil
        }
        player?.pause()
        player = nil
        currentFileIndex = 0
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
        installRouteObserverIfNeeded()
    }

    /// Pause when the output route disappears (AirPods pulled out / BT drops) —
    /// the Apple convention for playback apps. Without this the book keeps
    /// playing OUT LOUD on the speaker the moment the headphones leave the ear.
    /// Re-inserting does NOT auto-resume (deliberate: resume is the user's tap
    /// or the AirPods' own play command, which the remote-command handler takes).
    private var routeObserver: NSObjectProtocol?
    private func installRouteObserverIfNeeded() {
        guard routeObserver == nil else { return }
        routeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { note in
            let reason = (note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt)
                .flatMap(AVAudioSession.RouteChangeReason.init)
            guard reason == .oldDeviceUnavailable else { return }
            Task { @MainActor in
                if AudiobookSession.shared.isPlaying {
                    DevLog.log("audiobook pause — output route lost (headphones removed)")
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

        // SESSION PRIORITY (device finding 2026-06-12): re-inserting AirPods
        // mid-recording fired the remote PLAY command into this session — the
        // book started playing over (and killed) the live memo recording.
        // Remote play (incl. AirPods auto-play and the lock screen) is
        // ignored while a recording session is live. Pause stays allowed.
        // `LiveRecordingService.isRecordingActive` is the cross-lane contract
        // symbol (@MainActor static Bool, true while a recording is live —
        // including paused), defined by the route-robustness lane.
        center.playCommand.addTarget { _ in
            Task { @MainActor in
                if LiveRecordingService.isRecordingActive { return }
                AudiobookSession.shared.play()
            }
            return .success
        }
        center.pauseCommand.addTarget { _ in
            Task { @MainActor in AudiobookSession.shared.pause() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { _ in
            Task { @MainActor in
                let session = AudiobookSession.shared
                // Only the PLAY direction yields to a live recording.
                if !session.isPlaying, LiveRecordingService.isRecordingActive { return }
                session.togglePlay()
            }
            return .success
        }
        center.skipBackwardCommand.preferredIntervals = [NSNumber(value: Self.skipBack)]
        center.skipBackwardCommand.addTarget { _ in
            Task { @MainActor in AudiobookSession.shared.skip(-Self.skipBack) }
            return .success
        }
        center.skipForwardCommand.preferredIntervals = [NSNumber(value: Self.skipForward)]
        center.skipForwardCommand.addTarget { _ in
            Task { @MainActor in AudiobookSession.shared.skip(Self.skipForward) }
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
