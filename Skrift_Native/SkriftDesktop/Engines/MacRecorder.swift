import AVFoundation
import AppKit
import AudioToolbox
import CoreAudio
import CoreMedia
import Foundation
import Observation
import os

/// Microphone capture on the Mac. The phone's `LiveRecordingService` could not be ported —
/// it is built around `AVAudioSession`, which does not exist on macOS — so this is the
/// platform half, deliberately small: capture the input, write an m4a, publish elapsed + level.
/// Everything that decides how the recording sounds, what it is called, and how the meter
/// reads comes from the SHARED `RecordingCore`, so a Mac memo and a phone memo are the same
/// artefact.
///
/// **Built on `AVCaptureSession`, not `AVAudioEngine`** (`LANES-2026-07-28/RESEARCH_MIC.md`).
/// `AVAudioEngine.inputNode` and `outputNode` SHARE one `AUAudioUnit` on macOS, defaulting to
/// the system output device, and pointing it at another device from outside the engine's own
/// state machine is not a supported reconfiguration path (the symptom was near-zero or noise
/// buffers). `AVCaptureSession` + `AVCaptureDeviceInput` takes a specific device BY
/// CONSTRUCTION.
///
/// macOS needs no session category and has no iOS route-change war (no HFP flip, no phone-call
/// interruptions): you pick an input in System Settings and it stays; a device pulled
/// mid-take ends the capture (`.AVCaptureDeviceWasDisconnected`). What it DOES need,
/// which iOS does not, is the sandbox's `com.apple.security.device.audio-input` entitlement
/// plus a usage string — without both, capture yields silence rather than an error.
@MainActor
@Observable
final class MacRecorder {

    enum State: Equatable {
        case idle
        case recording
        /// The mic was refused, or the session could not start. Carries what to tell the user.
        case failed(Refusal)
    }

    /// The typed refusal lives in `Shared/Recording/RecordingRefusal.swift` (Q164) so the phone shows the same one.
    typealias Refusal = RecordingCore.Refusal


    /// Every gate in `start()` logs its verdict. This exists because the record path failed
    /// twice with the user watching and nothing written down anywhere — diagnosing it meant
    /// asking a person what a dialog said, and running `-miccheck` from a shell turned out to
    /// answer for the SHELL HOST's TCC identity, not this app's (2026-07-28: it read DENIED
    /// both before and after a successful `tccutil reset`, because the denial it was reading
    /// belonged to the terminal's responsible process). The one attribution that is always
    /// honest is the GUI app asking about itself — so it says what it sees, where
    /// `log show --predicate 'subsystem == "com.skrift.desktop"'` can read it back.
    private static let log = Logger(subsystem: "com.skrift.desktop", category: "record")

    private(set) var state: State = .idle
    private(set) var elapsed: TimeInterval = 0
    private(set) var meter = RecordingCore.Meter()

    var isRecording: Bool { state == .recording }
    var elapsedLabel: String { RecordingCore.elapsedLabel(elapsed) }

    /// A second consumer, beside the file writer — the live-caption engine's feed
    /// (`LiveRecordingSession`). Invoked on the sink's own callback queue (never Main, never
    /// blocking it) with an OWNED copy (`LiveCaptionEngine.copyBuffer`): the same discipline
    /// the phone's tap needs, kept here even though this capture path already allocates a
    /// fresh `AVAudioPCMBuffer` per callback — the two apps' contracts stay symmetric, and a
    /// future capture path change can't quietly reintroduce aliased storage. Set BEFORE
    /// `start()` — it is read once, synchronously, while building the capture session; a
    /// nil consumer (no live caption running) costs nothing extra.
    var onLiveBuffer: ((AVAudioPCMBuffer) -> Void)?

    // MARK: - capture plumbing

    private var session: AVCaptureSession?
    private var deviceInput: AVCaptureDeviceInput?
    private var audioOutput: AVCaptureAudioDataOutput?
    private var sampleSink: SampleSink?
    /// `startRunning`/`stopRunning` both block — never touched from Main. One dedicated queue
    /// for the pair so a stop can never race a start's configuration.
    private let configQueue = DispatchQueue(label: "com.skrift.desktop.record.session")
    /// The sample delegate's own queue — never Main, never `configQueue`.
    private let callbackQueue = DispatchQueue(label: "com.skrift.desktop.record.samples")

