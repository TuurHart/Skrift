import AVFoundation
import Foundation
import UIKit

/// Wave-2 text-capture: the resumable whole-book transcribe job (design
/// `mocks/text-capture-DESIGN.md` §4/§13). "Transcribe book" from the player ⋯
/// menu runs this; it makes text-capture instant + available anywhere.
///
/// Contract:
/// - **Resume state = the sidecar.** Each chunk is transcribed → fused → saved
///   atomically (`BookTranscriptStore`) before the next starts. On any
///   interruption (cancel, unplug, app kill, jetsam) the in-flight chunk was
///   never saved, so on resume it re-transcribes from the last saved frontier —
///   "discard the half-chunk and go again." Idempotent per chunk.
/// - **Runs on battery.** Transcribes plugged in OR on battery; it only auto-pauses
///   to conserve — when Low Power Mode is on (the user's explicit "save battery"
///   signal) or the charge drops below `lowBatteryPauseLevel` — and auto-resumes when
///   charging again or the condition clears. A foreground Pause / Resume is also
///   offered. Still best overnight on a charger for a full book.
/// - **Never blocks live capture.** Between chunks the loop yields to an active
///   capture (`suspendForCapture`), and a chunked spot needs no engine at all,
///   so a pre-transcribed book never contends.
@MainActor
final class BookTranscriptionJob: ObservableObject {
    static let shared = BookTranscriptionJob()

    enum Phase: Equatable {
        case idle
        case running
        case pausedUnplugged          // auto-paused to conserve: Low Power Mode or low battery
        case pausedByUser
        case finished
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    /// 0…1 across the WHOLE book (covered seconds / total seconds).
    @Published private(set) var progress: Double = 0
    /// The book currently being transcribed (nil when idle/finished).
    @Published private(set) var activeBookID: UUID?
    /// MEASURED throughput — audio-seconds transcribed per wall-second (the
    /// real-time factor, e.g. 6 = 6× realtime). Updated live as chunks complete
    /// and persisted, so the transcribe screen shows a REAL per-device estimate
    /// (never a fabricated number). nil until the first chunk on a device has
    /// been timed. Meaningless on the seeded sim (no ANE) — device-measured.
    @Published private(set) var measuredRTF: Double?

    private var runAudioSeconds: TimeInterval = 0
    private var runComputeSeconds: TimeInterval = 0
    private static let rtfKey = "bookTranscribeRTF"

    /// Per chunk: bigger = less per-chunk overhead, but a longer interruption
    /// loss and a longer wait for a capture that lands mid-chunk. 60 s is a
    /// middle ground (FluidAudio internally re-chunks ~15 s within it).
    private let chunkSeconds: TimeInterval = 60
    /// Seconds of preceding audio fed as decode context before each chunk (dropped
    /// from the kept words) so the chunk's opening words aren't garbled by a cold
    /// decoder. This is a decode WARM-UP, not a content overlap — ~a sentence of
    /// run-up saturates the model's start context; bigger just re-transcribes
    /// already-kept audio to throw away (wasted compute + seam re-decode risk) for
    /// no accuracy gain. Seams themselves are handled by ChunkFusion's sentence
    /// redo-tail, not by this lead. See `transcribeChunk`.
    private static let chunkLead: TimeInterval = 3.0

    private let library: AudiobookLibraryStore
    private let store: BookTranscriptStore
    private let makeTranscriber: () -> any Transcriber

    private var task: Task<Void, Never>?
    private var suspendedForCapture = false
    private var batteryObserver: NSObjectProtocol?
    private var levelObserver: NSObjectProtocol?
    private var powerModeObserver: NSObjectProtocol?

    init(library: AudiobookLibraryStore = .shared,
         store: BookTranscriptStore = BookTranscriptStore(),
         makeTranscriber: @escaping () -> any Transcriber = { TranscriberFactory.make() }) {
        self.library = library
        self.store = store
        self.makeTranscriber = makeTranscriber
        self.measuredRTF = UserDefaults.standard.object(forKey: Self.rtfKey) as? Double
        // Turn battery monitoring on at creation (the sheet/capture flow touch the
        // singleton well before Start), so the power policy reads a REAL state the
        // first time Start checks it. Reading `batteryState`/`batteryLevel` before
        // monitoring is enabled returns `.unknown`/`-1` (device-found 2026-06-13).
        enableBatteryMonitoring()
    }

