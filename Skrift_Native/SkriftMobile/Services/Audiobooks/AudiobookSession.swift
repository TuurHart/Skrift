import AVFoundation
import Foundation
import MediaPlayer
import Observation
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
///
/// Q57/C218: `@Observable` (per-property, like `LiveRecordingService`), not
/// `ObservableObject`/`@Published` — the old combined `objectWillChange` meant
/// the 0.5 s `currentTime` tick re-rendered EVERY view holding `.shared`
/// (mini player, library rows, chapters sheet, …) even ones that never read
/// `currentTime`. Fine-grained observation isolates the tick to only the
/// views that actually read it.
@MainActor
@Observable
final class AudiobookSession {
    static let shared = AudiobookSession()

    /// C3: a book session is active (playing or paused-with-book-loaded).
    var isActive: Bool = false
    private(set) var book: Audiobook?
    private(set) var isPlaying = false
    private(set) var currentTime: TimeInterval = 0
    private(set) var rate: Double = 1.0
    /// Wall-clock the sleep timer fires (nil = off / end-of-chapter mode).
    private(set) var sleepUntil: Date?
    /// Sleep at the end of the current chapter.
    private(set) var sleepAtChapterEnd = false

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
    /// WE were playing and an interruption paused us — so an `.ended` carrying
    /// `.shouldResume` is ours to act on. Cleared by any user-intent transport
    /// (`play`/`pause`/`endSession`), so a book the user paused themselves is
    /// NEVER auto-resumed by an unrelated interruption ending.
    ///
    /// The 2026-07-25 report ("midway through it stopped and the song started
    /// playing again") is this gap: `.began` paused us, `.ended` did nothing,
    /// and Deezer — which honours `.shouldResume` — took the route back. The
    /// "aggressive" competitor was just implementing the whole contract.
    fileprivate var pausedByInterruption = false
    /// Latched by the tick's silent-stop detector so the log records the moment
    /// AVPlayer stopped producing audio ONCE, not twice a second. Cleared on
    /// play/pause. Pure diagnostics — no behaviour hangs off it.
    private var stalled = false
    /// One line per session when the playhead passes the stored duration on a
    /// non-final file (bad metadata) — diagnostics, drives nothing.
    private var metadataShortfallLogged = false

    init(store: AudiobookLibraryStore = .shared) {
        self.store = store
    }

    var duration: TimeInterval { book?.duration ?? 0 }

    // MARK: - Session lifecycle

    /// Load a book (seeking to its resume position — for a multi-file book,
    /// into the right FILE) and mark the session active. Re-opening the
    /// already-loaded book is a no-op (so the player screen can be re-entered
    /// freely).
    @discardableResult
    func open(_ newBook: Audiobook, autoplay: Bool = false) -> Bool {
        if book?.id == newBook.id, player != nil {
            if autoplay, !isPlaying { play() }
            return true
        }
        // Cross-device resume: a CloudKit carrier may hold a further-along position
        // from another device that hasn't reconciled into library.json yet. Adopt it
        // when it's newer (and write it back so the store + future opens agree), so
        // opening on the iPad lands where you left off on the phone — even before
        // reconcile runs. A late-arriving newer position is handled by
        // adoptSyncedPosition() on CloudKit import.
        let startBook = newerSyncedBook(than: newBook)?.keepingLocalTextFields(from: newBook) ?? newBook
        if startBook.modifiedAt > newBook.modifiedAt { store.update(startBook) }   // converge library.json
        let resume = min(startBook.position, startBook.duration)
        let location = startBook.fileLocation(at: resume)
        let url = store.audioURL(of: startBook, fileIndex: location.index)
        // Validate the audio is on disk BEFORE any teardown. A synced book whose
        // audio hasn't downloaded yet (or was freed on this device) must NOT tear
        // down the currently-playing session or leave a dead player behind — bail
        // and let the caller trigger a download (Apple Books "tap to download").
        guard FileManager.default.fileExists(atPath: url.path) else {
            print("[Skrift] Audiobook audio missing: \(url.lastPathComponent)")
            return false
        }

        persistProgress(force: true)   // the outgoing book keeps its position
        closePlayer()

        let item = AVPlayerItem(asset: AudiobookImporter.makeAsset(url: url))
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
        // Retro path: a book fully transcribed before transcript-chapter
        // detection shipped gets its chapters on first open (no-op otherwise).
        BookTranscriptionJob.shared.detectChaptersIfNeeded(bookID: startBook.id)
        // 📖 spike 6: same retro idea for alignment — cheap no-op unless an
        // ePub is attached and some file's sidecar is stale.
        Task { await BookAlignmentRunner.alignIfNeeded(bookID: startBook.id) }
        return true
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
              let synced = newerSyncedBook(than: b)?.keepingLocalTextFields(from: b),
              abs(synced.position - currentTime) > 5 else { return }
        store.update(synced)
        book = synced
        rate = synced.playbackRate
        seek(to: min(synced.position, synced.duration))
    }

