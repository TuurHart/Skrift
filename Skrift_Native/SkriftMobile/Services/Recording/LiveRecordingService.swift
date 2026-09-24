import AVFoundation
import Foundation
import Observation
import UIKit

/// Drives a recording with a single `AVAudioEngine` tap that does three things at
/// once: writes the `.m4a` (for upload + playback + the authoritative one-shot
/// re-transcribe), computes the live mic level for the waveform, and feeds the
/// streaming `TranscriptionService` for the caption-first UI. Pause excludes
/// paused time from the duration and stops writing/feeding.
///
/// In **mock mode** (`-seedTranscript`) there's no engine, no mic, no model: a
/// timer advances the clock, fakes a level, and *progressively reveals* the
/// seeded transcript as the live caption — so the caption-first record screen is
/// fully UI-testable on the Simulator (which has no Neural Engine). Real capture,
/// the live ASR caption, and the file write are device-owed.
@MainActor
@Observable
final class LiveRecordingService {
    // Observation is PER-PROPERTY (`@Observable`, not ObservableObject): the
    // record screen splits into child views so the 4 Hz timer invalidates only
    // the timer text, the ~10 Hz level only the waveform, the caption only the
    // caption pane — the previous whole-screen re-render at ~30/s was a real
    // cost on a warm A15.
    private(set) var isRecording = false
    private(set) var isPaused = false
    private(set) var elapsed: TimeInterval = 0
    /// Smoothed input level, 0...1.
    private(set) var level: Float = 0
    /// Rolling level history (newest last) for the live waveform bars.
    private(set) var waveform: [Float] = []
    /// Best-effort live transcript shown caption-first while recording.
    private(set) var liveCaption: String = ""
    /// How many leading caption words are FINAL (rotated/committed chunks never
    /// re-transcribe) — the truthful solid-vs-volatile boundary for colouring.
    private(set) var liveCommittedWordCount: Int = 0
    /// A brief, self-clearing notice surfaced when the audio route changes
    /// mid-recording (e.g. AirPods pulled out) — so the user knows capture may
    /// have hiccuped without the recording being dropped. nil = nothing to show.
    private(set) var routeNotice: String?
    /// Set when a buffer could not be written (disk full, R46): the take has
    /// stopped capturing and everything that landed is kept. The owning screen
    /// stops + saves on this and says so. nil = healthy.
    private(set) var writeFailure: String?

    /// Whether live captioning is on (Settings toggle; default on). Off = record
    /// + waveform only, transcript comes from the one-shot pass after stop.
    /// Observable so the UI reacts when the auto-off flips it mid-recording
    /// (the RT tap reads `tapLive`, not this, so the flip is race-free).
    var liveTranscription: Bool

    // MARK: - Cross-feature recording signal

    /// The instance whose recording session is currently live. Weak, so an
    /// abnormally-dismissed recorder (deinit without stop/cancel) can never
    /// leave the flag stuck on.
    private static weak var activeService: LiveRecordingService?

    /// CROSS-LANE CONTRACT — do not rename. True while a recording session is
    /// live: from `start()` until `stop()`/`cancel()`, **including while
    /// paused**. Other features yield to an active recording on this signal —
    /// e.g. `AudiobookSession` ignores remote-play commands (AirPods in-ear
    /// auto-play) that would otherwise grab the audio session mid-recording.
    /// MainActor-isolated via the class annotation.
    static var isRecordingActive: Bool { activeService?.isRecording ?? false }

    /// Start failed because the mic input isn't ready (its format is invalid
    /// or mid-route-transition). `startRetrying` keeps retrying on this —
    /// installing a tap anyway would raise an uncatchable NSException.
    enum StartError: Error { case inputFormatNotReady }

    private let mock: Bool
    private static let waveformBars = 40

    // Internal state below is @ObservationIgnored: none of it is UI-facing,
    // and the tap mirrors especially must NOT go through the observation
    // registrar (the tap reads them on the real-time audio thread).
    @ObservationIgnored private var engine: AVAudioEngine?
    @ObservationIgnored private var audioFile: AVAudioFile?
    @ObservationIgnored private var tempURL: URL?
    /// Segment + marker persistence for this take (C99/D26). Read by the tap's
    /// writer block on `writerQueue`; set/cleared on main only with the queue
    /// drained, so the unsynchronised access is safe.
    @ObservationIgnored private nonisolated(unsafe) var checkpoint: RecordingCheckpoint?
    /// Latched by the writer on the first failed write — later buffers drop.
    @ObservationIgnored private nonisolated(unsafe) var writeFailed = false
    /// Captions paused because the app went to the background (D131); they
    /// resume on the way back to the foreground.
    @ObservationIgnored private var captionsSuspendedForBackground = false
    /// Captions dropped on a memory warning (D131); the model reloads after Stop.
    @ObservationIgnored private var captionsDroppedForMemory = false
    @ObservationIgnored private var lifecycleObservers: [NSObjectProtocol] = []
    /// UID of the input port the CURRENT tap was built for — used to spot
    /// route-change notifications that are just echoes of our OWN session
    /// activation (`.categoryChange` right after `start()`), where nothing
    /// actually changed underneath us. Rebuilding on those mid-transition
    /// echoes is what crashed round 2 (P0, 2026-06-12).
    @ObservationIgnored private var tapInputUID: String?

    // Mirrored, audio-thread-readable copies of the gating state. The tap runs
    // on a real-time thread; reading MainActor-isolated observable vars there
    // would be a data race, so we mirror what the tap needs.
    @ObservationIgnored private nonisolated(unsafe) var tapPaused = false
    @ObservationIgnored private nonisolated(unsafe) var tapLive = true
    /// Set before tearing down the tap so a callback already past `installTap`'s
    /// guard doesn't enqueue another write while we're finalizing the file.
    @ObservationIgnored private nonisolated(unsafe) var tapStopped = false
    /// Stamped by the rebuild the moment it tears the old tap down; the first
    /// buffer written through the NEW tap logs the visible hole. ⚠️ This
    /// stopwatch starts at the route-change NOTIFICATION — the OS stops the
    /// mic at the START of a route transition and only posts at its END, so
    /// the true hole is bigger by the transition time (b117: reported 184 ms
    /// while the word-timings proved ~1.9 s). Diagnostics, not truth.
    @ObservationIgnored private nonisolated(unsafe) var awaitingFirstBufferSince: Date?
    /// File encode (AAC) + RMS run here, OFF the real-time audio render thread,
    /// so disk/encode work can't cause render overruns. Drained at stop before
    /// the `AVAudioFile` is released.
    private let writerQueue = DispatchQueue(label: "skrift.recording.writer")

    @ObservationIgnored private var displayTimer: Timer?
    @ObservationIgnored private var captionTask: Task<Void, Never>?
    @ObservationIgnored private var routeObserver: NSObjectProtocol?
    /// `AVAudioEngineConfigurationChange` — the canonical "the engine's node
    /// formats changed underneath you" signal. Re-arms a recording whose
    /// rebuild retries exhausted while the input format was still settling.
    @ObservationIgnored private var engineConfigObserver: NSObjectProtocol?
    /// `mediaServicesWereReset` — the audio stack restarted; rebuild too.
    @ObservationIgnored private var mediaServicesObserver: NSObjectProtocol?
    /// `interruptionNotification` — a call/Siri/alarm stopped the engine. The
    /// route/engine-config observers do NOT fire for a plain interruption (the
    /// route never changed), so without this the engine stayed dead while the
    /// wall-clock timer kept counting — the "recorded only half my message" bug.
    @ObservationIgnored private var interruptionObserver: NSObjectProtocol?
    /// `didBecomeActive` — iOS doesn't always deliver interruption `.ended`
    /// (classically: the interruption happened while backgrounded); Apple's
    /// guidance is to re-check on foreground. Re-arms a dead engine then.
    @ObservationIgnored private var foregroundObserver: NSObjectProtocol?
    /// True between interruption `.began` and its recovery (`.ended` /
    /// foreground re-arm). The watchdog stands down while the system owns the
    /// mic — a rebuild mid-interruption cannot succeed and just churns retries.
    @ObservationIgnored private var interruptionActive = false
    /// When the watchdog first saw the engine stopped (nil = capture healthy).
    @ObservationIgnored private var stallSince: Date?
    /// Last rebuild attempt — the watchdog defers to the rebuild ladder's own
    /// backoff window instead of double-driving it.
    @ObservationIgnored private var lastRebuildAttemptAt: Date?
    @ObservationIgnored private var noticeClearTimer: Timer?
    @ObservationIgnored private var segmentStart: Date?
    @ObservationIgnored private var accumulated: TimeInterval = 0
    /// Auto-off for live captions (Settings → Recording; 0 = never): after
    /// this many recorded seconds the live stream quietly drops to save
    /// battery — the one-shot pass at stop transcribes regardless. Captured at
    /// `start()`; fires at most once per recording so tapping captions back ON
    /// afterwards doesn't instantly re-trigger. Lived in RecordView's
    /// `.onChange(of: elapsed)` before — which made the whole screen re-render
    /// on every elapsed tick; the service owns its own clock now.
    @ObservationIgnored private var autoOffSeconds = 0
    @ObservationIgnored private var autoOffFired = false

    // Mock-only progressive caption state.
    @ObservationIgnored private var mockWords: [String] = []
    @ObservationIgnored private var mockRevealed = 0

    init(mock: Bool = LaunchFlags.seedTranscript != nil,
         liveTranscription: Bool = UserDefaults.standard.object(forKey: "liveTranscription") as? Bool ?? true) {
        self.mock = mock
        self.liveTranscription = liveTranscription
    }