    /// The take's MAIN file — `rec_tmp_<take>.m4a` beside its segments + marker (C99, Q163).
    private var url: URL?
    private var startedAt: Date?
    /// Id of the take in flight (or just stopped). Names the main file, the 60 s segments
    /// and the marker, so the launch sweep (`RecordingSweep`) can find them after a kill.
    private var takeID: String?
    /// The take's segment + marker writer, handed over by the sink once its writer is closed.
    private var checkpoint: RecordingCheckpoint?
    private var checkpointSealed = false
    /// The last stopped take, kept until the arrival path has stored it (`discardFinishedTake`)
    /// — the files are deleted only AFTER the note exists, never before.
    private var finishedTake: (id: String, directory: URL)?
    private var terminateObserver: NSObjectProtocol?
    private var sleepObserver: NSObjectProtocol?

    /// Said in the draft pane when the input died mid-take but the words so far survive
    /// (recsj-029: this used to tear the take down with no message at all).
    private(set) var lossNotice: String?
    /// Why the take ended on its own (a write failure). Titles the note (R46); nil for a
    /// take the user stopped.
    private(set) var endedReason: String?
    /// Fired (main actor) when the recorder ends the take itself — a write failure — so
    /// the owner can stop + save. Set BEFORE `start()`.
    var onTakeEnded: ((String) -> Void)?

    /// R46: the disk refused a write. Honest about what is NOT known (full disk vs another
    /// I/O error) and about what is safe.
    nonisolated static let writeFailureMessage =
        "Recording stopped: the disk refused a write (it may be full). Everything recorded up to that point is saved."

    private var ticker: Timer?
    /// The input this take is actually listening to — for the stop-time verdict, so a dead
    /// take can NAME the device that produced it instead of shrugging.
    private var activeInputName = "the microphone"
    /// Did the sink ever deliver a non-zero sample? A dozing Bluetooth mic produces either no
    /// buffers at all or exact digital zeros — a real mic's noise floor is never exactly 0.
    private var sawSignal = false
    /// Has the FIRST buffer of this take arrived yet? Drives both the fail-fast timer and the
    /// first-buffer-opens-the-file rule.
    private var receivedFirstBuffer = false
    private var disconnectObserver: NSObjectProtocol?
    private var runtimeErrorObserver: NSObjectProtocol?
    /// Bumped once per `start()`. The fail-fast timer and the sink's closures are async and
    /// outlive any single take's lifetime by design — without tagging them, a quick
    /// Record→Stop→Record cycle under 1.5s would let the FIRST take's fail-fast timer fire
    /// during the SECOND take and kill it. Every async callback checks its captured generation
    /// against the current one before touching state.
    private var takeGeneration = 0

    /// Ask for the mic, then start. Returns false when permission was refused or the session
    /// refused to start — `state` carries the message either way.
    @discardableResult
    func start() async -> Bool {
        guard state != .recording else { return true }
        Self.log.notice("start(): tcc=\(AVCaptureDevice.authorizationStatus(for: .audio).rawValue, privacy: .public) hasInput=\(Self.hasInputDevice, privacy: .public)")
        // Hardware first: asking for permission to use a mic that doesn't exist prompts the
        // user for nothing and then fails anyway.
        guard Self.hasInputDevice else {
            Self.log.error("start(): REFUSED — no input device")
            state = .failed(.noInputDevice)
            return false
        }
        guard await Self.requestMicAccess() else {
            // Re-read AFTER the request: `.notDetermined` becomes `.denied` the moment the
            // user clicks Don't Allow, and that is the case worth naming precisely — from
            // then on macOS never prompts again, so the only way back is Settings.
            let status = AVCaptureDevice.authorizationStatus(for: .audio)
            Self.log.error("start(): REFUSED — mic access, tcc now=\(status.rawValue, privacy: .public)")
            state = .failed(Self.refusal(for: status))
            return false
        }
        // The phone's b119 policy, ported: with Bluetooth around, record on a wired mic.
        let inputs = Self.inputDevices()
        guard let chosen = Self.pickInput(from: inputs, systemDefault: Self.defaultInputID) else {
            Self.log.error("start(): REFUSED — hardware sees an input but AVCaptureDevice does not")
            state = .failed(.noUsableFormat)
            return false
        }
        activeInputName = chosen.name
        guard let captureDevice = Self.captureDevice(forID: chosen.id) else {
            Self.log.error("start(): REFUSED — could not resolve AVCaptureDevice for \(chosen.name, privacy: .public)")
            state = .failed(.noUsableFormat)
            return false
        }
        Self.log.notice("start(): input ← \(chosen.name, privacy: .public) of \(inputs.count, privacy: .public)")

        let take = UUID().uuidString
        let dest = AppPaths.recordingsDirectory.appendingPathComponent(RecordingCheckpoint.mainFilename(take: take))
        do {
            try FileManager.default.createDirectory(at: AppPaths.recordingsDirectory,
                                                    withIntermediateDirectories: true)
        } catch {
            Self.log.error("start(): REFUSED — could not create recordings directory: \(String(describing: error), privacy: .public)")
            state = .failed(.engineFailed(error.localizedDescription))
            return false
        }

        let input: AVCaptureDeviceInput
        do {
            input = try AVCaptureDeviceInput(device: captureDevice)
        } catch {
            Self.log.error("start(): ENGINE THREW building the input — \(String(describing: error), privacy: .public)")
            state = .failed(.engineFailed(error.localizedDescription))
            return false
        }

        let session = AVCaptureSession()
        session.beginConfiguration()
        guard session.canAddInput(input) else {
            session.commitConfiguration()
            Self.log.error("start(): REFUSED — session could not add the input")
            state = .failed(.engineFailed("the microphone input could not be added to the capture session"))
            return false
        }
        session.addInput(input)

        let output = AVCaptureAudioDataOutput()
        // Float32, non-interleaved: RecordingCore.level() reads floatChannelData?[0] assuming
        // non-interleaved float samples — an interleaved stereo buffer would alias two
        // channels into one RMS read. Sample rate and channel COUNT are deliberately left
        // unset here so they follow the device's own negotiated format; only the sample
        // representation is fixed.
        output.audioSettings = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            // The one settings constant with no "Key" suffix — its siblings all have one.
            AVLinearPCMIsNonInterleaved: true,
        ]
        guard session.canAddOutput(output) else {
            session.commitConfiguration()
            Self.log.error("start(): REFUSED — session could not add the audio output")
            state = .failed(.engineFailed("the audio output could not be added to the capture session"))
            return false
        }
        session.addOutput(output)
        session.commitConfiguration()