    /// End the listening session: persist progress, release the player + audio
    /// session, drop the mini-player. The book stays in the library.
    func endSession() {
        DevLog.log("audiobook endSession — book=\(book?.title ?? "-")"
                   + " at=\(String(format: "%.1f", currentTime))s wasPlaying=\(isPlaying)")
        cancelIdleEnd()
        persistProgress(force: true)
        closePlayer()
        book = nil
        coverImage = nil
        isActive = false
        pausedByInterruption = false   // nothing left to resume into
        metadataShortfallLogged = false
        clearSleep()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        deactivateAudioSession()
    }

    // MARK: - Transport

    func play() {
        guard let player, book != nil else { return }
        pausedByInterruption = false   // user intent supersedes any latch
        // Mutual exclusion (reverse direction): starting the book pauses any
        // playing memo — AudioPlayerModel.play() does the same to this session.
        AudioPlayerModel.nowPlaying?.pause()
        activateAudioSession()
        player.playImmediately(atRate: Float(rate))
        isPlaying = true
        stalled = false
        DevLog.log("audiobook play — at=\(String(format: "%.1f", currentTime))s rate=\(rate)")
        cancelIdleEnd()
        persistProgress(force: true)
        updateNowPlaying()
    }

    func pause() {
        guard let player else { return }
        pausedByInterruption = false   // a plain pause is user intent, not ours to undo
        DevLog.log("audiobook pause — at=\(String(format: "%.1f", currentTime))s"
                   + " of \(String(format: "%.1f", duration))s")
        player.pause()
        isPlaying = false
        stalled = false
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
        let item = AVPlayerItem(asset: AudiobookImporter.makeAsset(url: url))
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
        DevLog.log("audiobook file \(currentFileIndex + 1)/\(book.files.count) played to end"
                   + " at \(String(format: "%.1f", currentTime))s")
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
        DevLog.log("audiobook sleep timer fired — pausing")
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
        // SILENT-STOP DETECTOR (2026-07-25): we believe we're playing — does
        // AVPlayer agree? When the session is yanked out from under us (another
        // app taking the route, a category change, mediaservices dying) AVPlayer
        // just stops: no interruption callback fires, `isPlaying` stays true, and
        // the UI keeps claiming playback while the phone is silent. Latched to one
        // line per stall, with the reason AVPlayer gives for not playing.
        if let player, player.timeControlStatus != .playing {
            if !stalled {
                stalled = true
                DevLog.log("audiobook SILENT STOP — timeControlStatus="
                           + "\(player.timeControlStatus.rawValue)"
                           + " waitingReason=\(player.reasonForWaitingToPlay?.rawValue ?? "-")"
                           + " at=\(String(format: "%.1f", time))s"
                           + " itemStatus=\(player.currentItem?.status.rawValue ?? -1)"
                           + " sessionActive=\(audioSessionActive)"
                           + " route=\(AudiobookSession.describeRoute())")
                recoverFromSilentStop(at: time)
            }
        } else if stalled {
            stalled = false
            DevLog.log("audiobook resumed producing audio at \(String(format: "%.1f", time))s")
        }
        persistProgress()   // throttled inside
        // End-of-chapter sleep: pause the moment the chapter index moves on.
        if sleepAtChapterEnd, let armed = sleepChapterIndex,
           let now = book?.chapterIndex(at: time), now != armed {
            sleepFired()
        }
        // End of book: stop cleanly at the final position — but ONLY on the last
        // file. `duration` is the STORED metadata duration, and a book whose
        // metadata under-reports its real length used to trip this mid-listen,
        // reading as "the book just stopped" (2026-07-25 report shape). On an
        // earlier file the real end-of-file signal is the item-end observer,
        // which auto-advances; a metadata shortfall there is now ignored.
        let isLastFile = Self.isFinalFile(index: currentFileIndex, fileCount: book?.files.count ?? 1)
        if duration > 0, time >= duration - 0.25 {
            if isLastFile {
                DevLog.log("audiobook end-of-book pause — time=\(String(format: "%.1f", time))s"
                           + " >= duration=\(String(format: "%.1f", duration))s"
                           + " file=\(currentFileIndex + 1)/\(book?.files.count ?? 0)")
                pause()
            } else if !metadataShortfallLogged {
                metadataShortfallLogged = true
                DevLog.log("audiobook metadata SHORTFALL — time=\(String(format: "%.1f", time))s"
                           + " passed stored duration=\(String(format: "%.1f", duration))s"
                           + " on file \(currentFileIndex + 1)/\(book?.files.count ?? 0)"
                           + " — NOT pausing (item-end drives the advance)")
            }
        }
    }