    deinit {
        // Belt-and-braces teardown for an abnormal dismissal where stop()/cancel()
        // never ran: kill ALL timers + every recovery observer directly. (deinit
        // is nonisolated, so it can't call the @MainActor stopTimers()/
        // teardownRecoveryObservers() helpers — inline the same work.)
        displayTimer?.invalidate()
        captionTask?.cancel()
        noticeClearTimer?.invalidate()
        if let routeObserver { NotificationCenter.default.removeObserver(routeObserver) }
        if let engineConfigObserver { NotificationCenter.default.removeObserver(engineConfigObserver) }
        if let mediaServicesObserver { NotificationCenter.default.removeObserver(mediaServicesObserver) }
        if let interruptionObserver { NotificationCenter.default.removeObserver(interruptionObserver) }
        if let foregroundObserver { NotificationCenter.default.removeObserver(foregroundObserver) }
        for o in lifecycleObservers { NotificationCenter.default.removeObserver(o) }
    }

    // MARK: - Pre-warm (2026-07-26: "clicking record should start immediately")

    /// When the shared session was last configured + activated ahead of a start.
    /// `startEngine` trusts this to SKIP its two mediaserverd round-trips.
    private static var warmedAt: Date?

    /// How long a pre-warm is trusted. Short on purpose: the route can change
    /// under us (AirPods connect, a call ends) and a stale "warm" would skip the
    /// re-configure that a new route needs. A cold start costs one setCategory.
    private static let warmWindow: TimeInterval = 30

    /// True when the session is still configured the way `startEngine` wants it.
    /// All three halves matter — the stamp proves WE activated it, the category
    /// check proves nobody (audiobook, a call) has re-pointed the session since,
    /// and the OPTIONS check proves the Bluetooth-mic policy would pick the same
    /// options NOW (anything holding HFP-full options across a warm skip would
    /// hand the next start the ~1 s flip the policy exists to avoid).
    private static func isSessionWarm(_ session: AVAudioSession) -> Bool {
        guard let at = warmedAt, Date().timeIntervalSince(at) < warmWindow else { return false }
        guard session.category == .playAndRecord else { return false }
        return session.categoryOptions == recordingCategoryOptions(avoidBluetoothMic: avoidBluetoothMicNow(session))
    }

    /// Configure + activate the recording session and WAIT for the hardware to
    /// be ready — off the main actor, polling every 50 ms. The classic ladder
    /// waits out a settling route in 300 ms bites and pays a full re-setup per
    /// bite; this is the same wait at 6× finer grain, costing nothing per poll,
    /// while the main thread stays free for the recorder's present animation.
    /// Sets the warm stamp on success so `startEngine` skips its two
    /// mediaserverd round-trips. Best-effort: `false` just means the caller
    /// falls through to the classic path.
    // MARK: - Bluetooth mic policy (Tuur decisions 2026-07-26, two device rounds)

    /// b115 trace: the ~1 s cold-AirPods start is the A2DP→HFP flip INSIDE
    /// `engine.start()` (969 ms; session calls = 132 ms; once flipped = 1 ms),
    /// recurring per recording because stop() hands the route back. First
    /// answer was a two-phase handoff (start on the built-in mic, flip to the
    /// headset mic ~700 ms in). **The b117 round killed the flip:** the OS
    /// stops the mic at the START of the HFP transition and only posts the
    /// route change at its END — a ~1.9 s capture hole MID-SPEECH (the
    /// word-timings sidecar shows "One," at 0.08–0.96 stitched straight onto
    /// "four," — "two"/"three" eaten). So: with Bluetooth around, the WHOLE
    /// recording stays on the built-in mic (`avoidBluetoothMic: true` —
    /// `.allowBluetoothA2DP` keeps the AirPods as full-quality output). No
    /// flip, no hole, fast start. Pocket-dictation-through-AirPods is the
    /// accepted cost; the revisit item lives on the roadmap.
    nonisolated static func recordingCategoryOptions(avoidBluetoothMic: Bool) -> AVAudioSession.CategoryOptions {
        avoidBluetoothMic ? [.allowBluetoothA2DP, .defaultToSpeaker]
                          : [.allowBluetooth, .defaultToSpeaker]
    }

    /// True when Bluetooth is around to avoid — UNLESS the input already IS
    /// the headset mic (then forcing A2DP-only would yank the route out from
    /// under a live HFP input at start; leave it be, exactly as before this
    /// policy existed).
    nonisolated static func avoidsBluetoothMic(
        currentInputPortType: AVAudioSession.Port?,
        outputPortTypes: [AVAudioSession.Port],
        availableInputPortTypes: [AVAudioSession.Port]
    ) -> Bool {
        guard currentInputPortType != .bluetoothHFP else { return false }
        return outputPortTypes.contains(.bluetoothA2DP)
            || availableInputPortTypes.contains(.bluetoothHFP)
    }

    /// The live session's answer to `avoidsBluetoothMic`.
    nonisolated private static func avoidBluetoothMicNow(_ session: AVAudioSession) -> Bool {
        avoidsBluetoothMic(
            currentInputPortType: session.currentRoute.inputs.first?.portType,
            outputPortTypes: session.currentRoute.outputs.map(\.portType),
            availableInputPortTypes: (session.availableInputs ?? []).map(\.portType))
    }

    nonisolated static func settleSession(timeout: TimeInterval = 1.5) async -> Bool {
        await Task.detached(priority: .userInitiated) {
            let t = Date()
            let session = AVAudioSession.sharedInstance()
            do {
                try session.setCategory(.playAndRecord, mode: .default,
                                        options: recordingCategoryOptions(avoidBluetoothMic: avoidBluetoothMicNow(session)))
                try session.setActive(true)
            } catch {
                await MainActor.run { LiveRecordingService.warmedAt = nil }
                DevLog.log("session settle FAILED after \(LiveRecordingService.ms(t))ms: \(error)")
                return false
            }
            // The session's own hw numbers are the input-side readiness signal
            // (the engine node's format follows them) — poll until they're real.
            var polls = 0
            while Date().timeIntervalSince(t) < timeout,
                  !(session.sampleRate > 0 && session.inputNumberOfChannels > 0) {
                polls += 1
                try? await Task.sleep(for: .milliseconds(50))
            }
            let ready = session.sampleRate > 0 && session.inputNumberOfChannels > 0
            await MainActor.run { LiveRecordingService.warmedAt = ready ? Date() : nil }
            DevLog.log("session settled in \(LiveRecordingService.ms(t))ms — polls=\(polls)"
                       + " ready=\(ready) hw=\(Int(session.sampleRate))Hz/\(session.inputNumberOfChannels)ch"
                       + " route=\(LiveRecordingService.describe(session.currentRoute))")
            return ready
        }.value
    }

    // MARK: - Prestart (capture starts at the record BUTTON, not after the cover)

    /// The service parked by `prestart()` until the recorder claims it.
    /// Internal (not private) so unit tests can exercise the park/claim
    /// contract without touching the live audio session.
    static var prestarted: LiveRecordingService?

    /// Latched by the expiry sweep; every start driver checks it so an
    /// abandoned prestart can never ghost-record with no UI attached.
    @ObservationIgnored private var prestartAbandoned = false

    /// True while a start driver (fast path or the retry ladder) is running —
    /// the recorder's own `onAppear` start call no-ops against it instead of
    /// racing a second bring-up.
    @ObservationIgnored private var startInFlight = false