    /// Estimated wall-seconds to finish `book` from the current coverage, using
    /// the measured throughput. nil until a per-device rate exists. The screen
    /// turns this into "≈ N min left" — a real number, not a placeholder.
    func estimatedRemainingSeconds(for book: Audiobook) -> TimeInterval? {
        guard let rtf = measuredRTF, rtf > 0 else { return nil }
        let remainingAudio = max(0, book.duration * (1 - progress))
        return remainingAudio / rtf
    }

    var isRunningOrPaused: Bool {
        switch phase { case .running, .pausedUnplugged, .pausedByUser: return true; default: return false }
    }

    // MARK: - Controls

    /// Start (or resume from the saved frontier) transcribing `book`. No-op if a
    /// job for this book is already live.
    func start(book: Audiobook) {
        if activeBookID == book.id, isRunningOrPaused { return }
        cancel()
        enableBatteryMonitoring()   // ensure `isPluggedIn` is valid before we read it
        activeBookID = book.id
        progress = savedProgress(for: book)
        runAudioSeconds = 0
        runComputeSeconds = 0
        phase = shouldConserve ? .pausedUnplugged : .running   // runs on battery unless conserving
        let id = book.id
        task = Task { [weak self] in await self?.run(bookID: id) }
    }

    /// Saved on-disk progress for `book` (sidecar coverage ÷ duration), 0…1.
    /// Lets the sheet show the REAL % (and the "Resume" label + estimate) the
    /// moment it opens — before Start — instead of 0.
    func savedProgress(for book: Audiobook) -> Double {
        publishValue(book: book, starts: book.fileStartTimes)
    }

    /// Reflect `book`'s saved progress when idle so the sheet bar/label/estimate
    /// are correct on open (the resume state was always preserved on disk; this
    /// just shows it). No-op while a job is live — it owns `progress`.
    func reflectSavedProgress(for book: Audiobook) {
        guard !isRunningOrPaused else { return }
        progress = savedProgress(for: book)
    }

    func pauseByUser() { if phase == .running || phase == .pausedUnplugged { phase = .pausedByUser } }

    func resumeByUser() {
        guard phase == .pausedByUser else { return }
        phase = shouldConserve ? .pausedUnplugged : .running
    }

    func cancel() {
        task?.cancel()
        task = nil
        if isRunningOrPaused { phase = .idle }
        activeBookID = nil
    }

    /// Live capture is starting — yield the engine so the capture's window
    /// transcribe (un-chunked spot) isn't stuck behind a chunk. The loop checks
    /// this between chunks. A chunked spot needs no engine, so this only matters
    /// while the book is still being transcribed.
    func suspendForCapture() { suspendedForCapture = true }
    func resumeAfterCapture() { suspendedForCapture = false }

    // MARK: - Loop

    private func run(bookID: UUID) async {
        guard let book = library.book(id: bookID) else { phase = .failed("book missing"); return }
        let transcriber = makeTranscriber()
        let starts = book.fileStartTimes

        for fileIndex in book.files.indices {
            if Task.isCancelled { return }
            let fileDuration = book.fileDurations.indices.contains(fileIndex) ? book.fileDurations[fileIndex] : 0
            guard fileDuration > 0 else { continue }
            let audioURL = library.audioURL(of: book, fileIndex: fileIndex)
            guard FileManager.default.fileExists(atPath: audioURL.path) else { continue }
            let signature = store.signature(forFileAt: audioURL)

            var ft = store.load(bookID: bookID, fileIndex: fileIndex, expectedSignature: signature)
                ?? FileTranscript(fileIndex: fileIndex, signature: signature)

            while ft.coveredUpTo < fileDuration - 0.05 {
                if Task.isCancelled { return }
                await awaitRunnable()
                if Task.isCancelled { return }

                let chunkStart = ft.coveredUpTo
                let chunkEnd = min(chunkStart + chunkSeconds, fileDuration)
                let isFinal = chunkEnd >= fileDuration - 0.05

                let started = Date()
                guard let kept = await transcribeChunk(
                    transcriber: transcriber, audioURL: audioURL,
                    chunkStart: chunkStart, chunkEnd: chunkEnd, isFinal: isFinal)
                else {
                    // Export/transcribe failed for this chunk — skip past it so the
                    // job doesn't wedge; the gap stays an un-chunked (wave-1) spot.
                    ft = ft.appending([], upTo: chunkEnd)
                    try? store.save(ft, bookID: bookID)
                    publishProgress(book: book, starts: starts)
                    continue
                }

                // Save-after-complete: only now does the frontier advance on disk.
                ft = ft.appending(kept.kept, upTo: kept.newFrontier)
                do { try store.save(ft, bookID: bookID) }
                catch { phase = .failed("save failed: \(error.localizedDescription)"); return }
                recordThroughput(audioSeconds: chunkEnd - chunkStart,
                                 computeSeconds: Date().timeIntervalSince(started))
                publishProgress(book: book, starts: starts)
            }
        }
        if !Task.isCancelled {
            progress = 1
            phase = .finished
            activeBookID = nil
        }
    }