    /// The session was yanked and AVPlayer stopped with no interruption
    /// callback (`timeControlStatus != .playing` while `isPlaying`). Re-assert
    /// the session and push play — the same repair `play()` does, minus the
    /// user-intent side effects. Best-effort and self-limiting: `stalled`
    /// latches, so this runs once per stall, not twice a second.
    private func recoverFromSilentStop(at time: TimeInterval) {
        guard isPlaying, !LiveRecordingService.isRecordingActive else {
            DevLog.log("audiobook silent-stop recovery SKIPPED — a recording owns the session")
            return
        }
        DevLog.log("audiobook silent-stop RECOVERY — re-activating + playImmediately")
        activateAudioSession()
        player?.playImmediately(atRate: Float(rate))
        updateNowPlaying()
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
            DevLog.log("audiobook session ACTIVATED — route=\(AudiobookSession.describeRoute())")
        } catch {
            // NOTE: play() carries on regardless — so a failure here shows as
            // "playing" in the UI with no sound. Logged so that's not invisible.
            DevLog.log("audiobook session activation FAILED — \(error)")
            print("[Skrift] Audiobook audio session activation failed: \(error)")
        }
    }

    /// Hands the route back to whatever we interrupted (`.notifyOthersOnDeactivation`
    /// is literally "other app, resume now") — so every call here is a potential
    /// "my music started playing again" report. Only `endSession()` should reach it.
    private func deactivateAudioSession() {
        guard audioSessionActive else { return }
        audioSessionActive = false
        DevLog.log("audiobook session DEACTIVATED (notifyOthersOnDeactivation — others may resume)")
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
            let type = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt)
                .flatMap(AVAudioSession.InterruptionType.init)
            let began = type == .began
            // DIAGNOSIS (2026-07-25 "the book stops and Deezer resumes"): we only
            // ever ACT on `.began`. `.ended` is logged but unhandled — so after any
            // transient interruption the book stays silent while a competitor that
            // DOES honour `.shouldResume` takes the route back. Log both directions
            // (with the resume hint + who owns the route) so a device pull proves
            // whether an interruption is what killed playback.
            let opts = AVAudioSession.InterruptionOptions(
                rawValue: note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0)
            let reasonRaw = note.userInfo?[AVAudioSessionInterruptionReasonKey] as? UInt
            Task { @MainActor in
                let session = AudiobookSession.shared
                DevLog.log("audiobook interruption \(began ? "BEGAN" : "ENDED")"
                           + " — wasPlaying=\(session.isPlaying)"
                           + " pausedByInterruption=\(session.pausedByInterruption)"
                           + " shouldResume=\(opts.contains(.shouldResume))"
                           + " reasonRaw=\(reasonRaw?.description ?? "-")"
                           + " route=\(AudiobookSession.describeRoute())")
                if began {
                    // Latch BEFORE pausing — pause() clears the latch (it's the
                    // user-intent signal), so the order matters.
                    if session.isPlaying {
                        session.pause()
                        session.pausedByInterruption = true
                    }
                } else {
                    session.resumeAfterInterruptionIfOurs(shouldResume: opts.contains(.shouldResume))
                }
            }
        }
        installRouteObserverIfNeeded()
    }

    /// Whether the loaded file is the book's last — the ONLY file on which
    /// passing the stored duration means "end of book". Pure so the guard that
    /// used to stop multi-file books mid-listen (bad metadata) is testable.
    nonisolated static func isFinalFile(index: Int, fileCount: Int) -> Bool {
        index >= max(0, fileCount - 1)
    }

    /// Whether an interruption `.ended` should resume playback. Pure mirror of
    /// `resumeAfterInterruptionIfOurs`'s decision, so the contract that broke
    /// the 2026-07-25 report is unit-pinned: resume only OUR pause, only with
    /// the system's `shouldResume` hint, never over a live recording.
    nonisolated static func shouldResumeAfterInterruption(
        pausedByInterruption: Bool,
        shouldResumeHint: Bool,
        recordingActive: Bool
    ) -> Bool {
        pausedByInterruption && shouldResumeHint && !recordingActive
    }

    /// Interruption `.ended`: resume ONLY the pause we caused. Two guards, both
    /// load-bearing — `shouldResume` is the system saying the route is ours
    /// again, and the latch is us saying we didn't stop on purpose. Without the
    /// latch a user-paused book would spring to life whenever an unrelated
    /// interruption ended; without `shouldResume` we'd fight whoever now owns
    /// the route.
    ///
    /// Re-activating first matters: after an interruption our session is
    /// deactivated, so `playImmediately` alone would play into a dead session
    /// (the classic "UI says playing, phone is silent").
    fileprivate func resumeAfterInterruptionIfOurs(shouldResume: Bool) {
        guard pausedByInterruption else { return }
        guard shouldResume else {
            // No resume hint: whoever interrupted still holds the route. Drop
            // the latch — resuming later on a stale interruption would yank
            // audio back from an app the user is now actively using.
            pausedByInterruption = false
            DevLog.log("audiobook interruption ended WITHOUT shouldResume — staying paused")
            return
        }
        guard !LiveRecordingService.isRecordingActive else {
            // Session priority (the 2026-06-12 device finding): a live recording
            // outranks playback. Keep the latch — the recorder's stop is not an
            // interruption end, so this book stays paused until the user taps.
            DevLog.log("audiobook interruption ended — deferring, a recording is live")
            return
        }
        pausedByInterruption = false
        DevLog.log("audiobook interruption ended — RESUMING (our pause, shouldResume set)")
        play()
    }

    /// Current output route, for the DevLog traces (e.g. "AirPods Pro").
    private static func describeRoute() -> String {
        let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
        return outputs.isEmpty ? "none" : outputs.map(\.portName).joined(separator: "+")
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
            Task { @MainActor in
                let session = AudiobookSession.shared
                // Log EVERY route change while a book session exists — a route flip
                // is the other way the book can lose the output from under it
                // (AirPods handing back to a competing app, `.categoryChange` from
                // our own recorder claiming .playAndRecord, `.routeConfigurationChange`).
                if session.isActive {
                    // rawValue, not the case name: an imported NS_ENUM has no
                    // guaranteed readable description. 2=oldDeviceUnavailable,
                    // 3=categoryChange, 6=routeConfigurationChange.
                    DevLog.log("audiobook route change — reasonRaw=\(reason?.rawValue.description ?? "?")"
                               + " playing=\(session.isPlaying) route=\(AudiobookSession.describeRoute())")
                }
                guard reason == .oldDeviceUnavailable else { return }
                if session.isPlaying {
                    DevLog.log("audiobook pause — output route lost (headphones removed)")
                    session.pause()
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
        // OWN the transport (Tuur's Spotify-vs-Deezer point 2026-07-25): commands
        // left ENABLED but unhandled make us look like a half-working now-playing
        // app to iOS — the system can route a next/previous press to us and get
        // nothing, and the "which app owns playback" arbitration reads a
        // partially-claimed transport. A book has no tracks: say so explicitly.
        center.nextTrackCommand.isEnabled = false
        center.previousTrackCommand.isEnabled = false
        center.seekForwardCommand.isEnabled = false
        center.seekBackwardCommand.isEnabled = false
        // …and the ones we DO implement are enabled explicitly, so ownership is
        // stated rather than inherited from whatever the last app configured.
        center.playCommand.isEnabled = true
        center.pauseCommand.isEnabled = true
        center.togglePlayPauseCommand.isEnabled = true
        center.skipForwardCommand.isEnabled = true
        center.skipBackwardCommand.isEnabled = true
        center.changePlaybackPositionCommand.isEnabled = true
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
        // State the transport state EXPLICITLY. Inferring it from the playback
        // rate is ambiguous (rate 0 reads as both "paused" and "stopped"), and
        // an app that never declares .playing is easy for the system to treat
        // as the stale now-playing entry when another app wants the slot.
        MPNowPlayingInfoCenter.default().playbackState = isPlaying ? .playing : .paused
    }
}