    /// Record-button fast path: create the service and start capturing NOW,
    /// while the fullScreenCover is still animating in. The recorder claims
    /// the running service in its `onAppear`; by then the mic is usually
    /// already live, so the first words land in the file instead of the gap.
    ///
    /// PARKS SYNCHRONOUSLY — b115 device trace: an async park lost the race
    /// to onAppear by 15 ms, so the claim found nil, the view span up its own
    /// service the old way, and the orphaned prestart became a SECOND
    /// concurrent recording that the expiry then tore down under the live
    /// one. The button action is main-actor, so parking before returning
    /// makes the claim's success a happens-before fact, not a scheduling bet.
    ///
    /// Engine bring-up stays ON the main actor (same code path, same
    /// observer ordering as any start — no new races); only the session
    /// settle runs off-main. Mock/UITest launches keep the classic path.
    /// If the cover somehow never claims it, the expiry sweep cancels the
    /// recording and deletes the temp file — no ghost capture.
    static func prestart() {
        let tapped = Date()
        guard LaunchFlags.seedTranscript == nil else { return }
        guard prestarted == nil, !isRecordingActive else { return }
        let svc = LiveRecordingService()
        prestarted = svc
        DevLog.log("prestart requested at the record button —"
                   + " route=\(describe(AVAudioSession.sharedInstance().currentRoute))")
        svc.startFast(tappedAt: tapped)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(8))
            if prestarted === svc {
                prestarted = nil
                DevLog.log("prestart EXPIRED unclaimed after 8 s — tearing down")
                svc.abandon()
            }
        }
    }

    /// Hand the parked service to the recorder (once). nil = no prestart ran
    /// (append flow, quote ramble, Siri, mock) — the caller uses its own.
    static func claimPrestarted() -> LiveRecordingService? {
        guard let svc = prestarted else { return nil }
        prestarted = nil
        return svc
    }

    /// Kill an unclaimed prestart: stop any capture, delete the temp file,
    /// and pin every driver (ladder included) so a sleeping retry can't
    /// resurrect it.
    private func abandon() {
        prestartAbandoned = true
        if isRecording { cancel() }
    }

    /// Settle the session off-main, then run the normal main-actor start.
    /// Any failure hands to the classic ladder — the worst case is exactly
    /// today's behavior, just begun at the button instead of after the cover.
    func startFast(tappedAt: Date) {
        // `!Self.isRecordingActive`: with self.isRecording false, a true here
        // means ANOTHER instance is capturing — never start a second recording
        // (b115 trace: the orphaned prestart did exactly that, 4 s in).
        guard !isRecording, !startInFlight, !Self.isRecordingActive else { return }
        startInFlight = true
        // DETACH FIRST (b117 trace: button-to-live=1029ms, 278ms of which was
        // this task queued BEHIND the cover-presentation transaction — an
        // off-main settle that had to wait for main to go off-main). The
        // detached task starts settling immediately; main is touched only for
        // the engine bring-up, which needs it anyway.
        Task.detached(priority: .userInitiated) { [weak self, mock = mock] in
            if !mock { _ = await Self.settleSession() }
            await MainActor.run { [weak self] in
                guard let self else { return }
                guard !self.isRecording, !self.prestartAbandoned, !Self.isRecordingActive else {
                    self.startInFlight = false
                    return
                }
                do {
                    try self.start()
                    self.startInFlight = false
                    DevLog.log("prestart LIVE — button-to-live=\(Self.ms(tappedAt))ms")
                } catch {
                    self.startInFlight = false
                    DevLog.log("prestart engine attempt failed (\(error)) — handing to the ladder")
                    self.startRetrying()
                }
            }
        }
    }

    /// Start, retrying briefly when the audio session is contended. Owned by the
    /// service (not the view) so the retries die with the recorder — `[weak self]`
    /// means a dismissed RecordView can never ghost-start a recording. With
    /// `siriGrace` (a pending Record-intent launch) the first attempt waits 700 ms:
    /// right after a voice launch Siri still owns the audio session, and
    /// contending instantly just burns retries. A plain in-app open starts at once.
    func startRetrying(siriGrace: Bool = false) {
        // `startInFlight`: when the record button already prestarted this
        // service, the recorder's own onAppear call lands here mid-bring-up —
        // no-op instead of racing a second driver (the fast path hands to this
        // ladder itself on failure).
        guard !isRecording, !startInFlight else { return }
        startInFlight = true
        // WALL CLOCK for the "Starting…" placeholder: this stamp is taken the
        // instant the recorder asks to start, and the success line reports the
        // full tap-to-live latency (retries + Siri grace included). Pair it with
        // the per-stage `engine started` line to see WHERE the time went.
        let tRequested = Date()
        DevLog.log("start requested — siriGrace=\(siriGrace)"
                   + " route=\(Self.describe(AVAudioSession.sharedInstance().currentRoute))")
        Task { @MainActor [weak self] in
            defer { self?.startInFlight = false }
            if siriGrace { try? await Task.sleep(for: .milliseconds(700)) }
            for attempt in 0..<16 {
                // isRecordingActive with self.isRecording false = another
                // instance is live — a retrying driver must never become a
                // second concurrent recording.
                guard let self, !self.isRecording, !self.prestartAbandoned,
                      !Self.isRecordingActive else { return }
                do {
                    try self.start()
                    DevLog.log("start LIVE after \(attempt + 1) attempt(s)"
                               + " — tap-to-live=\(Self.ms(tRequested))ms")
                    return
                }
                catch {
                    // Session busy (e.g. Siri releasing the mic) or the input
                    // format isn't ready yet — wait and retry.
                    DevLog.log("start attempt \(attempt) failed: \(error)")
                }
                try? await Task.sleep(for: .milliseconds(300))
            }
            DevLog.log("start gave up after 16 attempts — \(Self.ms(tRequested))ms burned")
        }
    }

    func start() throws {
        guard !isRecording else { return }
        // Reflect the CURRENT "Live transcription" preference, and reset any transient
        // auto-off (the timer) left on a reused service from a prior recording — so a
        // long recording's auto-off never silences the NEXT one (2026-06-22).
        liveTranscription = UserDefaults.standard.object(forKey: "liveTranscription") as? Bool ?? true
        accumulated = 0
        elapsed = 0
        level = 0
        waveform = []
        liveCaption = ""
        liveCommittedWordCount = 0
        let takeID = UUID().uuidString
        let url = AppPaths.recordingsDirectory.appendingPathComponent(RecordingCheckpoint.mainFilename(take: takeID))
        tempURL = url
        writeFailure = nil
        writeFailed = false
        captionsSuspendedForBackground = false
        captionsDroppedForMemory = false

        tapPaused = false
        tapStopped = false
        tapLive = liveTranscription
        awaitingFirstBufferSince = nil
        interruptionActive = false
        stallSince = nil
        lastRebuildAttemptAt = nil
        autoOffFired = false
        autoOffSeconds = UserDefaults.standard.object(forKey: "liveCaptionAutoOffSeconds") as? Int ?? 60

        if mock {
            FileManager.default.createFile(atPath: url.path, contents: Data())
            mockWords = (LaunchFlags.seedTranscript ?? "").split(separator: " ").map(String.init)
            mockRevealed = 0
        } else {
            DevLog.log("record start — live=\(liveTranscription)")
            try startEngine(writingTo: url, takeID: takeID)
            installLifecycleObservers()
            RecordingLifecycleLog.log("start", "take=\(takeID) live=\(liveTranscription)")
            if liveTranscription {
                Task { await TranscriptionService.shared.beginStream() }
                startCaptionPolling()
            }
        }

        isRecording = true
        isPaused = false
        Self.activeService = self
        segmentStart = Date()
        startDisplayTimer()
        if !mock { RecordingActivityManager.shared.start() }
    }

    /// Flip live captioning ON/OFF — the record-screen top-right toggle, mirrored
    /// by the Settings "Live transcription" preference. OFF keeps recording, the
    /// waveform, and the `.m4a` write going but stops feeding the live caption
    /// stream: for a long, battery-saving recording that's transcribed in ONE
    /// pass after stop (the authoritative one-shot transcribe runs regardless of
    /// this flag). Safe mid-recording — OFF tears the stream down, ON begins it
    /// from the current point (the caption picks up from here, not the start).
    func setLiveTranscription(_ on: Bool) {
        guard liveTranscription != on else { return }
        liveTranscription = on
        tapLive = on
        guard isRecording, !mock else { return }
        if on {
            liveCommittedWordCount = 0
            Task { await TranscriptionService.shared.beginStream() }
            startCaptionPolling()
        } else {
            captionTask?.cancel(); captionTask = nil
            liveCaption = ""
            liveCommittedWordCount = 0
            Task { await TranscriptionService.shared.endStream() }
        }
    }

    func pause() {
        guard isRecording, !isPaused else { return }
        accumulate()
        isPaused = true
        tapPaused = true
        if !mock { engine?.pause(); RecordingActivityManager.shared.pause(); DevLog.log("record pause") }
    }

    func resume() {
        guard isRecording, isPaused else { return }
        segmentStart = Date()
        isPaused = false
        tapPaused = false
        if !mock {
            if engine != nil, tapInputUID == nil {
                // The tap was torn down while paused (a route change mid-pause
                // whose rebuild couldn't complete) — rebuild for the CURRENT
                // route instead of starting an engine that captures nothing.
                DevLog.log("record resume — no live tap, rebuilding for the current route")
                rebuildTapForCurrentRoute()
            } else {
                try? engine?.start()
                if engine?.isRunning != true {
                    // e.g. the session was interrupted while paused — a plain
                    // start can't recover that; the rebuild reasserts the
                    // session and reinstalls for the current route.
                    DevLog.log("record resume — engine didn't start, rebuilding")
                    interruptionActive = false
                    rebuildTapForCurrentRoute()
                }
            }
            DevLog.log("record resume — engineRunning=\(engine?.isRunning == true)")
            RecordingActivityManager.shared.resume(elapsed: elapsed)
        }
    }

    struct Result { let url: URL; let duration: TimeInterval; let liveCaption: String }

    func stop() -> Result? {
        guard isRecording else { return nil }
        accumulate()
        stopTimers()
        teardownRecoveryObservers()
        var duration = elapsed
        if !mock {
            tapStopped = true
            engine?.inputNode.removeTap(onBus: 0)
            engine?.stop()
            writerQueue.sync {}   // drain pending writes before finalizing the file
            // Real recorded length from the file — 0 frames means the tap never
            // captured audio (e.g. a fast start→stop, or an unavailable mic/session);
            // the caller treats that as an empty recording instead of a silent memo.
            if let file = audioFile, file.length > 0 {
                duration = Double(file.length) / file.fileFormat.sampleRate
            } else {
                duration = 0
            }
            // FINALIZE the .m4a deterministically BEFORE anyone reads it: close()
            // flushes the AAC encoder's buffered tail and writes the MP4 header
            // (moov) NOW. Relying on AVAudioFile dealloc (`audioFile = nil`) was a
            // race — the tap block can keep the file alive briefly after
            // removeTap, so the one-shot transcription that runs right after stop
            // could open a not-yet-finalized file and transcribe it WITHOUT the
            // last stretch of speech (the intermittent cut-off-tail bug).
            audioFile?.close()
            if let merged = finishCheckpoint(mainURL: tempURL) { duration = merged }
            engine = nil
            audioFile = nil
            tapInputUID = nil
            if captionsDroppedForMemory {
                // D131: the transcriber was unloaded mid-take — bring it back now.
                captionsDroppedForMemory = false
                Task { try? await TranscriptionService.shared.ensureLoaded() }
            }
            logSessionHandback("stop")
            releaseSessionUnlessAnotherRecords("stop")
            if liveTranscription { Task { await TranscriptionService.shared.endStream() } }
            RecordingActivityManager.shared.end()
            RecordingLifecycleLog.log("finalize", "reason=stop duration=\(String(format: "%.2f", duration))s")
        }
        isRecording = false
        isPaused = false
        if Self.activeService === self { Self.activeService = nil }
        let caption = liveCaption
        guard let url = tempURL else { return nil }
        tempURL = nil
        return Result(url: url, duration: duration, liveCaption: caption)
    }

    func cancel() {
        guard isRecording else { return }
        stopTimers()
        teardownRecoveryObservers()
        if !mock {
            tapStopped = true
            engine?.inputNode.removeTap(onBus: 0)
            engine?.stop()
            writerQueue.sync {}    // drain pending writes before finalizing the file
            audioFile?.close()     // finalize before the temp file is deleted below
            checkpoint?.discard()
            checkpoint = nil
            engine = nil
            audioFile = nil
            tapInputUID = nil
            logSessionHandback("cancel")
            releaseSessionUnlessAnotherRecords("cancel")
            if liveTranscription { Task { await TranscriptionService.shared.endStream() } }
            RecordingActivityManager.shared.end()
            RecordingLifecycleLog.log("cancel")
        }
        if let url = tempURL { try? FileManager.default.removeItem(at: url) }
        tempURL = nil
        isRecording = false
        isPaused = false
        if Self.activeService === self { Self.activeService = nil }
        elapsed = 0
        level = 0
        waveform = []
        liveCaption = ""
        liveCommittedWordCount = 0
    }

    // MARK: - Durability (C99/D26, R46, D131)

    /// Writer-queue side of a failed write: latch, then stop the take on main.
    nonisolated private func noteWriteFailure(_ error: Error) {
        guard !writeFailed else { return }
        writeFailed = true
        let text = error.localizedDescription
        Task { @MainActor [weak self] in self?.handleWriteFailure(text) }
    }

    /// R46: the disk refused a buffer. Stop capturing (nothing more can land),
    /// close the open segment so what landed is safe, and tell the owner — the
    /// record screen stops + saves on `writeFailure` and the note says why.
    private func handleWriteFailure(_ detail: String) {
        guard isRecording, writeFailure == nil else { return }
        tapStopped = true
        writerQueue.sync { checkpoint?.rotate(reason: "write-failed") }
        RecordingLifecycleLog.log("write-failed", detail)
        writeFailure = Self.diskFullMessage
    }

    static let diskFullMessage = "Recording stopped: the phone ran out of storage. Everything recorded up to that point is saved."

    /// Close the open segment and rewrite the marker NOW (interruption,
    /// background, memory warning) — drains queued buffers first.
    private func checkpointNow(_ reason: String) {
        writerQueue.sync { checkpoint?.rotate(reason: reason) }
    }

    /// Normal stop: the main file is closed. Keep it when it reads back; when it
    /// does not (a disk-full take whose index never got written), rebuild it from
    /// the closed segments. Returns the rebuilt duration when a rebuild ran.
    private func finishCheckpoint(mainURL: URL?) -> TimeInterval? {
        guard let cp = checkpoint else { return nil }
        checkpoint = nil
        cp.rotate(reason: "stop")
        guard let main = mainURL, !RecordingCheckpoint.isReadableAudio(main) else {
            cp.discard()
            return nil
        }
        let segments = cp.segmentURLs.filter(RecordingCheckpoint.isReadableAudio)
        guard !segments.isEmpty else { cp.discard(); return nil }
        do {
            try MemoSaver.mergeAudioSync(sources: segments, to: main)
            let f = try AVAudioFile(forReading: main)
            cp.discard()
            RecordingLifecycleLog.log("finalize", "rebuilt main file from \(segments.count) segment(s)")
            return Double(f.length) / f.fileFormat.sampleRate
        } catch {
            RecordingLifecycleLog.log("finalize", "rebuild from segments FAILED (\(error)) — marker kept for the launch sweep")
            return nil
        }
    }

    private func installLifecycleObservers() {
        guard lifecycleObservers.isEmpty else { return }
        let nc = NotificationCenter.default
        func on(_ name: Notification.Name, _ body: @escaping @MainActor (LiveRecordingService) -> Void) {
            lifecycleObservers.append(nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { if let self { body(self) } }
            })
        }
        on(UIApplication.didEnterBackgroundNotification) { $0.handleDidEnterBackground() }
        on(UIApplication.willEnterForegroundNotification) { $0.handleWillEnterForeground() }
        on(UIApplication.didReceiveMemoryWarningNotification) { $0.handleMemoryWarning() }
        on(UIApplication.willTerminateNotification) { $0.handleWillTerminate() }
    }

    /// D131: in the background the recording continues and live captions stop.
    /// A segment is closed on the way out — background is where kills happen.
    private func handleDidEnterBackground() {
        guard isRecording, !mock else { return }
        checkpointNow("background")
        guard liveTranscription, !captionsSuspendedForBackground else { return }
        captionsSuspendedForBackground = true
        tapLive = false
        captionTask?.cancel(); captionTask = nil
        Task { await TranscriptionService.shared.endStream() }
        RecordingLifecycleLog.log("captions-stopped", "reason=background")
    }

    private func handleWillEnterForeground() {
        guard captionsSuspendedForBackground else { return }
        captionsSuspendedForBackground = false
        guard isRecording, !mock, liveTranscription else { return }
        tapLive = true
        liveCommittedWordCount = 0
        Task { await TranscriptionService.shared.beginStream() }
        startCaptionPolling()
        RecordingLifecycleLog.log("captions-resumed", "reason=foreground")
    }

    /// D131, in this order: the recording is saved first, then the memory goes.
    enum MemoryWarningStep: String, CaseIterable {
        case flushAudio, writeCheckpoint, stopCaptions, unloadTranscriber
    }
    static let memoryWarningOrder: [MemoryWarningStep] = [.flushAudio, .writeCheckpoint, .stopCaptions, .unloadTranscriber]

    func handleMemoryWarning() {
        guard isRecording, !mock else { return }
        for step in Self.memoryWarningOrder {
            switch step {
            case .flushAudio:
                writerQueue.sync {}
            case .writeCheckpoint:
                checkpoint?.rotate(reason: "memory")
            case .stopCaptions:
                captionsSuspendedForBackground = false
                liveTranscription = false
                tapLive = false
                captionTask?.cancel(); captionTask = nil
            case .unloadTranscriber:
                // endStream first: `unload()` refuses while a stream is open.
                captionsDroppedForMemory = true
                Task {
                    await TranscriptionService.shared.endStream()
                    await TranscriptionService.shared.unload()
                }
            }
            RecordingLifecycleLog.log("memory-warning", "step=\(step.rawValue)")
        }
    }

    /// Force-quit: close the main file and every segment, and mark the take
    /// finalized — the next launch's sweep turns it into a note.
    private func handleWillTerminate() {
        guard isRecording, !mock else { return }
        tapStopped = true
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        writerQueue.sync {}
        audioFile?.close()
        if let url = tempURL, RecordingCheckpoint.isReadableAudio(url) {
            checkpoint?.finalize()
        } else {
            checkpoint?.rotate(reason: "terminate")
        }
        RecordingLifecycleLog.log("finalize", "reason=terminate")
    }

    // MARK: - Real engine

    /// Whole milliseconds between two stamps — the DevLog stage-timing formatter.
    nonisolated private static func ms(_ from: Date, _ to: Date = Date()) -> String {
        String(format: "%.0f", to.timeIntervalSince(from) * 1000)
    }

    /// The recorder OWNS the route while it runs (`.playAndRecord`), and both
    /// `stop()` and `cancel()` release it with `.notifyOthersOnDeactivation` —
    /// which is literally "other app, resume now". When a book session is live
    /// (the audiobook quote-capture ramble records THROUGH this service) that
    /// handback goes to whatever we interrupted, and the paused book does NOT
    /// come back on its own. Logged so the "my music started playing again"
    /// reports have a cause to point at.
    /// Diagnostics only — `#if DEBUG` so a Release stop never reaches for the
    /// audiobook singleton just to log.
    private func logSessionHandback(_ verb: String) {
        #if DEBUG
        let book = AudiobookSession.shared
        guard book.isActive else { return }
        DevLog.log("record \(verb) — releasing the audio session WHILE a book session is active"
                   + " (bookPlaying=\(book.isPlaying)) — others may resume instead of the book")
        #endif
    }

    /// Release the shared session — with two exceptions where handing the route
    /// back would hurt:
    ///
    /// 1. Another instance is mid-recording: deactivating rips the route out
    ///    from under live capture (b115 trace: the expired orphan prestart's
    ///    cancel() did exactly this, 27 ms before the user's own stop).
    /// 2. **A book session is active** — the audiobook quote-capture ramble
    ///    records THROUGH this service, so `.notifyOthersOnDeactivation`
    ///    ("other app, resume now") reached whatever the BOOK had interrupted:
    ///    capture a quote while Deezer was paused → finish the ramble → Deezer
    ///    comes back instead of the book. The book re-activates for itself a
    ///    moment later (`QuoteCaptureFlowView.onFinish` → `session.play()`), so
    ///    skipping the release here loses nothing and keeps the route in-app.
    private func releaseSessionUnlessAnotherRecords(_ verb: String) {
        if let active = Self.activeService, active !== self, active.isRecording {
            DevLog.log("record \(verb) — session deactivation SKIPPED, another recording is live")
            return
        }
        if AudiobookSession.shared.isActive {
            DevLog.log("record \(verb) — session deactivation SKIPPED, a book session is active"
                       + " (the book takes the route back, not the app we interrupted)")
            return
        }
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    private func startEngine(writingTo url: URL, takeID: String) throws {
        // STAGE TIMINGS (2026-07-25, "Starting… takes a while"): every stage below
        // is a synchronous MAIN-ACTOR call into mediaserverd, so their sum IS the
        // "Starting…" placeholder's lifetime. Logged as one summary line per
        // attempt so a device pull shows exactly which stage owns the latency
        // (suspicion: setCategory with .allowBluetooth = the A2DP→HFP flip).
        let tStart = Date()
        let session = AVAudioSession.sharedInstance()
        // PRE-WARM (A.1): when the record button already configured + activated
        // the session, both calls below are skipped — that's the whole point of
        // the pre-warm, and `warm=` in the log lines says which path ran.
        // .default (not .measurement): .measurement strips input gain/AGC, which
        // made recordings very quiet → soft playback + a barely-moving waveform.
        // A voice-memo wants normal capture gain.
        let warm = Self.isSessionWarm(session)
        if !warm {
            try session.setCategory(.playAndRecord, mode: .default,
                                    options: Self.recordingCategoryOptions(avoidBluetoothMic: Self.avoidBluetoothMicNow(session)))
        }
        let tCategory = Date()
        if !warm {
            try session.setActive(true)
        }
        let tActivate = Date()

        let engine = AVAudioEngine()
        let input = engine.inputNode
        // inputFormat (the HARDWARE side of the node), NOT outputFormat: the
        // latter is pinned to the engine's render rate and goes stale across
        // route changes (DevLog round 4 — it sat at 48 kHz forever while the
        // hardware and inputFormat said 24 kHz).
        let format = input.inputFormat(forBus: 0)
        // The mic may not be ready right after activation (e.g. a Bluetooth
        // route still settling): a 0 Hz/0 ch format here would make an invalid
        // .m4a AND crash the tap install. Throw instead — `startRetrying`
        // retries every 300 ms while the route settles.
        let tFormat = Date()
        guard format.sampleRate > 0, format.channelCount > 0 else {
            // A warm session that still can't vend a format is a STALE warm (the
            // route moved under us): drop the stamp so the retry does the full
            // cold setCategory/setActive instead of skipping it again.
            if warm { Self.warmedAt = nil }
            DevLog.log("start refused — input format not ready (\(Self.describe(format)))"
                       + " · warm=\(warm) cat=\(Self.ms(tStart, tCategory))ms"
                       + " activate=\(Self.ms(tCategory, tActivate))ms"
                       + " node=\(Self.ms(tActivate, tFormat))ms burned=\(Self.ms(tStart))ms"
                       + " — retrying in 300 ms")
            throw StartError.inputFormatNotReady
        }

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings)
        self.audioFile = file
        // Segments + marker beside the main file (C99): the marker exists from
        // this instant, so even a kill in the first second leaves a findable take.
        checkpoint?.discard()
        checkpoint = RecordingCheckpoint(directory: url.deletingLastPathComponent(), takeID: takeID,
                                         settings: settings, sampleRate: format.sampleRate)
        let tFile = Date()

        guard installRecordingTap(on: input, file: file) else {
            // Don't leave the just-created empty .m4a behind across retries.
            self.audioFile = nil
            checkpoint?.discard()
            checkpoint = nil
            try? FileManager.default.removeItem(at: url)
            DevLog.log("start refused — tap install failed · burned=\(Self.ms(tStart))ms")
            throw StartError.inputFormatNotReady   // startRetrying retries
        }
        let tTap = Date()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            writerQueue.sync {}
            checkpoint?.discard()
            checkpoint = nil
            throw error
        }
        self.engine = engine
        DevLog.log("engine started — input=\(currentInputName()) \(Self.describe(format))"
                   + " · warm=\(warm) cat=\(Self.ms(tStart, tCategory))ms"
                   + " activate=\(Self.ms(tCategory, tActivate))ms"
                   + " node=\(Self.ms(tActivate, tFormat))ms file=\(Self.ms(tFormat, tFile))ms"
                   + " tap=\(Self.ms(tFile, tTap))ms engine=\(Self.ms(tTap))ms"
                   + " TOTAL=\(Self.ms(tStart))ms")
        installRecoveryObservers()
    }

    /// Install the recording tap in the input node's CURRENT hardware format.
    /// The `.m4a` keeps the format it was created with for the whole recording
    /// (a constant file format is mandatory mid-file), so when the current route's
    /// mic format differs — e.g. the recording started on AirPods (24 kHz) and
    /// fell back to the built-in mic (48 kHz) — every buffer is converted to the
    /// file's write format via an `AVAudioConverter` owned by THIS tap closure.
    /// The converter persists across callbacks, so sample-rate-conversion state
    /// stays continuous; in-flight blocks from a previous tap still write
    /// correctly through their own converter (the writer queue is serial).
    ///
    /// Real-time audio thread: keep the tap body minimal. Copy the buffer (tap
    /// storage is reused after the callback) and hand the heavy work — convert +
    /// AAC encode + RMS — to the writer queue so it never blocks the render thread.
    ///
    /// CRASH SAFETY (P0, 2026-06-12 — NSException SIGABRT in InstallTapOnNode):
    /// `installTap` enforces its preconditions with NSExceptions that Swift
    /// CANNOT catch, so validation here is the only defense. Before installing:
    /// (a) any existing tap is ALWAYS removed (installing over a live tap
    /// raises), and (b) the format the tap would install with (the node's
    /// vended format — exactly what we pass to `installTap`) is validated via
    /// `canInstallTap` against the SESSION's live hardware format:
    /// mid-route-transition the node reports 0 Hz/0 ch, or a cached vended
    /// format that still lags the new route. Returns false instead of
    /// installing — callers retry while the route settles
    /// (`rebuildTapForCurrentRoute`, which `engine.reset()`s a stale cache
    /// FIRST so this re-read sees the fresh hardware format) or throw
    /// (`startEngine`).
    ///
    /// DEAFNESS SAFETY (DevLog verdict 2026-06-12 09:14): the validation must
    /// NOT compare against the FILE's format — a hardware format that differs
    /// from the file (AirPods 24 kHz ↔ built-in 48 kHz) is a LEGITIMATE
    /// cross-rate rebuild, and the converter below bridges it. The earlier
    /// check effectively demanded "new format == old format" and refused every
    /// cross-rate rebuild → the recording went deaf on the new route.
    @discardableResult
    private func installRecordingTap(on input: AVAudioInputNode, file: AVAudioFile) -> Bool {
        input.removeTap(onBus: 0)   // (a) never double-install
        tapInputUID = nil           // no live tap from here until a successful install
        let session = AVAudioSession.sharedInstance()
        let sessionRate = session.sampleRate
        let sessionChannels = AVAudioChannelCount(max(0, session.inputNumberOfChannels))
        // ROUND-4 FIX (DevLog /tmp/devlog3.txt): validate + install with the
        // node's INPUT format. `outputFormat(forBus: 0)` is the engine-render
        // side — it stays frozen at the old rate across route flips (even
        // through engine.reset()) and can NEVER converge to the session's
        // hardware format; `inputFormat(forBus: 0)` tracked the hardware
        // correctly on every logged transition.
        let tapFormat = input.inputFormat(forBus: 0)
        guard Self.canInstallTap(sessionHwRate: sessionRate, sessionHwChannels: sessionChannels,
                                 vendedRate: tapFormat.sampleRate, vendedChannels: tapFormat.channelCount) else {
            DevLog.log("tap install REFUSED (transient — retry/re-arm) — sessionHw=\(Int(sessionRate))Hz/\(sessionChannels)ch"
                       + " nodeIn=\(Self.describe(tapFormat)) vendedOut=\(Self.describe(input.outputFormat(forBus: 0)))")
            return false
        }
        // (Per-install:) the converter is created HERE, from THIS tap's fresh
        // format, and captured by THIS tap's closure — so every reinstall
        // bridges its own NEW format to the file's fixed write format.
        let writeFormat = file.processingFormat
        let converter = Self.makeWriteConverter(from: tapFormat, to: writeFormat)
        DevLog.log("tap install ACCEPTED — \(Self.describe(tapFormat)) → file \(Self.describe(writeFormat))"
                   + (converter == nil ? " (no conversion)" : " (converting)"))
        input.installTap(onBus: 0, bufferSize: 4096, format: tapFormat) { [weak self] buffer, _ in
            guard let self, !self.tapPaused, !self.tapStopped,
                  let copy = Self.copyBuffer(buffer) else { return }
            let live = self.tapLive
            self.writerQueue.async { [weak self] in
                if self?.writeFailed == true { return }
                let out: AVAudioPCMBuffer
                if let converter {
                    guard let converted = Self.convert(copy, with: converter, to: writeFormat) else { return }
                    out = converted
                } else {
                    out = copy
                }
                // R46: a failed write (disk full) used to be a silent `try?` per
                // buffer — the timer kept counting over a file that stopped
                // growing. Now the first failure stops the take honestly.
                do {
                    try file.write(from: out)
                    try self?.checkpoint?.write(out)
                } catch {
                    self?.noteWriteFailure(error)
                    return
                }
                // Tap-swap diagnostics: first write through a rebuilt tap.
                // POST-NOTIFICATION view only — the OS stops the mic at the
                // START of a route transition and posts at its END, so the
                // true hole is this PLUS the transition time (b117 lesson:
                // this line said 184 ms while ~1.9 s of speech was lost).
                // Compare file duration vs wall clock for the real number.
                if let s = self, let since = s.awaitingFirstBufferSince {
                    s.awaitingFirstBufferSince = nil
                    let rawMs = Date().timeIntervalSince(since) * 1000
                    let fillMs = Double(out.frameLength) / out.format.sampleRate * 1000
                    DevLog.log(String(format: "capture resumed after tap rebuild — "
                                      + "notification→first-buffer=%.0fms (buffer fill %.0fms;"
                                      + " pre-notification transition time NOT included)", rawMs, fillMs))
                }
                let lvl = Self.rms(out)
                Task { @MainActor [weak self] in
                    guard let self, self.isRecording, !self.isPaused else { return }
                    self.level = lvl
                    self.pushWaveform(lvl)
                }
                // Feed the stream the WRITE-format buffer, not the raw tap copy:
                // the live-caption accumulator memcpy-concatenates its buffers
                // assuming ONE format for the whole stream, so a mid-recording
                // route change must not leak a different sample rate into it.
                if live { Task { await TranscriptionService.shared.feedStream(out) } }
            }
        }
        tapInputUID = AVAudioSession.sharedInstance().currentRoute.inputs.first?.uid
        return true
    }

    /// Keep the recording alive across an audio-route change (AirPods pulled out
    /// or re-inserted, a wired headset unplugged, a Bluetooth device dropping).
    /// iOS tears the route down and stops the engine — AND the input node's
    /// hardware format usually changes with the route, so merely restarting the
    /// engine is NOT enough: a tap installed in the old route's format keeps the
    /// stale format and every `file.write` fails silently from then on (the
    /// recording "dies"). On every transition we fully tear the tap down,
    /// re-query the new input format, reinstall, and restart — see
    /// `rebuildTapForCurrentRoute`. The session category was set once in
    /// `startEngine`; we don't reconfigure it here.
    ///
    /// Five observers, together the NEVER-give-up guarantee: a refused rebuild
    /// only ever waits — it is re-triggered by the next route change, by an
    /// `AVAudioEngineConfigurationChange` (the canonical "the engine's node
    /// formats changed" signal), by a media-services reset, by an audio-session
    /// interruption ending (call/Siri/alarm — fires NO route/config event, the
    /// gap that silently killed recordings halfway), or by returning to the
    /// foreground (iOS can skip `.ended` for interruptions taken while
    /// backgrounded). (DevLog round 3: these are RE-ARM triggers only — a stale
    /// vended format never converges by waiting; the rebuild itself breaks the
    /// cache with `engine.reset()`.) The display-timer watchdog (`watchdogTick`)
    /// is the last resort for anything none of these cover.
    private func installRecoveryObservers() {
        guard routeObserver == nil else { return }
        let session = AVAudioSession.sharedInstance()
        routeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: session,
            queue: .main
        ) { [weak self] note in
            MainActor.assumeIsolated {
                self?.handleRouteChange(note)
            }
        }
        if let engine {
            engineConfigObserver = NotificationCenter.default.addObserver(
                forName: .AVAudioEngineConfigurationChange,
                object: engine,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.handleEngineConfigurationChange()
                }
            }
        }
        mediaServicesObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification,
            object: session,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleMediaServicesReset()
            }
        }
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: session,
            queue: .main
        ) { [weak self] note in
            MainActor.assumeIsolated {
                self?.handleInterruption(note)
            }
        }
        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleForegroundReArm()
            }
        }
    }

    /// A call/Siri/alarm/another app took the audio session. iOS stops the
    /// engine and — unlike a route change — fires no rebuild trigger, so before
    /// this handler the recording stayed dead while the timer kept counting
    /// (the half-recorded-message data loss). `.began` just marks the state
    /// (nothing can capture while the system owns the mic); `.ended` reasserts
    /// the session and rebuilds through the existing route-recovery ladder.
    private func handleInterruption(_ note: Notification) {
        guard isRecording, !mock else { return }
        let typeValue = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
        let type = typeValue.flatMap { AVAudioSession.InterruptionType(rawValue: $0) }
        switch type {
        case .began:
            interruptionActive = true
            DevLog.log("interruption BEGAN — engineRunning=\(engine?.isRunning == true) paused=\(isPaused)")
            RecordingLifecycleLog.log("interrupt", "began")
            checkpointNow("interrupt")
            showRouteNotice("Interrupted — recording resumes when it's over")
        case .ended:
            let optsRaw = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let shouldResume = AVAudioSession.InterruptionOptions(rawValue: optsRaw).contains(.shouldResume)
            interruptionActive = false
            RecordingLifecycleLog.log("interrupt", "ended shouldResume=\(shouldResume)")
            if let engine, engine.isRunning {
                DevLog.log("interruption ENDED (shouldResume=\(shouldResume)) — capture already healthy")
                return
            }
            DevLog.log("interruption ENDED (shouldResume=\(shouldResume)) — rebuilding")
            rebuildTapForCurrentRoute()
            if engine?.isRunning == true {
                showRouteNotice("Interruption over — still recording on \(currentInputName())")
            }
        default:
            break
        }
    }

    /// Foreground re-arm: if an interruption never delivered `.ended` (taken
    /// while backgrounded) or the engine is just dead with no pending rebuild,
    /// recover now — the user is looking at the screen expecting a live
    /// recording.
    private func handleForegroundReArm() {
        guard isRecording, !mock else { return }
        let engineDead = !isPaused && engine?.isRunning != true
        guard interruptionActive || engineDead else { return }
        DevLog.log("foreground re-arm — interruptionActive=\(interruptionActive)"
                   + " engineRunning=\(engine?.isRunning == true) paused=\(isPaused)")
        interruptionActive = false
        guard !isPaused else { return }   // resume() rebuilds when the user resumes
        rebuildTapForCurrentRoute()
    }

    private func handleRouteChange(_ note: Notification) {
        guard isRecording, !mock else { return }
        let reasonValue = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
        let reason = reasonValue.flatMap { AVAudioSession.RouteChangeReason(rawValue: $0) }
        let previous = note.userInfo?[AVAudioSessionRouteChangePreviousRouteKey] as? AVAudioSessionRouteDescription
        let session = AVAudioSession.sharedInstance()
        let currentInput = session.currentRoute.inputs.first
        let nodeIn = engine.map { Self.describe($0.inputNode.inputFormat(forBus: 0)) } ?? "-"
        let vended = engine.map { Self.describe($0.inputNode.outputFormat(forBus: 0)) } ?? "-"
        DevLog.log("route change — reason=\(Self.name(reason))"
                   + " prev=\(Self.describe(previous)) now=\(Self.describe(session.currentRoute))"
                   + " sessionHw=\(Int(session.sampleRate))Hz/\(session.inputNumberOfChannels)ch"
                   + " nodeIn=\(nodeIn) vended=\(vended) engineRunning=\(engine?.isRunning == true)")

        switch reason {
        case .oldDeviceUnavailable, .newDeviceAvailable, .categoryChange:
            // Ignore transitions that didn't touch OUR input. Two proven cases:
            // the echo of our OWN session activation (.categoryChange right
            // after start() — rebuilding mid-transition on an invalid format
            // was the round-2 P0 SIGABRT), and — b119 device trace — an
            // OUTPUT-side attach (.newDeviceAvailable when idle AirPods wake
            // and take playback ~1 s into a recording: input UID unchanged,
            // format live, and the old code tore the tap down anyway —
            // installing a byte-identical tap and putting a hole in the file,
            // most of its 0.6 s wall-vs-file deficit). Skip when the input is
            // ours, the engine runs, and the node still vends the session's
            // live format; a same-UID format renegotiation this misses lands
            // in the AVAudioEngineConfigurationChange observer + the capture
            // watchdog (the documented backstops).
            if currentInput?.uid == tapInputUID, let engine, engine.isRunning,
               Self.canInstallTap(
                   sessionHwRate: session.sampleRate,
                   sessionHwChannels: AVAudioChannelCount(max(0, session.inputNumberOfChannels)),
                   vendedRate: engine.inputNode.inputFormat(forBus: 0).sampleRate,
                   vendedChannels: engine.inputNode.inputFormat(forBus: 0).channelCount) {
                DevLog.log("route change ignored — input unchanged + format live (\(Self.name(reason)))")
                return
            }
            // The input device changed (AirPods pulled / re-inserted, headset
            // unplugged, another component touched the session). The tap MUST be
            // rebuilt in the new route's format — a restart alone leaves a
            // stale-format tap whose writes all fail silently. Rebuild even
            // while paused (so resume() finds a valid tap); the engine itself
            // only restarts when not paused.
            rebuildTapForCurrentRoute()
            showRouteNotice("Input changed — still recording on \(currentInputName())")
        default:
            // .routeConfigurationChange/.override etc. can also stop the engine;
            // if capture stalled, rebuild quietly (same stale-format hazard).
            // This is also a re-arm path: a recording whose rebuild retries
            // exhausted sits with a stopped engine, so ANY later route
            // notification lands here and tries again.
            if !isPaused, let engine, !engine.isRunning {
                DevLog.log("engine stalled by \(Self.name(reason)) — rebuilding")
                rebuildTapForCurrentRoute()
            }
        }
    }

    /// The engine reconfigured itself — its node formats just changed. The
    /// engine stops itself when this happens. If a route-notification rebuild
    /// already brought capture back, do nothing; otherwise rebuild NOW — this
    /// re-arms a recording whose earlier rebuild retries exhausted. (The
    /// rebuild no longer depends on this signal to un-stick a stale vended
    /// format — it resets the engine's format cache itself; see
    /// `rebuildTapForCurrentRoute`.)
    private func handleEngineConfigurationChange() {
        guard isRecording, !mock else { return }
        let running = engine?.isRunning == true
        DevLog.log("engine configuration change — engineRunning=\(running) paused=\(isPaused)")
        if running {
            DevLog.log("engine configuration change ignored — capture already healthy")
            return
        }
        rebuildTapForCurrentRoute()
    }

    /// The system audio stack restarted underneath us. Reassert our session
    /// configuration (a reset wipes it) and rebuild. Best-effort: if the old
    /// engine can't be restarted the observers stay armed and the file keeps
    /// everything captured so far.
    private func handleMediaServicesReset() {
        guard isRecording, !mock else { return }
        DevLog.log("media services were RESET — reconfiguring session + rebuilding")
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .default, options: [.allowBluetooth, .defaultToSpeaker])
        rebuildTapForCurrentRoute()
    }

    /// Survive a route change: tear the tap down, re-query the input node's NEW
    /// hardware format, reinstall the tap in that format (converting buffers to
    /// the file's fixed write format — see `installRecordingTap`), and restart
    /// the engine. Pull AirPods out → capture continues on the built-in mic;
    /// re-insert → capture continues on the AirPods, same `.m4a` throughout.
    ///
    /// Two distinct failure modes guard this path — and every attempt handles
    /// BOTH, reset-then-requery FIRST:
    /// - **STALE CACHED FORMAT** (DevLog round 3, 2026-06-12 09:40):
    ///   `AVAudioEngine` caches its nodes' formats until `reset()`, so after a
    ///   route flip the input node can keep VENDING the old route's format
    ///   indefinitely (vended=48 kHz frozen vs sessionHw=24 kHz on every
    ///   retry). Each attempt first compares vended vs the session's live
    ///   hardware and, on disagreement, calls `engine.reset()` to force a
    ///   re-query before validating — without the reset the refuse-loop never
    ///   converged and the recording deadlocked deaf until the user cancelled.
    ///   This includes the initial start race (record starts on the built-in
    ///   mic, the route flips to AirPods ~1 s later — the user's actual
    ///   failure): post-reset the node vends the new 24 kHz hardware format,
    ///   the install is accepted, and the per-install `AVAudioConverter`
    ///   bridges the new tap format to the file's fixed write format.
    /// - **GENUINELY NOT READY** (0 Hz/0 ch session input mid-transition —
    ///   common right after a Bluetooth route drops): a reset can't conjure a
    ///   mic; `installRecordingTap` refuses (installing would raise an
    ///   uncatchable NSException — the round-2 P0 crash) and we retry with
    ///   backoff (~3 s total) while the route settles, keeping the recording
    ///   session alive throughout.
    /// Exhausting the backoff is NOT a give-up: the recording stays armed, and
    /// the next route-change / engine-configuration-change / media-services
    /// notification re-triggers this rebuild from attempt 0 (the DevLog-verdict
    /// fix — the old hard stop left the recording permanently deaf).
    private func rebuildTapForCurrentRoute(attempt: Int = 0) {
        guard isRecording, let engine, let file = audioFile else { return }
        lastRebuildAttemptAt = Date()   // the watchdog defers while we're at it
        // Capture-hole stopwatch: from the FIRST teardown (keep the earliest
        // stamp across rebuild retries) to the first buffer the new tap writes.
        if awaitingFirstBufferSince == nil { awaitingFirstBufferSince = Date() }
        let input = engine.inputNode
        input.removeTap(onBus: 0)
        engine.stop()
        // Drain in-flight writer blocks from the old tap. Each tap closure owns
        // the converter for ITS format, so already-queued old-format buffers
        // still convert + write correctly before the new tap's buffers arrive.
        writerQueue.sync {}

        // The route change may have deactivated the session; reassert it so the
        // new input route is live before we read its format.
        try? AVAudioSession.sharedInstance().setActive(true)

        // STALE-CACHE BREAKER — runs FIRST on every attempt. When the session's
        // hardware is live but the node still vends a different cached format,
        // `engine.reset()` forces the engine to re-query the hardware. Safe for
        // the file writer: the tap is already removed, the engine stopped, and
        // the writer queue drained above — and the `AVAudioFile` handle is
        // independent of the engine — so a reset cannot disturb the file or any
        // in-flight write. `installRecordingTap` below re-reads the (now fresh)
        // vended format and re-validates before touching `installTap`.
        let session = AVAudioSession.sharedInstance()
        // ROUND-4 FIX: decide on the node's INPUT format (tracks hardware) —
        // outputFormat is engine-render-pinned and never converges, so gating
        // on it kept this loop refusing forever (DevLog round 4).
        let nodeInBefore = input.inputFormat(forBus: 0)
        let action = Self.rebuildAction(
            sessionHwRate: session.sampleRate,
            sessionHwChannels: AVAudioChannelCount(max(0, session.inputNumberOfChannels)),
            vendedRate: nodeInBefore.sampleRate,
            vendedChannels: nodeInBefore.channelCount)
        if action == .resetThenRequery {
            DevLog.log("rebuild attempt \(attempt) — stale nodeIn \(Self.describe(nodeInBefore))"
                       + " vs sessionHw=\(Int(session.sampleRate))Hz/\(session.inputNumberOfChannels)ch"
                       + " — engine.reset() to re-query hardware")
            engine.reset()
            DevLog.log("post-reset formats — sessionHw=\(Int(session.sampleRate))Hz/\(session.inputNumberOfChannels)ch"
                       + " vended=\(Self.describe(input.outputFormat(forBus: 0)))"
                       + " nodeIn=\(Self.describe(input.inputFormat(forBus: 0)))")
        }

        guard installRecordingTap(on: input, file: file) else {
            // Transient no-input gap mid-transition (common right after a
            // Bluetooth route drops) — retry shortly; a follow-up route
            // notification usually rebuilds us anyway.
            if let delay = Self.rebuildRetryDelayMs(afterAttempt: attempt) {
                DevLog.log("rebuild attempt \(attempt) — input not ready, retrying in \(delay) ms")
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .milliseconds(delay))
                    guard let self, self.isRecording else { return }
                    // A follow-up route notification may have rebuilt us while
                    // this retry was sleeping — don't tear a live engine down.
                    if !self.isPaused, let engine = self.engine, engine.isRunning {
                        DevLog.log("rebuild retry skipped — engine already running again")
                        return
                    }
                    self.rebuildTapForCurrentRoute(attempt: attempt + 1)
                }
            } else {
                DevLog.log("rebuild backoff exhausted after \(attempt + 1) attempts — staying ARMED"
                           + " (next route/engine-config/media-services notification re-triggers)")
                showRouteNotice("Waiting for the mic — keeping what's recorded so far")
            }
            return
        }

        guard !isPaused else {
            DevLog.log("rebuild done while paused — resume() will start the engine")
            return
        }
        do {
            try engine.start()
            DevLog.log("engine restarted — input=\(currentInputName())")
        } catch {
            DevLog.log("engine restart FAILED: \(error) — staying ARMED"
                       + " (next route/engine-config/media-services notification re-triggers)")
            showRouteNotice("Waiting for the mic — keeping what's recorded so far")
        }
    }

    /// Human-readable name of the current input (e.g. "AirPods Pro",
    /// "iPhone Microphone") for the route notice.
    private func currentInputName() -> String {
        AVAudioSession.sharedInstance().currentRoute.inputs.first?.portName ?? "the built-in mic"
    }

    /// Surface a transient notice and auto-clear it after a few seconds.
    private func showRouteNotice(_ text: String) {
        routeNotice = text
        noticeClearTimer?.invalidate()
        noticeClearTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.routeNotice = nil }
        }
    }

    private func teardownRecoveryObservers() {
        if let routeObserver { NotificationCenter.default.removeObserver(routeObserver) }
        routeObserver = nil
        if let engineConfigObserver { NotificationCenter.default.removeObserver(engineConfigObserver) }
        engineConfigObserver = nil
        if let mediaServicesObserver { NotificationCenter.default.removeObserver(mediaServicesObserver) }
        mediaServicesObserver = nil
        if let interruptionObserver { NotificationCenter.default.removeObserver(interruptionObserver) }
        interruptionObserver = nil
        if let foregroundObserver { NotificationCenter.default.removeObserver(foregroundObserver) }
        foregroundObserver = nil
        interruptionActive = false
        stallSince = nil
        noticeClearTimer?.invalidate(); noticeClearTimer = nil
        for o in lifecycleObservers { NotificationCenter.default.removeObserver(o) }
        lifecycleObservers = []
        routeNotice = nil
    }

    // MARK: - Tap-install validation + rebuild backoff (pure; unit-tested)

    /// Decide whether installing the recording tap is SAFE right now.
    /// `installTap` enforces its preconditions as UNCATCHABLE NSExceptions
    /// (the round-2 P0 SIGABRT), so this check is the only defense. The tap
    /// installs in the node's CURRENT vended format whenever that format is
    /// settled:
    /// - it must be real (rate > 0, channels > 0) — mid-route-transition the
    ///   input node reports 0 Hz/0 ch;
    /// - it must AGREE with the SESSION's live hardware input format — right
    ///   after a route change the engine's cached vended format can lag the
    ///   new route (stale AirPods 24 kHz while the session is already on the
    ///   48 kHz built-in mic); capture at that stale rate would be garbage.
    ///
    /// Refuse ONLY those transient states. The FILE's format is deliberately
    /// NOT consulted: a hardware format differing from the file is the normal
    /// cross-rate rebuild (AirPods 24 kHz ↔ built-in 48 kHz) and the per-tap
    /// `AVAudioConverter` bridges tap→file. (DevLog verdict 2026-06-12 09:14:
    /// requiring "new == old/file format" here refused every cross-rate
    /// rebuild and left recordings permanently deaf on the new route.)
    /// Stateless on purpose — a refusal never poisons later attempts.
    ///
    /// NOTE (DevLog round 3): the stale-vended disagreement does NOT settle on
    /// its own — `AVAudioEngine` caches node formats until `reset()` — so the
    /// rebuild doesn't wait for it: `rebuildTapForCurrentRoute` sees the
    /// disagreement via `rebuildAction` and calls `engine.reset()` to force a
    /// re-query BEFORE this validation runs against the fresh vended format.
    nonisolated static func canInstallTap(sessionHwRate: Double, sessionHwChannels: AVAudioChannelCount,
                                          vendedRate: Double, vendedChannels: AVAudioChannelCount) -> Bool {
        vendedRate > 0 && vendedChannels > 0
            && vendedRate == sessionHwRate && vendedChannels == sessionHwChannels
    }

    /// What a rebuild attempt should do, given the SESSION's live hardware
    /// input format vs the engine's vended (possibly cached) input format
    /// (pure — the deadlock fix for DevLog round 3, 2026-06-12 09:40).
    enum RebuildAction: Equatable {
        /// Vended format is real and agrees with the hardware — install now.
        case install
        /// The hardware is live but the node vends a DIFFERENT (or dead)
        /// cached format — the round-3 refuse-loop. `engine.reset()` forces a
        /// hardware re-query, then validation runs against the fresh format.
        case resetThenRequery
        /// The hardware itself isn't ready (0 Hz / 0 ch session input) — a
        /// reset can't conjure a mic; wait out the backoff, stay armed.
        case backoff
    }

    /// Decide the rebuild step. `.resetThenRequery` whenever the session
    /// hardware looks live but `canInstallTap` would refuse — that disagreement
    /// is the engine's STALE CACHE, which never converges without `reset()`
    /// (round-3 deadlock: vended=48 kHz frozen vs sessionHw=24 kHz across every
    /// backoff retry until the user cancelled). `.backoff` only when the
    /// hardware itself reports not-ready. Stateless like `canInstallTap` — a
    /// reset or refusal history never poisons later attempts.
    nonisolated static func rebuildAction(sessionHwRate: Double, sessionHwChannels: AVAudioChannelCount,
                                          vendedRate: Double, vendedChannels: AVAudioChannelCount) -> RebuildAction {
        if canInstallTap(sessionHwRate: sessionHwRate, sessionHwChannels: sessionHwChannels,
                         vendedRate: vendedRate, vendedChannels: vendedChannels) {
            return .install
        }
        if sessionHwRate > 0, sessionHwChannels > 0 { return .resetThenRequery }
        return .backoff
    }

    /// Backoff schedule for tap-rebuild retries while a new route's input
    /// format settles: the delay (ms) to wait after a refused `attempt`
    /// (0-based), or nil once the schedule is exhausted (~3 s cumulative —
    /// generous for a Bluetooth handover). Exhaustion is NOT a give-up: the
    /// recording stays armed and the next route-change /
    /// engine-configuration-change / media-services notification re-triggers
    /// the rebuild from attempt 0.
    nonisolated static func rebuildRetryDelayMs(afterAttempt attempt: Int) -> Int? {
        let delays = [250, 400, 600, 850, 900]   // ≈3 s total
        guard attempt >= 0, attempt < delays.count else { return nil }
        return delays[attempt]
    }

    // MARK: - DevLog descriptions

    nonisolated private static func describe(_ format: AVAudioFormat) -> String {
        "\(Int(format.sampleRate))Hz/\(format.channelCount)ch"
    }

    nonisolated private static func describe(_ route: AVAudioSessionRouteDescription?) -> String {
        guard let route else { return "?" }
        let ins = route.inputs.map(\.portName).joined(separator: "+")
        let outs = route.outputs.map(\.portName).joined(separator: "+")
        return "in[\(ins.isEmpty ? "-" : ins)] out[\(outs.isEmpty ? "-" : outs)]"
    }

    nonisolated private static func name(_ reason: AVAudioSession.RouteChangeReason?) -> String {
        switch reason {
        case .newDeviceAvailable: return "newDeviceAvailable"
        case .oldDeviceUnavailable: return "oldDeviceUnavailable"
        case .categoryChange: return "categoryChange"
        case .override: return "override"
        case .wakeFromSleep: return "wakeFromSleep"
        case .noSuitableRouteForCategory: return "noSuitableRouteForCategory"
        case .routeConfigurationChange: return "routeConfigurationChange"
        case .unknown: return "unknown"
        case nil: return "nil"
        @unknown default: return "raw(\(reason.map { String($0.rawValue) } ?? "?"))"
        }
    }

    // MARK: - Format conversion (pure; unit-tested)

    /// Whether buffers tapped in `tap` format must be converted before writing
    /// to a file whose processing format is `write`. Field-by-field (not
    /// `AVAudioFormat ==`) so an irrelevant channel-layout difference can't
    /// force a needless converter.
    nonisolated static func needsConversion(from tap: AVAudioFormat, to write: AVAudioFormat) -> Bool {
        tap.sampleRate != write.sampleRate
            || tap.channelCount != write.channelCount
            || tap.commonFormat != write.commonFormat
            || tap.isInterleaved != write.isInterleaved
    }

    /// A converter bridging the current route's mic format to the file's fixed
    /// write format — or nil when the formats already match (the no-overhead
    /// common case: the route the recording started on).
    nonisolated static func makeWriteConverter(from tap: AVAudioFormat, to write: AVAudioFormat) -> AVAudioConverter? {
        guard needsConversion(from: tap, to: write) else { return nil }
        return AVAudioConverter(from: tap, to: write)
    }

    /// Convert one owned buffer to `format` using a persistent `converter`
    /// (its internal resampler state carries across calls, keeping sample-rate
    /// conversion continuous between buffers). Runs on the writer queue.
    /// Returns nil when the converter produced nothing (e.g. it's priming).
    nonisolated static func convert(
        _ buffer: AVAudioPCMBuffer,
        with converter: AVAudioConverter,
        to format: AVAudioFormat
    ) -> AVAudioPCMBuffer? {
        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 64
        guard let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: max(capacity, 1)) else { return nil }
        var fed = false
        var error: NSError?
        let status = converter.convert(to: out, error: &error) { _, outStatus in
            if fed { outStatus.pointee = .noDataNow; return nil }
            fed = true
            outStatus.pointee = .haveData
            return buffer
        }
        guard status != .error, out.frameLength > 0 else { return nil }
        return out
    }

    nonisolated private static func copyBuffer(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let dst = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength) else { return nil }
        dst.frameLength = buffer.frameLength
        let channels = Int(buffer.format.channelCount)
        let frames = Int(buffer.frameLength)
        if let src = buffer.floatChannelData, let out = dst.floatChannelData {
            for ch in 0..<channels { memcpy(out[ch], src[ch], frames * MemoryLayout<Float>.size) }
        }
        return dst
    }

    /// Poll the live caption on a SELF-PACING loop (was a fixed 0.6 s timer):
    /// each snapshot re-transcribes the whole accumulated live chunk, so its
    /// cost GROWS with the chunk — on a warm A15 the fixed cadence ran the
    /// ANE/CPU flat-out for the entire recording (heat → throttle → frozen
    /// UI). Pacing the next poll off the last snapshot's cost bounds the duty
    /// cycle, and thermal pressure stretches it further (`captionPollDelay`).
    private func startCaptionPolling() {
        captionTask?.cancel()
        captionTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let s = self, s.isRecording, s.liveTranscription else { return }
                if s.isPaused {
                    try? await Task.sleep(for: .milliseconds(400))
                    continue
                }
                let started = Date()
                let parts = await TranscriptionService.shared.liveCaptionParts()
                let cost = Date().timeIntervalSince(started)
                guard let s = self, s.isRecording, s.liveTranscription else { return }
                if !parts.full.isEmpty, !s.isPaused {
                    s.liveCaption = parts.full
                    // The REAL finalized boundary: rotated (committed) chunks
                    // never re-transcribe — drives solid-vs-volatile truthfully.
                    s.liveCommittedWordCount = parts.committed
                        .split(whereSeparator: { $0.isWhitespace }).count
                    RecordingActivityManager.shared.update(caption: parts.full)
                }
                let delay = Self.captionPollDelay(
                    afterSnapshotCost: cost,
                    thermal: ProcessInfo.processInfo.thermalState)
                try? await Task.sleep(for: .seconds(delay))
            }
        }
    }

    /// Next-poll delay after a snapshot that took `cost` seconds. The MATH moved to the
    /// shared `LiveCaptionEngine.pollDelay` (2026-07-28 — the Mac's live surface paces off
    /// the same rule; a cool M4 settles at the 0.6 s floor with no platform case). This
    /// forwarder keeps the phone's call sites and tests on their existing seam.
    nonisolated static func captionPollDelay(afterSnapshotCost cost: TimeInterval,
                                             thermal: ProcessInfo.ThermalState) -> TimeInterval {
        LiveCaptionEngine.pollDelay(afterSnapshotCost: cost, thermal: thermal)
    }

    nonisolated private static func rms(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let ch = buffer.floatChannelData?[0] else { return 0 }
        let n = Int(buffer.frameLength)
        guard n > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<n { sum += ch[i] * ch[i] }
        let rms = (sum / Float(n)).squareRoot()
        return min(1, rms * 12)   // scale like Shhhcribble's AudioInput
    }

    // MARK: - Timers / shared

    private func startDisplayTimer() {
        // 4 Hz is plenty: the timer label has 1 s resolution, the waveform is
        // driven by the tap's level pushes (not this timer), and the watchdog
        // thinks in seconds. The old 20 Hz tick re-rendered the record screen
        // for nothing.
        displayTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    private func stopTimers() {
        displayTimer?.invalidate(); displayTimer = nil
        captionTask?.cancel(); captionTask = nil
    }

    private func tick() {
        let live = segmentStart.map { Date().timeIntervalSince($0) } ?? 0
        elapsed = accumulated + (isPaused ? 0 : live)
        if !autoOffFired, autoOffSeconds > 0, isRecording, liveTranscription,
           elapsed >= Double(autoOffSeconds) {
            autoOffFired = true
            DevLog.log("live captions auto-off at \(Int(elapsed))s (limit \(autoOffSeconds)s)")
            setLiveTranscription(false)
            Haptics.tap()
        }
        if mock { mockTick() } else { watchdogTick() }
    }

    /// Last-resort capture watchdog, driven by the display timer: `elapsed` is
    /// wall-clock, so a dead engine otherwise LOOKS alive (timer counting,
    /// file silently not growing — how a half-captured message slips out
    /// looking fine). If the engine sits stopped mid-recording with no rebuild
    /// in flight and no interruption owning the mic, rebuild — this catches
    /// any stall the five recovery observers didn't (and re-drives an
    /// exhausted-backoff recording without waiting for the next notification).
    private func watchdogTick(now: Date = Date()) {
        guard isRecording, !isPaused, !interruptionActive else { stallSince = nil; return }
        if engine?.isRunning == true { stallSince = nil; return }
        let since = stallSince ?? now
        stallSince = since
        guard Self.watchdogShouldRebuild(
            stalledFor: now.timeIntervalSince(since),
            sinceLastRebuildAttempt: lastRebuildAttemptAt.map { now.timeIntervalSince($0) }) else { return }
        stallSince = nil
        DevLog.log("WATCHDOG — engine stopped with no rebuild in flight; rebuilding")
        showRouteNotice("Recovering the mic — keeping what's recorded so far")
        rebuildTapForCurrentRoute()
    }

    /// Whether the watchdog should fire (pure; unit-tested): the engine has
    /// been stopped for a couple of seconds AND the rebuild ladder isn't
    /// already on it (its retry backoff spans ~3 s — treading on a sleeping
    /// retry would double-drive the engine teardown).
    nonisolated static func watchdogShouldRebuild(stalledFor: TimeInterval,
                                                  sinceLastRebuildAttempt: TimeInterval?) -> Bool {
        guard stalledFor >= 2 else { return false }
        if let since = sinceLastRebuildAttempt, since < 4 { return false }
        return true
    }

    /// Fake level + progressive caption reveal so the caption-first UI is
    /// testable without a mic or the Neural Engine.
    private func mockTick() {
        guard !isPaused else { level = 0; return }
        level = Float(0.35 + 0.3 * abs(sin(elapsed * 5)))
        pushWaveform(level)
        // Reveal ~1 word every 0.3s of elapsed time.
        let shouldReveal = min(mockWords.count, Int(elapsed / 0.3) + 1)
        if shouldReveal > mockRevealed {
            mockRevealed = shouldReveal
            liveCaption = mockWords.prefix(mockRevealed).joined(separator: " ")
        }
    }

    private func pushWaveform(_ value: Float) {
        waveform.append(value)
        if waveform.count > Self.waveformBars { waveform.removeFirst(waveform.count - Self.waveformBars) }
    }

    private func accumulate() {
        if let start = segmentStart {
            accumulated += Date().timeIntervalSince(start)
            segmentStart = nil
        }
    }
}