        takeGeneration += 1
        let generation = takeGeneration
        receivedFirstBuffer = false
        sawSignal = false
        lossNotice = nil
        endedReason = nil
        checkpoint = nil
        checkpointSealed = false
        takeID = take

        let sink = SampleSink(destination: dest, takeID: take, queue: callbackQueue,
            onWriteFailure: { [weak self] detail in
                Task { @MainActor [weak self] in
                    guard let self, self.takeGeneration == generation else { return }
                    self.handleWriteFailure(detail, generation: generation)
                }
            },
            onFirstBuffer: { [weak self] format in
                Task { @MainActor [weak self] in
                    guard let self, self.takeGeneration == generation else { return }
                    self.receivedFirstBuffer = true
                    Self.log.notice("start(): FIRST BUFFER ← \(self.activeInputName, privacy: .public) format=\(format.sampleRate, privacy: .public)Hz/\(format.channelCount, privacy: .public)ch")
                }
            },
            onLevel: { [weak self] level in
                Task { @MainActor [weak self] in
                    guard let self, self.takeGeneration == generation else { return }
                    self.meter.push(level)
                    if level > 0 { self.sawSignal = true }
                }
            },
            onLiveBuffer: onLiveBuffer)
        output.setSampleBufferDelegate(sink, queue: callbackQueue)

        self.session = session
        self.deviceInput = input
        self.audioOutput = output
        self.sampleSink = sink
        self.url = dest
        self.startedAt = Date()
        self.elapsed = 0
        self.meter = RecordingCore.Meter()
        self.state = .recording
        startTicker()
        installLossObservers(device: captureDevice, session: session, generation: generation)
        installLifecycleObservers()
        scheduleFailFastCheck(generation: generation)
        RecordingLifecycleLog.log("start", "take=\(take) input=\(chosen.name)")

