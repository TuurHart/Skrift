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
/// - **Charger job.** Pauses when unplugged, auto-resumes when charging again;
///   a foreground Pause / Resume is also offered. Best left plugged in overnight.
/// - **Never blocks live capture.** Between chunks the loop yields to an active
///   capture (`suspendForCapture`), and a chunked spot needs no engine at all,
///   so a pre-transcribed book never contends.
@MainActor
final class BookTranscriptionJob: ObservableObject {
    static let shared = BookTranscriptionJob()

    enum Phase: Equatable {
        case idle
        case running
        case pausedUnplugged          // auto-paused: on battery
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

    private let library: AudiobookLibraryStore
    private let store: BookTranscriptStore
    private let makeTranscriber: () -> any Transcriber

    private var task: Task<Void, Never>?
    private var suspendedForCapture = false
    private var batteryObserver: NSObjectProtocol?

    init(library: AudiobookLibraryStore = .shared,
         store: BookTranscriptStore = BookTranscriptStore(),
         makeTranscriber: @escaping () -> any Transcriber = { TranscriberFactory.make() }) {
        self.library = library
        self.store = store
        self.makeTranscriber = makeTranscriber
        self.measuredRTF = UserDefaults.standard.object(forKey: Self.rtfKey) as? Double
        // Turn battery monitoring on at creation (the sheet/capture flow touch the
        // singleton well before Start), so `isPluggedIn` reads a REAL state the
        // first time Start checks it. Reading `batteryState` before monitoring is
        // enabled returns `.unknown` → a false "unplugged" → "plug in to continue"
        // even while charging (device-found 2026-06-13).
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
        phase = isPluggedIn ? .running : .pausedUnplugged
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
        phase = isPluggedIn ? .running : .pausedUnplugged
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
            .appendingPathComponent("bookchunk_\(UUID().uuidString).m4a")
        defer { try? FileManager.default.removeItem(at: temp) }
        do {
            try await QuoteCaptureProcessor.exportSpan(of: audioURL, start: chunkStart, end: chunkEnd, to: temp)
            let result = try await transcriber.transcribe(audioURL: temp, imageManifest: [])
            let fileLocal = result.wordTimings.map {
                WordTiming(word: $0.word, start: $0.start + chunkStart, end: $0.end + chunkStart)
            }
            return ChunkFusion.fuse(chunkWords: fileLocal, chunkStart: chunkStart, chunkEnd: chunkEnd,
                                    isFinal: isFinal, minProgress: chunkSeconds * 0.5)
        } catch {
            return nil
        }
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

    // MARK: - Battery (charger job)

    private var isPluggedIn: Bool {
        let s = UIDevice.current.batteryState
        return s == .charging || s == .full
    }

    private func enableBatteryMonitoring() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        guard batteryObserver == nil else { return }
        batteryObserver = NotificationCenter.default.addObserver(
            forName: UIDevice.batteryStateDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.batteryChanged() }
        }
    }

    private func batteryChanged() {
        switch phase {
        case .running where !isPluggedIn:        phase = .pausedUnplugged
        case .pausedUnplugged where isPluggedIn:  phase = .running
        default: break
        }
    }
}