    /// Export `[chunkStart, chunkEnd]` of the file, transcribe it, offset the
    /// word-timings to FILE-LOCAL, and fuse to the keepable words + new frontier.
    /// Returns nil on export/transcribe failure. The temp file is always cleaned.
    private func transcribeChunk(transcriber: any Transcriber, audioURL: URL,
                                 chunkStart: TimeInterval, chunkEnd: TimeInterval,
                                 isFinal: Bool) async -> ChunkFusion.Fused? {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("bookchunk_\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: temp) }
        do {
            // SAMPLE-ACCURATE extraction (NOT AVAssetExportSession): exporting a
            // compressed-MP3 timeRange drifts progressively late with seek position
            // (Mac `-chunksim` proof 2026-06-13: export thirds −0.24/+0.38/+0.96 vs
            // PCM −0.02/−0.02/−0.01), which made the read-along trail by ~1–2 s deep
            // in a chapter. AVAudioFile frame reads are drift-free.
            //
            // LEADING CONTEXT (2026-06-19): a chunk is transcribed from a COLD
            // decoder with no preceding audio, so its OPENING words get mis-decoded
            // / wrongly capitalised (device artifacts "UndetectedED", "WILLIM
            // RAULF"). Prepend ~2 s of audio before chunkStart as decode context,
            // then DROP those lead-in words (they're the previous chunk's already-
            // kept tail) — keeping word times exactly file-local. First chunk has no
            // lead. Cheap (~3% more audio); chunkEnd behaviour is unchanged, so
            // ChunkFusion's redo-tail still owns the trailing seam.
            let lead: TimeInterval = chunkStart > 0 ? Self.chunkLead : 0
            let extractStart = chunkStart - lead
            try Self.extractPCM(of: audioURL, start: extractStart, end: chunkEnd, to: temp)
            let result = try await transcriber.transcribe(audioURL: temp, imageManifest: [])
            let fileLocal = result.wordTimings.compactMap { wt -> WordTiming? in
                let start = wt.start + extractStart           // temp t=0 maps to extractStart
                // Drop the lead-in context words (they were kept by the previous
                // chunk). Tolerance absorbs cross-decode timing jitter on the
                // FRONTIER word: ChunkFusion rewinds the frontier to a word the
                // next chunk must re-transcribe whole, and its re-decoded start can
                // land a fraction before the recorded frontier — a hairline guard
                // would drop it and re-introduce the seam gap. 0.2 s stays well
                // under the gap to the (dropped) preceding lead word, so it can't
                // duplicate one.
                guard start >= chunkStart - 0.2 else { return nil }   // drop lead-in context
                return WordTiming(word: wt.word, start: start, end: wt.end + extractStart)
            }
            return ChunkFusion.fuse(chunkWords: fileLocal, chunkStart: chunkStart, chunkEnd: chunkEnd,
                                    isFinal: isFinal, minProgress: chunkSeconds * 0.5)
        } catch {
            return nil
        }
    }

    /// Sample-accurate extraction of `[start, end]` to a temp WAV via AVAudioFile
    /// frame reads — drift-free, unlike `AVAssetExportSession` on compressed audio
    /// (see `transcribeChunk`). FluidAudio transcribes the WAV; word times then
    /// align to the original file at every seek depth.
    static func extractPCM(of url: URL, start: TimeInterval, end: TimeInterval, to dst: URL) throws {
        let file = try AVAudioFile(forReading: url)
        let sr = file.processingFormat.sampleRate
        file.framePosition = AVAudioFramePosition(max(0, start) * sr)
        let frames = AVAudioFrameCount(max(0, end - start) * sr)
        guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frames) else {
            throw QuoteCaptureError.exportFailed
        }
        try file.read(into: buffer, frameCount: frames)
        try? FileManager.default.removeItem(at: dst)
        let out = try AVAudioFile(forWriting: dst, settings: file.processingFormat.settings)
        try out.write(from: buffer)
    }