        Self.log.notice("start(): session configured, dispatching startRunning() on \(self.activeInputName, privacy: .public) → \(dest.lastPathComponent, privacy: .public)")
        configQueue.async { session.startRunning() }
        return true
    }

    /// Stop and hand back the finished file, or nil if nothing usable was captured. The
    /// caller ingests it exactly like an imported file — that is the whole point: a Mac
    /// recording is not a new kind of thing, it is a file arriving by a different door.
    ///
    /// A dead take leaves `state` at `.failed` with the device's NAME, never `.idle`. This
    /// path used to fold "nothing arrived" into a silent nil, and the caller's message went
    /// somewhere invisible — so a dozing Bluetooth mic produced a transport that counted,
    /// a stop that shrugged, and a user who reasonably concluded the feature was broken.
    @discardableResult
    func stop() -> URL? {
        guard state == .recording else { return nil }
        Self.log.notice("stop(): after \(RecordingCore.elapsedLabel(self.elapsed), privacy: .public), signal=\(self.sawSignal, privacy: .public)")
        ticker?.invalidate(); ticker = nil
        // Drains the writer queue, closes the main file, closes the open segment and writes
        // the marker (C224: "writer queue drained on stop") — BEFORE anything reads the file.
        teardownSession()
        let main = url
        let take = takeID
        url = nil
        startedAt = nil
        guard let main, let take else {
            elapsed = 0
            state = .failed(.nothingCaptured(activeInputName))
            return nil
        }
        let directory = main.deletingLastPathComponent()

        // Hand the arrival path a `memo_<id>.m4a` (the phone's naming; it becomes the Memo's
        // audio filename). The main file stays as `rec_tmp_*` until the note is stored —
        // a hard link, so a nearly-full disk costs nothing.
        let staged = directory.appendingPathComponent(
            RecordingCore.filename(id: UUID(uuidString: take) ?? UUID()))
        try? FileManager.default.removeItem(at: staged)
        let mainReadable = RecordingCheckpoint.isReadableAudio(main)
        var rebuildFailed = false
        if mainReadable {
            if (try? FileManager.default.linkItem(at: main, to: staged)) == nil {
                try? FileManager.default.copyItem(at: main, to: staged)
            }
        } else if let cp = checkpoint, !cp.segmentURLs.isEmpty {
            // A write failure can leave the main file without its index (a dead m4a). The
            // closed segments hold the same audio: rebuild from them.
            let segments = cp.segmentURLs.filter(RecordingCheckpoint.isReadableAudio)
            do {
                try AudioClipMerge.merge(sources: segments, to: staged)
                RecordingLifecycleLog.log("finalize", "take=\(take) rebuilt from \(segments.count) segment(s)")
            } catch {
                RecordingLifecycleLog.log("finalize", "take=\(take) rebuild FAILED (\(error)) — files kept for the launch sweep")
                try? FileManager.default.removeItem(at: staged)
                rebuildFailed = true
            }
        }
        finishedTake = (take, directory)
        let size = (try? FileManager.default.attributeOfItemSize(at: staged)) ?? 0
        if rebuildFailed {
            // Audio WAS captured but nothing could be handed over: keep every file — the
            // launch sweep rebuilds the note from the segments.
            state = .failed(.engineFailed("the recording could not be finalised. It is kept and will appear as a recovered note the next time Skrift opens."))
            elapsed = 0
            finishedTake = nil
            releaseTake()
            return nil
        }
        // No signal = a broken take whatever its byte count: an encoder fed zeros (or
        // nothing) still writes headers and frames, so size alone can't tell a quiet room
        // from a dead input. Delete it and say which device let us down.
        if let reason = RecordingCore.deadTakeVerdict(fileBytes: Int(size), sawSignal: sawSignal, deviceName: activeInputName) {
            discardFinishedTake()
            releaseTake()
            elapsed = 0
            state = .failed(reason)
            Self.log.error("stop(): DEAD TAKE — \(size, privacy: .public) bytes from \(self.activeInputName, privacy: .public)")
            return nil
        }
        state = .idle
        releaseTake()
        RecordingLifecycleLog.log("finalize", "reason=stop take=\(take)")
        return staged
    }

    /// Delete the last stopped take's files — main, segments, marker and the staged
    /// `memo_*` copy. Call ONLY once the note exists (the arrival path stored it): until
    /// then these files are the only copy, and the next launch's sweep would rebuild them.
    func discardFinishedTake() {
        guard let (take, directory) = finishedTake else { return }
        finishedTake = nil
        RecordingCheckpoint.discardTakeFiles(take: take, in: directory)
        RecordingCheckpoint.discardIfExists(
            directory.appendingPathComponent(RecordingCore.filename(id: UUID(uuidString: take) ?? UUID())))
    }

    /// Abandon the take and delete the file — for a cancel, or a window closing mid-record.
    /// Clears any stop-time verdict too: the user threw this take away on purpose, so a
    /// "nothing was captured" complaint about it would be noise.
    func cancel() {
        guard state == .recording else { clearFailure(); return }
        _ = stop()
        clearFailure()
        discardFinishedTake()
    }

    func clearFailure() { if case .failed = state { state = .idle } }

    private func startTicker() {
        ticker?.invalidate()
        // 4 Hz: the label has 1s resolution and the meter is pushed by the sink, not by this.
        ticker = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let started = self.startedAt else { return }
                self.elapsed = Date().timeIntervalSince(started)
            }
        }
    }

    /// Tear down everything session-side: observers, the delegate (so the output releases the
    /// sink), then the session itself. Dispatched off Main — brief's rule: the main thread
    /// must never wait on the session, only ever hand it work.
    ///
    /// Also CLOSES THE WRITER, synchronously: waits out any callback already on the writer
    /// queue, closes the main file, closes the open segment, and writes the marker as
    /// finalised when the main file reads back. Idempotent — `stop()` calls it again after a
    /// loss already did.
    private func teardownSession() {
        if let observer = disconnectObserver { NotificationCenter.default.removeObserver(observer); disconnectObserver = nil }
        if let observer = runtimeErrorObserver { NotificationCenter.default.removeObserver(observer); runtimeErrorObserver = nil }
        if let observer = terminateObserver { NotificationCenter.default.removeObserver(observer); terminateObserver = nil }
        if let observer = sleepObserver { NSWorkspace.shared.notificationCenter.removeObserver(observer); sleepObserver = nil }
        audioOutput?.setSampleBufferDelegate(nil, queue: nil)
        let sessionToStop = session
        session = nil
        deviceInput = nil
        audioOutput = nil
        configQueue.async { sessionToStop?.stopRunning() }
        sealWriter()
    }

    /// Close the main file + the open segment and write the final marker. Runs once per take.
    private func sealWriter() {
        guard !checkpointSealed, let sink = sampleSink else { return }
        checkpointSealed = true
        let cp = sink.closeWriter()          // drains the writer queue first
        checkpoint = cp
        guard let cp, let main = url else { return }
        if RecordingCheckpoint.isReadableAudio(main) {
            cp.finalize()                    // the sweep prefers a cleanly closed main file
        } else {
            cp.rotate(reason: "close")       // main unreadable (write failure): segments carry the take
        }
    }

    /// The take is over (stopped, or thrown away): drop the sink so its files are released.
    /// The files on disk stay until `discardFinishedTake` — or the sweep — deals with them.
    private func releaseTake() {
        sampleSink = nil
        checkpoint = nil
        takeID = nil
    }

    private func installLifecycleObservers() {
        // A kill leaves segments; a clean quit (⌘Q mid-take) should leave the finished file
        // too. `willTerminate` closes the writer so the sweep next launch sees a finalised take.
        terminateObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.state == .recording else { return }
                RecordingLifecycleLog.log("finalize", "reason=terminate")
                self.teardownSession()
            }
        }
        // Closing a segment before the Mac sleeps — the lid shut with a take running is where
        // a battery death happens.
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.sampleSink?.rotateNow(reason: "sleep") }
        }
    }

    // MARK: - write failure (R46)

    /// The disk refused a write. Stop capturing — nothing more can land — close what did,
    /// and tell the owner so the take is stopped and SAVED, the note titled with the reason.
    private func handleWriteFailure(_ detail: String, generation: Int) {
        guard state == .recording, takeGeneration == generation, endedReason == nil else { return }
        Self.log.error("handleWriteFailure(): \(detail, privacy: .public)")
        RecordingLifecycleLog.log("write-failed", detail)
        endedReason = Self.writeFailureMessage
        ticker?.invalidate(); ticker = nil
        teardownSession()
        onTakeEnded?(Self.writeFailureMessage)
    }

    // MARK: - mid-take device loss (brief §7)

    private func installLossObservers(device: AVCaptureDevice, session: AVCaptureSession, generation: Int) {
        let center = NotificationCenter.default
        disconnectObserver = center.addObserver(forName: .AVCaptureDeviceWasDisconnected, object: device, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.handleLoss(reason: "device disconnected", generation: generation) }
        }
        runtimeErrorObserver = center.addObserver(forName: .AVCaptureSessionRuntimeError, object: session, queue: .main) { [weak self] note in
            let why = (note.userInfo?[AVCaptureSessionErrorKey] as? Error)?.localizedDescription ?? "session runtime error"
            Task { @MainActor [weak self] in self?.handleLoss(reason: why, generation: generation) }
        }
    }

    /// A device vanished, or the session itself errored, mid-take. Captured words beat a
    /// clean error: if the take already holds signal, it SURVIVES — `state` stays `.recording`
    /// and the file/url stay put, so the next `stop()` call (whenever it comes) finalizes and
    /// returns it exactly like a user-pressed stop. Only a take that holds NOTHING gets the
    /// dead-take verdict immediately, because there is nothing to lose by finalizing now.
    private func handleLoss(reason: String, generation: Int) {
        guard state == .recording, takeGeneration == generation else { return }
        Self.log.error("handleLoss(): input lost mid-take (\(reason, privacy: .public)) — signal=\(self.sawSignal, privacy: .public)")
        RecordingLifecycleLog.log("input-lost", "take=\(takeID ?? "?") reason=\(reason) signal=\(sawSignal)")
        teardownSession()                    // also closes the writer + finalises the marker
        ticker?.invalidate(); ticker = nil   // freeze the displayed time — a torn-down session must not keep counting
        guard !sawSignal else {
            // Survives: left exactly as a normal in-progress take, but SAID (recsj-029).
            lossNotice = "“\(activeInputName)” stopped delivering audio (\(reason)). What was recorded up to here is saved. Press Stop to keep it."
            return
        }
        let name = activeInputName
        discardAllTakeFiles()
        url = nil
        startedAt = nil
        elapsed = 0
        state = .failed(.nothingCaptured(name))
    }

    /// A take that holds nothing: remove its files (main, segments, marker) and drop the sink.
    private func discardAllTakeFiles() {
        if let take = takeID, let dir = url?.deletingLastPathComponent() {
            RecordingCheckpoint.discardTakeFiles(take: take, in: dir)
        }
        releaseTake()
    }

    // MARK: - fail-fast (brief §6)

    /// Pure decision: has this take gone long enough with nothing delivered that it should be
    /// given up on? Free of `Timer`/`Task`/`Date` so it's testable without waiting on a clock.
    nonisolated static func shouldFailFast(elapsedSinceStart: TimeInterval, hasReceivedBuffer: Bool) -> Bool {
        RecordingCore.shouldFailFast(elapsedSinceStart: elapsedSinceStart, hasReceivedBuffer: hasReceivedBuffer)
    }

    private func scheduleFailFastCheck(generation: Int) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard let self, self.takeGeneration == generation, self.state == .recording else { return }
            guard Self.shouldFailFast(elapsedSinceStart: 1.5, hasReceivedBuffer: self.receivedFirstBuffer) else { return }
            Self.log.error("start(): FAIL-FAST — no buffer within 1.5s from \(self.activeInputName, privacy: .public)")
            let name = self.activeInputName
            self.teardownSession()
            self.ticker?.invalidate(); self.ticker = nil
            self.discardAllTakeFiles()
            self.url = nil
            self.startedAt = nil
            self.elapsed = 0
            self.state = .failed(.nothingCaptured(name))
        }
    }

    // MARK: - Input choice (the phone's b119 policy, ported)

    /// One capture-capable device, as the pick rule sees it. `isBluetooth` is precomputed
    /// from the CoreAudio transport type so the rule itself stays pure and host-testable.
    struct InputDevice: Equatable {
        var id: AudioDeviceID
        var name: String
        var isBluetooth: Bool
    }

    /// Which input a take should listen to. The phone learned this policy on hardware
    /// (b114–b119, the AirPods saga): a Bluetooth mic is the one class of input that can be
    /// present, selected, and asleep — so with Bluetooth around, record on a wired mic. Here:
    /// keep the system default unless it's Bluetooth AND a non-Bluetooth input exists, in
    /// which case take the first non-Bluetooth one. A Bluetooth-only Mac still records over
    /// Bluetooth — a maybe-asleep mic beats no mic, and the stop-time verdict catches the
    /// sleeping case by name.
    nonisolated static func pickInput(from devices: [InputDevice],
                                      systemDefault: AudioDeviceID?) -> InputDevice? {
        guard !devices.isEmpty else { return nil }
        let fallback = devices.first { $0.id == systemDefault } ?? devices[0]
        guard fallback.isBluetooth, let wired = devices.first(where: { !$0.isBluetooth }) else {
            return fallback
        }
        return wired
    }

    /// Every audio-capture-capable device macOS exposes to `AVCaptureDevice`, translated to
    /// our `AudioDeviceID`-keyed struct so `pickInput`'s policy (and its tests) stay untouched
    /// by the switch away from `AVAudioEngine`.
    static func inputDevices() -> [InputDevice] {
        let discovery = AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone, .external],
                                                         mediaType: .audio, position: .unspecified)
        return discovery.devices.compactMap { device in
            guard let id = deviceID(forUniqueID: device.uniqueID) else { return nil }
            return InputDevice(id: id, name: device.localizedName, isBluetooth: isBluetoothTransport(id))
        }
    }

    /// The `AVCaptureDevice` behind an `AudioDeviceID` `pickInput` chose — round-tripped
    /// through the device's CoreAudio UID, since `AVCaptureDeviceInput` needs the capture
    /// object, not the id `pickInput`'s policy reasons about.
    private static func captureDevice(forID id: AudioDeviceID) -> AVCaptureDevice? {
        guard let uid = deviceUID(for: id) else { return nil }
        let discovery = AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone, .external],
                                                         mediaType: .audio, position: .unspecified)
        return discovery.devices.first { $0.uniqueID == uid }
    }

    private static func deviceID(forUniqueID uniqueID: String) -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslateUIDToDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var uid = uniqueID as CFString
        var deviceID = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = withUnsafeMutablePointer(to: &uid) { uidPtr in
            AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address,
                                       UInt32(MemoryLayout<CFString>.size), uidPtr, &size, &deviceID)
        }
        return (status == noErr && deviceID != kAudioObjectUnknown) ? deviceID : nil
    }

    private static func deviceUID(for id: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var uid: CFString? = nil
        var size = UInt32(MemoryLayout<CFString?>.size)
        let status = withUnsafeMutablePointer(to: &uid) {
            AudioObjectGetPropertyData(id, &address, 0, nil, &size, $0)
        }
        return status == noErr ? uid as String? : nil
    }

    private static func isBluetoothTransport(_ id: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var transport = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &transport) == noErr else { return false }
        return transport == kAudioDeviceTransportTypeBluetooth
            || transport == kAudioDeviceTransportTypeBluetoothLE
    }

    /// The system's default input device id, or nil when there is none at all.
    static var defaultInputID: AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID)
        return (status == noErr && deviceID != kAudioObjectUnknown) ? deviceID : nil
    }

    /// Is there a microphone AT ALL — asked of the audio hardware, not of TCC.
    ///
    /// This distinction is the whole point. `AVCaptureDevice.DiscoverySession` comes back
    /// empty in two completely different situations: a machine with no mic, and a machine
    /// with a mic we haven't been granted yet. Using it to decide whether to offer recording
    /// would disable the feature on every Mac that simply hasn't been asked yet. CoreAudio's
    /// default-input property is not gated by privacy, so it answers the hardware question
    /// honestly.
    ///
    /// (Found the hard way: a Mac mini with no input device at all reported "no microphone"
    /// through a code path that looked identical to "permission pending".)
    static var hasInputDevice: Bool { defaultInputID != nil }

    private static func requestMicAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
    }

    /// TCC's verdict, translated into something the UI can act on. Split out from `start()`
    /// so it can be tested without a microphone, a grant, or a running app — the mapping is
    /// the part that decides whether the user is offered a way out, and it was previously
    /// buried in an async function that needs real hardware to reach.
    nonisolated static func refusal(for status: AVAuthorizationStatus) -> Refusal {
        // `.notDetermined` reaching here means the prompt itself was declined (or could not
        // be shown, as from a CLI launch): the shared mapping treats it as "denied".
        RecordingCore.refusal(for: status)
    }
}

