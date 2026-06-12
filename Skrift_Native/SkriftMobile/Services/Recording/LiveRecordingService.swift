import AVFoundation
import Combine
import Foundation

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
final class LiveRecordingService: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var isPaused = false
    @Published private(set) var elapsed: TimeInterval = 0
    /// Smoothed input level, 0...1.
    @Published private(set) var level: Float = 0
    /// Rolling level history (newest last) for the live waveform bars.
    @Published private(set) var waveform: [Float] = []
    /// Best-effort live transcript shown caption-first while recording.
    @Published private(set) var liveCaption: String = ""
    /// A brief, self-clearing notice surfaced when the audio route changes
    /// mid-recording (e.g. AirPods pulled out) — so the user knows capture may
    /// have hiccuped without the recording being dropped. nil = nothing to show.
    @Published private(set) var routeNotice: String?

    /// Whether live captioning is on (Settings toggle; default on). Off = record
    /// + waveform only, transcript comes from the one-shot pass after stop.
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

    private let mock: Bool
    private static let waveformBars = 40

    private var engine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var tempURL: URL?

    // Mirrored, audio-thread-readable copies of the gating state. The tap runs
    // on a real-time thread; reading MainActor-isolated @Published vars there
    // would be a data race, so we mirror what the tap needs.
    private nonisolated(unsafe) var tapPaused = false
    private nonisolated(unsafe) var tapLive = true
    /// Set before tearing down the tap so a callback already past `installTap`'s
    /// guard doesn't enqueue another write while we're finalizing the file.
    private nonisolated(unsafe) var tapStopped = false
    /// File encode (AAC) + RMS run here, OFF the real-time audio render thread,
    /// so disk/encode work can't cause render overruns. Drained at stop before
    /// the `AVAudioFile` is released.
    private let writerQueue = DispatchQueue(label: "skrift.recording.writer")

    private var displayTimer: Timer?
    private var captionTimer: Timer?
    private var routeObserver: NSObjectProtocol?
    private var noticeClearTimer: Timer?
    private var segmentStart: Date?
    private var accumulated: TimeInterval = 0

    // Mock-only progressive caption state.
    private var mockWords: [String] = []
    private var mockRevealed = 0

    init(mock: Bool = LaunchFlags.seedTranscript != nil,
         liveTranscription: Bool = UserDefaults.standard.object(forKey: "liveTranscription") as? Bool ?? true) {
        self.mock = mock
        self.liveTranscription = liveTranscription
    }

    deinit {
        // Belt-and-braces teardown for an abnormal dismissal where stop()/cancel()
        // never ran: kill ALL timers + the route observer directly. (deinit is
        // nonisolated, so it can't call the @MainActor stopTimers()/
        // teardownRouteObserver() helpers — inline the same work.)
        displayTimer?.invalidate()
        captionTimer?.invalidate()
        noticeClearTimer?.invalidate()
        if let routeObserver { NotificationCenter.default.removeObserver(routeObserver) }
    }

    /// Start, retrying briefly when the audio session is contended. Owned by the
    /// service (not the view) so the retries die with the recorder — `[weak self]`
    /// means a dismissed RecordView can never ghost-start a recording. With
    /// `siriGrace` (a pending Record-intent launch) the first attempt waits 700 ms:
    /// right after a voice launch Siri still owns the audio session, and
    /// contending instantly just burns retries. A plain in-app open starts at once.
    func startRetrying(siriGrace: Bool = false) {
        guard !isRecording else { return }
        Task { @MainActor [weak self] in
            if siriGrace { try? await Task.sleep(for: .milliseconds(700)) }
            for _ in 0..<16 {
                guard let self, !self.isRecording else { return }
                do { try self.start(); return }
                catch { /* session busy (e.g. Siri releasing the mic) — retry */ }
                try? await Task.sleep(for: .milliseconds(300))
            }
        }
    }

    func start() throws {
        guard !isRecording else { return }
        accumulated = 0
        elapsed = 0
        level = 0
        waveform = []
        liveCaption = ""
        let url = AppPaths.recordingsDirectory.appendingPathComponent("rec_tmp_\(UUID().uuidString).m4a")
        tempURL = url

        tapPaused = false
        tapStopped = false
        tapLive = liveTranscription

        if mock {
            FileManager.default.createFile(atPath: url.path, contents: Data())
            mockWords = (LaunchFlags.seedTranscript ?? "").split(separator: " ").map(String.init)
            mockRevealed = 0
        } else {
            try startEngine(writingTo: url)
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

    func pause() {
        guard isRecording, !isPaused else { return }
        accumulate()
        isPaused = true
        tapPaused = true
        if !mock { engine?.pause(); RecordingActivityManager.shared.pause() }
    }

    func resume() {
        guard isRecording, isPaused else { return }
        if !mock { try? engine?.start() }
        segmentStart = Date()
        isPaused = false
        tapPaused = false
        if !mock { RecordingActivityManager.shared.resume(elapsed: elapsed) }
    }

    struct Result { let url: URL; let duration: TimeInterval; let liveCaption: String }

    func stop() -> Result? {
        guard isRecording else { return nil }
        accumulate()
        stopTimers()
        teardownRouteObserver()
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
            engine = nil
            audioFile = nil
            try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
            if liveTranscription { Task { await TranscriptionService.shared.endStream() } }
            RecordingActivityManager.shared.end()
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
        teardownRouteObserver()
        if !mock {
            tapStopped = true
            engine?.inputNode.removeTap(onBus: 0)
            engine?.stop()
            writerQueue.sync {}    // drain pending writes before finalizing the file
            audioFile?.close()     // finalize before the temp file is deleted below
            engine = nil
            audioFile = nil
            try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
            if liveTranscription { Task { await TranscriptionService.shared.endStream() } }
            RecordingActivityManager.shared.end()
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
    }

    // MARK: - Real engine

    private func startEngine(writingTo url: URL) throws {
        let session = AVAudioSession.sharedInstance()
        // .default (not .measurement): .measurement strips input gain/AGC, which
        // made recordings very quiet → soft playback + a barely-moving waveform.
        // A voice-memo wants normal capture gain.
        try session.setCategory(.playAndRecord, mode: .default, options: [.allowBluetooth, .defaultToSpeaker])
        try session.setActive(true)

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings)
        self.audioFile = file

        installRecordingTap(on: input, file: file)
        try engine.start()
        self.engine = engine
        observeRouteChanges()
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
    private func installRecordingTap(on input: AVAudioInputNode, file: AVAudioFile) {
        let tapFormat = input.outputFormat(forBus: 0)
        let writeFormat = file.processingFormat
        let converter = Self.makeWriteConverter(from: tapFormat, to: writeFormat)
        input.installTap(onBus: 0, bufferSize: 4096, format: tapFormat) { [weak self] buffer, _ in
            guard let self, !self.tapPaused, !self.tapStopped,
                  let copy = Self.copyBuffer(buffer) else { return }
            let live = self.tapLive
            self.writerQueue.async { [weak self] in
                let out: AVAudioPCMBuffer
                if let converter {
                    guard let converted = Self.convert(copy, with: converter, to: writeFormat) else { return }
                    out = converted
                } else {
                    out = copy
                }
                try? file.write(from: out)
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
    private func observeRouteChanges() {
        guard routeObserver == nil else { return }
        routeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] note in
            MainActor.assumeIsolated {
                self?.handleRouteChange(note)
            }
        }
    }

    private func handleRouteChange(_ note: Notification) {
        guard isRecording, !mock else { return }
        let reasonValue = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
        let reason = reasonValue.flatMap { AVAudioSession.RouteChangeReason(rawValue: $0) }

        switch reason {
        case .oldDeviceUnavailable, .newDeviceAvailable, .categoryChange:
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
            if !isPaused, let engine, !engine.isRunning {
                rebuildTapForCurrentRoute()
            }
        }
    }

    /// Survive a route change: tear the tap down, re-query the input node's NEW
    /// hardware format, reinstall the tap in that format (converting buffers to
    /// the file's fixed write format — see `installRecordingTap`), and restart
    /// the engine. Pull AirPods out → capture continues on the built-in mic;
    /// re-insert → capture continues on the AirPods, same `.m4a` throughout.
    /// A failure here doesn't drop the recording — the file already holds what
    /// was captured, and the user is shown the notice.
    private func rebuildTapForCurrentRoute(retry: Bool = true) {
        guard isRecording, let engine, let file = audioFile else { return }
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
        let newFormat = input.outputFormat(forBus: 0)
        guard newFormat.sampleRate > 0, newFormat.channelCount > 0 else {
            // Transient no-input gap mid-transition (common right after a
            // Bluetooth route drops) — retry once shortly; the follow-up route
            // notification usually rebuilds us anyway.
            if retry {
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .milliseconds(300))
                    guard let self, self.isRecording else { return }
                    self.rebuildTapForCurrentRoute(retry: false)
                }
            } else {
                showRouteNotice("Lost the mic input — tap Stop to keep what was recorded")
            }
            return
        }

        installRecordingTap(on: input, file: file)
        guard !isPaused else { return }   // resume() starts the engine
        do {
            try engine.start()
        } catch {
            showRouteNotice("Lost the mic input — tap Stop to keep what was recorded")
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

    private func teardownRouteObserver() {
        if let routeObserver { NotificationCenter.default.removeObserver(routeObserver) }
        routeObserver = nil
        noticeClearTimer?.invalidate(); noticeClearTimer = nil
        routeNotice = nil
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

    private func startCaptionPolling() {
        captionTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isRecording, !self.isPaused else { return }
                Task {
                    let caption = await TranscriptionService.shared.liveCaption()
                    if !caption.isEmpty {
                        self.liveCaption = caption
                        RecordingActivityManager.shared.update(caption: caption)
                    }
                }
            }
        }
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
        displayTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    private func stopTimers() {
        displayTimer?.invalidate(); displayTimer = nil
        captionTimer?.invalidate(); captionTimer = nil
    }

    private func tick() {
        let live = segmentStart.map { Date().timeIntervalSince($0) } ?? 0
        elapsed = accumulated + (isPaused ? 0 : live)
        if mock { mockTick() }
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