    /// Block while paused (user or unplugged) or yielding to a capture. Polls
    /// cheaply; returns immediately when runnable or cancelled.
    private func awaitRunnable() async {
        while !Task.isCancelled {
            if phase == .running, !suspendedForCapture { return }
            try? await Task.sleep(nanoseconds: 300_000_000)
        }
    }

    // MARK: - Progress

    private func publishProgress(book: Audiobook, starts: [TimeInterval]) {
        progress = publishValue(book: book, starts: starts)
    }

    /// Covered seconds across all files / total book seconds.
    private func publishValue(book: Audiobook, starts: [TimeInterval]) -> Double {
        let total = book.duration
        guard total > 0 else { return 0 }
        var covered: TimeInterval = 0
        for fileIndex in book.files.indices {
            let dur = book.fileDurations.indices.contains(fileIndex) ? book.fileDurations[fileIndex] : 0
            guard dur > 0 else { continue }
            let url = library.audioURL(of: book, fileIndex: fileIndex)
            let sig = store.signature(forFileAt: url)
            let c = store.load(bookID: book.id, fileIndex: fileIndex, expectedSignature: sig)?.coveredUpTo ?? 0
            covered += min(c, dur)
        }
        return min(1, covered / total)
    }

    // MARK: - Throughput (real per-device speed; replaces the placeholder estimate)

    /// Fold one completed chunk's timing into the measured real-time factor and
    /// persist it. DEBUG-logs the per-chunk + cumulative rate so a device devlog
    /// pull shows the REAL per-hour transcribe speed (the handoff's measurement).
    private func recordThroughput(audioSeconds: TimeInterval, computeSeconds: TimeInterval) {
        guard audioSeconds > 0, computeSeconds > 0.01 else { return }
        runAudioSeconds += audioSeconds
        runComputeSeconds += computeSeconds
        let rtf = runAudioSeconds / runComputeSeconds
        measuredRTF = rtf
        UserDefaults.standard.set(rtf, forKey: Self.rtfKey)
        let minPerHour = rtf > 0 ? 60.0 / rtf : 0   // wall-minutes to transcribe 1 h of audio
        DevLog.log(String(format: "book-transcribe: chunk %.0fs audio in %.1fs (%.1f× rt) — cumulative %.1f× → ~%.1f min/hr",
                          audioSeconds, computeSeconds, audioSeconds / computeSeconds, rtf, minPerHour))
    }

    // MARK: - Power policy (runs on battery; pauses only to conserve)

    /// Below this charge (and not charging) the job auto-pauses to avoid draining the
    /// phone flat. While paused it draws nothing, so the level won't keep falling →
    /// no flapping; charging resumes it immediately.
    private static let lowBatteryPauseLevel: Float = 0.20

    private var isPluggedIn: Bool {
        let s = UIDevice.current.batteryState
        return s == .charging || s == .full
    }

    /// True when we should pause to conserve: ON BATTERY and either Low Power Mode is
    /// on (the user's explicit save-battery signal) or the charge is low. Plugged in →
    /// never conserves.
    private var shouldConserve: Bool {
        guard !isPluggedIn else { return false }
        if ProcessInfo.processInfo.isLowPowerModeEnabled { return true }
        let level = UIDevice.current.batteryLevel   // -1 when monitoring is off (we enable it)
        return level >= 0 && level < Self.lowBatteryPauseLevel
    }

    private func enableBatteryMonitoring() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        guard batteryObserver == nil else { return }
        let recheck: @Sendable (Notification) -> Void = { [weak self] _ in
            Task { @MainActor in self?.powerStateChanged() }
        }
        batteryObserver = NotificationCenter.default.addObserver(
            forName: UIDevice.batteryStateDidChangeNotification, object: nil, queue: .main, using: recheck)
        levelObserver = NotificationCenter.default.addObserver(
            forName: UIDevice.batteryLevelDidChangeNotification, object: nil, queue: .main, using: recheck)
        powerModeObserver = NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main, using: recheck)
    }

    /// Re-evaluate run/pause when power conditions change (charge, level, Low Power
    /// Mode). Only moves between `.running` and the auto-pause — never overrides a user
    /// pause or a terminal phase.
    private func powerStateChanged() {
        switch phase {
        case .running where shouldConserve:          phase = .pausedUnplugged
        case .pausedUnplugged where !shouldConserve: phase = .running
        default: break
        }
    }
}