/// Bridges `AVCaptureAudioDataOutput`'s delegate callback — fired on our own dedicated queue,
/// never the main thread — to the take's file and meter. Deliberately NOT `@MainActor`
/// (`MacRecorder` is): the callback must not wait on that actor, so this plain `NSObject` owns
/// the write side of the take and only ever reaches back to `MacRecorder` through the
/// `onFirstBuffer`/`onLevel` closures, which themselves hop with `Task { @MainActor in }` —
/// exactly like the old tap closure this replaces.
private final class SampleSink: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
    private static let log = Logger(subsystem: "com.skrift.desktop", category: "record")

    private let destination: URL
    private let takeID: String
    /// The writer queue — the capture delegate's own queue. Everything that touches `file` /
    /// `checkpoint` runs on it; the main actor reaches in only through `closeWriter` /
    /// `rotateNow`, which `sync` onto it (no callback ever waits on Main, so that cannot deadlock).
    private let queue: DispatchQueue
    private let onWriteFailure: (String) -> Void
    private let onFirstBuffer: (AVAudioFormat) -> Void
    private let onLevel: (Float) -> Void
    private let onLiveBuffer: ((AVAudioPCMBuffer) -> Void)?
    private var file: AVAudioFile?
    /// 60 s segments + the marker beside the main file (C99/D131, Q163). Created with the
    /// first buffer — the rate and channel count are only known then.
    private var checkpoint: RecordingCheckpoint?
    private var failed = false
    private var closed = false

    init(destination: URL,
         takeID: String,
         queue: DispatchQueue,
         onWriteFailure: @escaping (String) -> Void,
         onFirstBuffer: @escaping (AVAudioFormat) -> Void,
         onLevel: @escaping (Float) -> Void,
         onLiveBuffer: ((AVAudioPCMBuffer) -> Void)? = nil) {
        self.destination = destination
        self.takeID = takeID
        self.queue = queue
        self.onWriteFailure = onWriteFailure
        self.onFirstBuffer = onFirstBuffer
        self.onLevel = onLevel
        self.onLiveBuffer = onLiveBuffer
    }

    /// Wait out any callback in flight, close the main file and the open segment, and hand
    /// back the checkpoint (nil when no buffer ever arrived). After this no buffer is written.
    func closeWriter() -> RecordingCheckpoint? {
        queue.sync {
            closed = true
            file?.close()
            file = nil
            checkpoint?.rotate(reason: "close")
            return checkpoint
        }
    }

    /// Close the open segment and rewrite the marker now (the Mac is about to sleep).
    func rotateNow(reason: String) {
        queue.sync { checkpoint?.rotate(reason: reason) }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard !closed, !failed, let pcm = Self.pcmBuffer(from: sampleBuffer) else { return }
        if file == nil {
            // THE rule from RESEARCH_MIC §iii, made structural: settings — and the exact PCM
            // shape the file is opened to accept — come from the format THIS buffer actually
            // arrived in, never a value read before the session started running.
            do {
                let settings = RecordingCore.encoderSettings(for: pcm.format)
                file = try AVAudioFile(forWriting: destination,
                                       settings: settings,
                                       commonFormat: pcm.format.commonFormat,
                                       interleaved: pcm.format.isInterleaved)
                // Segments take Float32 non-interleaved buffers (the capture output is
                // configured that way). Any other shape skips the checkpoint — logged, never
                // a failed take: the main file is still the take.
                if pcm.format.commonFormat == .pcmFormatFloat32, !pcm.format.isInterleaved {
                    checkpoint = RecordingCheckpoint(directory: destination.deletingLastPathComponent(),
                                                     takeID: takeID, settings: settings,
                                                     sampleRate: pcm.format.sampleRate)
                } else {
                    RecordingLifecycleLog.log("checkpoint-skipped", "take=\(takeID) format=\(pcm.format)")
                }
                onFirstBuffer(pcm.format)
            } catch {
                Self.log.error("first buffer: could not open the file — \(String(describing: error), privacy: .public)")
                return
            }
        }
        // R46: a failed write (disk full) used to be logged and ignored — the timer kept
        // counting over a file that stopped growing. The first failure now ends the take.
        do {
            try file?.write(from: pcm)
            try checkpoint?.write(pcm)
        } catch {
            failed = true
            Self.log.error("write failed: \(String(describing: error), privacy: .public)")
            onWriteFailure(String(describing: error))
            return
        }
        onLevel(RecordingCore.level(pcm))
        // The live-caption fan-out: an OWNED copy, since the caller's feed may hold onto it
        // across an actor hop while this callback moves on to the next buffer.
        if let onLiveBuffer, let copy = LiveCaptionEngine.copyBuffer(pcm) {
            onLiveBuffer(copy)
        }
    }

    /// One delivered buffer, converted from Core Media's wire format to the PCM buffer
    /// everything downstream already understands (`RecordingCore.level`, `AVAudioFile.write`).
    /// `nil` on anything CoreMedia can't describe as PCM — dropped rather than crashing on a
    /// malformed sample.
    ///
    /// `AVAudioPCMBuffer(pcmFormat:frameCapacity:)` allocates its OWN correctly-shaped storage
    /// (the right number of channel buffers for `format`, interleaved or not) and owns it via
    /// normal ARC — deliberately not the zero-copy `bufferListNoCopy` initializer, which would
    /// hand back a bare `AudioBufferList` header sized for exactly one channel (Swift's
    /// imported struct has room for one `AudioBuffer`) and require us to hand-manage that
    /// header's memory for as long as the PCM buffer lives. A non-interleaved stereo mic would
    /// need two buffer slots; getting that lifetime wrong by hand is a worse bug than the copy
    /// this avoids paying for.
    private static func pcmBuffer(from sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard CMSampleBufferDataIsReady(sampleBuffer) else { return nil }
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription),
              let format = AVAudioFormat(streamDescription: asbd) else { return nil }
        let frameCount = CMSampleBufferGetNumSamples(sampleBuffer)
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount))
        else { return nil }
        buffer.frameLength = AVAudioFrameCount(frameCount)
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer, at: 0, frameCount: Int32(frameCount), into: buffer.mutableAudioBufferList)
        guard status == noErr else { return nil }
        return buffer
    }
}

private extension FileManager {
    func attributeOfItemSize(at url: URL) throws -> Int {
        (try attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
    }
}
