import AVFoundation
import Foundation

/// The live-caption engine — the part of "words appear while you talk" that is the SAME on
/// every app: accumulate captured PCM, re-transcribe the live window in snapshots, rotate it
/// into COMMITTED chunks that never change again, and pace the caller's poll off measured
/// cost so slow hardware slows down instead of melting.
///
/// Extracted verbatim from the phone's `TranscriptionService` streaming section (2026-07-28,
/// for the Mac's live-recording surface — mock `mocks/mac-live-transcription.html` m2). That
/// code is the survivor of the phone's freeze-spiral rounds, and every rule in here is a scar:
/// the committed/volatile boundary is REAL (rotated chunks never re-transcribe — the caption's
/// solid-vs-volatile colouring lied until it was; 2026-06-10 device finding), the pacing is
/// measured-cost-driven (a fixed cadence ran an A15 flat out → heat → throttle → frozen UI),
/// and the early rotation bounds per-poll inference on old/hot hardware. On an M4 the same
/// rules simply settle near their floors — no platform tuning, by construction.
///
/// What is NOT here, on purpose: the model (an injected `Transcribe` closure — the owner keeps
/// its one loaded ASR manager and its own readiness rules), the logger (`DevLog` on the phone,
/// `os.Logger` on the Mac), and any notion of a microphone. The engine eats owned buffers and
/// emits strings.
///
/// The caption is DISPLAY + SEED, never the authoritative transcript — the one-shot pass over
/// the finished file remains the truth on both apps (the Mac's m2 surface narrows that pass to
/// the engine-owned tail once the user has edited, but that is the caller's policy, not ours).
actor LiveCaptionEngine {

    /// The one ASR call the engine makes: the merged live window in, raw text out. The owner
    /// builds it over its loaded manager (fresh decoder state per call) and may swap/clear it
    /// mid-stream as the model loads and unloads — a `nil` transcriber pauses captions without
    /// dropping audio, exactly like the phone's `guard let asr`.
    typealias Transcribe = @Sendable (AVAudioPCMBuffer) async throws -> String

    /// Committing the live window bounds live-buffer memory on long recordings — and, on the
    /// Mac's m2 surface, sets how fast text SETTLES (settled = editable = white). The phone
    /// keeps the 25 s it was tuned with (a caption strip doesn't care, and rotation costs a
    /// re-transcribe of the window — dear on an A15). The Mac passes ~7 s: Tuur's first live
    /// take, 2026-07-28 — "it seems to write a whole paragraph until it turns white … works
    /// way less clear than the Apple one" — and an M4 re-transcribes a 7 s window in well
    /// under a second, so sentence-sized settling is affordable there.
    static let defaultRotationInterval: TimeInterval = 25
    let rotationInterval: TimeInterval

    /// Pause-triggered settling (2026-07-28 research, `LANES-2026-07-28/RESEARCH_DICTATION.md`):
    /// production streaming stacks treat endpointing as the PRIMARY commit signal and the
    /// fixed window as the safety net — our timer-primary shape had it inverted. When
    /// enabled, a detected pause rotates the chunk, so text settles at PHRASE boundaries the
    /// way Apple's dictation feels — the interval above only catches the person who never
    /// stops talking. Off by default: the phone keeps its thermally-tuned timer-only
    /// behavior byte-identical.
    ///
    /// HOW a pause is detected — TEXT STABILITY, not audio level. Two real takes on the
    /// same USB mic (2026-07-28) killed the RMS approach in opposite directions: the mic's
    /// silence ripples through 0.16–0.33 on the shared scale, exactly the band its quiet
    /// speech occupies, so no energy threshold — fixed 0.15 (saw zero of seven real pauses)
    /// or adaptive noise-riding (voice never registered / fake mid-sentence pauses) — can
    /// separate the two. What CAN: the decode we already run every poll. If consecutive
    /// polls decode the live window to the IDENTICAL non-empty tail, no new words are being
    /// produced — that IS the pause, on any mic at any gain. The stable decode is adopted
    /// as the committed chunk directly (it is by definition the window's final text), so
    /// settling costs no extra ASR call.
    let pauseTriggered: Bool
    /// Identical consecutive decodes required before the tail settles. 2 = the
    /// LocalAgreement-2 sweet spot (IWSLT2022; see the research memo) — one poll of
    /// stability is just "a new decode landed", two is "and nothing changed it".
    static let stablePollsToSettle = 2
    /// Never pause-rotate a window shorter than this — tiny chunks churn the ASR for
    /// fragments and pollute `committedChunks` with confetti.
    static let minPauseWindow: TimeInterval = 2.0
    /// The live window's decode from the previous poll + how many consecutive polls it has
    /// survived unchanged. `pauseTriggered` only.
    private var lastTail = ""
    private var stableTailPolls = 0
    /// The most recent per-buffer levels (newest last), kept only while `pauseTriggered` —
    /// logged at rotate time as tuning EVIDENCE (they are what proved the mic's silence and
    /// quiet speech share a band; they no longer gate anything).
    private var recentLevels: [Float] = []
    private static let recentLevelCount = 16
    /// Hard ceiling on the live buffer (≈90 s at 48 kHz). `rotateIfNeeded` normally trims at
    /// 25 s, but it bails when no transcriber is set — so this cap (enforced in `feed`,
    /// model-independent) stops the buffer running away while a model is downloading/loading.
    static let maxStreamFrames: AVAudioFrameCount = 48_000 * 90

    private let log: @Sendable (String) -> Void

    private var transcribe: Transcribe?
    private var streamBuffers: [AVAudioPCMBuffer] = []
    /// Committed chunks with the separator each one carries BEFORE its text ("" on the
    /// first). In pause mode a chunk that follows a pause-rotated, sentence-ending chunk
    /// joins with a paragraph break — see `chunkJoin`. Timer-only (the phone) every join is
    /// a single space, so `committedText()` stays byte-identical there.
    private var committedChunks: [(join: String, text: String)] = []
    /// The separator the NEXT committed chunk will carry — a space until a
    /// paragraph-wanting boundary RESOLVES to "\n\n" (see `paragraphPendingSince`),
    /// consumed by the next append. An empty rotate in between (a silence-only window)
    /// must not disturb it: the boundary is still the last REAL chunk's.
    private var nextJoin = " "
    /// Set the moment a chunk commits off a paragraph-wanting boundary
    /// (`wantsParagraph`: pause-settle + finished sentence). The first NON-EMPTY decode
    /// after it measures the real silence and resolves `nextJoin`
    /// (`resolvedJoin(afterSilence:)`), then clears this. A chunk that commits while
    /// it is still pending keeps the space — no resumption was ever observed, so there
    /// is no evidence of a deliberate stop.
    private var paragraphPendingSince: Date?
    private var streamStartedAt: Date?
    private var lastRotationAt: Date?
    private var rotating = false
    private var snapshotRunning = false
    private var streaming = false
    /// Cost of the most recent live-window snapshot on THIS device right now — drives the
    /// caller's poll pacing and the early rotation.
    private var lastSnapshotCost: TimeInterval = 0

    init(rotationInterval: TimeInterval = LiveCaptionEngine.defaultRotationInterval,
         pauseTriggered: Bool = false,
         log: @escaping @Sendable (String) -> Void = { _ in }) {
        self.rotationInterval = rotationInterval
        self.pauseTriggered = pauseTriggered
        self.log = log
    }

    // MARK: - Session

    /// Begin a live session: clear prior state. The owner sets the transcriber separately,
    /// once (and whenever) its model is actually ready.
    func begin() {
        streamBuffers.removeAll(keepingCapacity: true)
        committedChunks.removeAll()
        nextJoin = " "
        paragraphPendingSince = nil
        streamStartedAt = Date()
        lastRotationAt = nil
        rotating = false
        streaming = true
        lastSnapshotCost = 0
        recentLevels.removeAll(keepingCapacity: true)
        lastTail = ""; stableTailPolls = 0
        transcribe = nil
    }

    /// The model became ready (or went away). Safe mid-stream in either direction.
    func setTranscriber(_ t: Transcribe?) { transcribe = t }

    /// Append a captured buffer. The caller hands off an **owned** copy — capture taps reuse
    /// their backing storage under us.
    func feed(_ ownedBuffer: AVAudioPCMBuffer) {
        guard streaming else { return }
        if pauseTriggered {
            recentLevels.append(RecordingCore.level(ownedBuffer))
            if recentLevels.count > Self.recentLevelCount { recentLevels.removeFirst() }
        }
        streamBuffers.append(ownedBuffer)
        // Safety net: if rotation isn't trimming yet (no transcriber), drop the oldest
        // buffers so memory can't run away. The audio file on disk still has everything —
        // only the live-caption prefix is sacrificed, which is empty anyway without a model.
        var total = streamBuffers.reduce(AVAudioFrameCount(0)) { $0 + $1.frameLength }
        while total > Self.maxStreamFrames, streamBuffers.count > 1 {
            total -= streamBuffers.removeFirst().frameLength
        }
    }

    /// Drop all live state (stop/cancel).
    func end() {
        streamBuffers.removeAll(keepingCapacity: false)
        committedChunks.removeAll(keepingCapacity: false)
        nextJoin = " "
        paragraphPendingSince = nil
        streamStartedAt = nil
        lastRotationAt = nil
        rotating = false
        streaming = false
        recentLevels.removeAll(keepingCapacity: false)
        lastTail = ""; stableTailPolls = 0
        transcribe = nil
    }

    // MARK: - Caption

    /// The caption split at its REAL finalized boundary: `committed` = rotated chunks that
    /// will NEVER change again; everything after is the live chunk, re-transcribed wholesale
    /// each poll (volatile). This is the true signal solid-vs-volatile rendering needs — and
    /// on the Mac's m2 surface it is also the OWNERSHIP boundary: settled text belongs to the
    /// user, the volatile tail to the engine.
    func captionParts() async -> (full: String, committed: String) {
        await rotateIfNeeded()
        let committed = committedText()
        guard transcribe != nil, !streamBuffers.isEmpty else { return (committed, committed) }
        if snapshotRunning { return (committed, committed) }
        snapshotRunning = true
        defer { snapshotRunning = false }
        guard let merged = Self.concatenate(buffers: streamBuffers) else { return (committed, committed) }
        // How many buffers this decode covers — buffers appended DURING the await below
        // (feed interleaves on the actor) sit past this index and must survive an adoption.
        let coveredBuffers = streamBuffers.count
        let windowSeconds = Double(merged.frameLength) / merged.format.sampleRate
        let started = Date()
        defer {
            lastSnapshotCost = Date().timeIntervalSince(started)
            log("live snapshot: \(String(format: "%.1f", windowSeconds))s window"
                + " → \(Int(lastSnapshotCost * 1000))ms")
        }
        do {
            guard let transcribe else { return (committed, committed) }
            let tail = try await transcribe(merged)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if tail.isEmpty {
                if pauseTriggered { lastTail = ""; stableTailPolls = 0 }
                return (committed, committed)
            }
            // Words are back. If the last boundary wanted a paragraph, NOW the silence
            // can be measured — resolve the pending join before anything can consume it
            // (a same-poll settle is impossible here, stability needs ≥2 polls, but the
            // ordering keeps that fact irrelevant).
            if let since = paragraphPendingSince {
                let silence = Date().timeIntervalSince(since)
                nextJoin = Self.resolvedJoin(afterSilence: silence)
                paragraphPendingSince = nil
                log("live join: \(nextJoin == "\n\n" ? "paragraph" : "space") after "
                    + "\(String(format: "%.1f", silence))s silence")
            }
            if pauseTriggered, streaming {
                stableTailPolls = (tail == lastTail) ? stableTailPolls + 1 : 1
                lastTail = tail
                if Self.settleOnStability(stablePolls: stableTailPolls, windowSeconds: windowSeconds) {
                    adoptStableTail(tail, coveredBuffers: coveredBuffers, windowSeconds: windowSeconds)
                    let newCommitted = committedText()
                    return (newCommitted, newCommitted)
                }
            }
            let full = committed.isEmpty ? tail : committed + " " + tail
            return (full, committed)
        } catch {
            return (committed, committed)
        }
    }

    /// A stability settle: the live window decoded to the same text `stableTailPolls` polls
    /// running, so that decode IS the window's final text — commit it verbatim (no second
    /// ASR pass) and drop exactly the audio it covered. Buffers that arrived during the
    /// decode stay for the next window. Synchronous on purpose: no await between the
    /// stability check and the commit, so no interleaved call can see a half-rotated state.
    private func adoptStableTail(_ text: String, coveredBuffers: Int, windowSeconds: Double) {
        var line = "live rotate[\(RotationTrigger.pause.rawValue)]: adopting "
            + "\(String(format: "%.1f", windowSeconds))s window"
            + " (stable \(stableTailPolls) polls)"
        if !recentLevels.isEmpty {
            line += " levels " + recentLevels.map { String(format: "%.2f", $0) }.joined(separator: " ")
        }
        log(line)
        committedChunks.append((join: committedChunks.isEmpty ? "" : nextJoin, text: text))
        nextJoin = " "
        paragraphPendingSince = Self.wantsParagraph(afterChunk: text, trigger: .pause) ? Date() : nil
        streamBuffers.removeFirst(min(coveredBuffers, streamBuffers.count))
        lastRotationAt = Date()
        lastSnapshotCost = 0   // fresh (small) window — let the pacing re-measure
        lastTail = ""
        stableTailPolls = 0
    }

    /// Stitched transcribe of the remaining buffer + committed chunks, then teardown, split at the ownership boundary — for the Mac's m2 surface, where the user
    /// may have EDITED the settled text mid-take: `finalTail` is a final-quality transcribe of
    /// ONLY the un-rotated live window (the engine's own wet ink), so the caller can finalize
    /// the engine's region without touching a word the user owns. `stitched` remains the whole
    /// thing for callers that want it. Tears down either way.
    func finishParts() async -> (stitched: String, finalTail: String) {
        var finalSegment = ""
        if let transcribe, !streamBuffers.isEmpty,
           let merged = Self.concatenate(buffers: streamBuffers) {
            finalSegment = ((try? await transcribe(merged)) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let stitched = (committedChunks.map(\.text) + [finalSegment])
            .filter { !$0.isEmpty }.joined(separator: " ")
        end()
        return (stitched, finalSegment)
    }

    private func committedText() -> String {
        committedChunks.reduce("") { $0 + $1.join + $1.text }
    }

    /// Chunk rotation: transcribe the live buffer into a committed chunk and clear it — at
    /// the `rotationInterval` hard cap (bounds memory), or EARLY once snapshots have grown
    /// expensive for this device (bounds per-poll inference cost — see `rotationTrigger`).
    private func rotateIfNeeded() async {
        guard !rotating, let transcribe, !streamBuffers.isEmpty else { return }
        let started = lastRotationAt ?? streamStartedAt ?? Date()
        let window = Date().timeIntervalSince(started)
        guard let trigger = Self.rotationTrigger(
            sinceRotation: window, lastSnapshotCost: lastSnapshotCost,
            interval: rotationInterval) else { return }
        // The feel-tuning evidence in one line (backlog ROUND 10): WHICH trigger fired and —
        // pause mode only — the recent buffer levels. (Pause settles never come through
        // here; they adopt synchronously in `captionParts` — see `adoptStableTail`.)
        var line = "live rotate[\(trigger.rawValue)]: committing "
            + "\(String(format: "%.1f", window))s window"
            + " (last snapshot \(Int(lastSnapshotCost * 1000))ms)"
        if !recentLevels.isEmpty {
            line += " levels " + recentLevels.map { String(format: "%.2f", $0) }.joined(separator: " ")
        }
        log(line)
        rotating = true
        let snapshot = streamBuffers
        streamBuffers.removeAll(keepingCapacity: true)
        defer { rotating = false }
        guard let merged = Self.concatenate(buffers: snapshot) else { return }
        if let text = try? await transcribe(merged) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                committedChunks.append((join: committedChunks.isEmpty ? "" : nextJoin,
                                        text: trimmed))
                nextJoin = " "
                paragraphPendingSince = Self.wantsParagraph(afterChunk: trimmed, trigger: trigger) ? Date() : nil
            }
        }
        lastRotationAt = Date()
        lastSnapshotCost = 0   // fresh (small) window — let the pacing re-measure
        // The stability state described the window this rotate just consumed.
        lastTail = ""
        stableTailPolls = 0
    }

    // MARK: - Pure rules (unit-tested; both apps' behavior hangs off these)

    /// Why a rotation fired — logged per rotate so a real take can be read back trigger by
    /// trigger (the ROUND 10 instrumentation: "mid-sentence whitening" is only diagnosable
    /// once every settle says whether a pause, the ceiling, or the cost guard caused it).
    enum RotationTrigger: String {
        case pause      // the tail decode went stable — the primary settle signal
        case ceiling    // the fixed interval — the person who never stops talking
        case cost       // snapshots grew expensive — old/hot hardware protection
    }

    /// Which POLL-TIME trigger (if any) should rotate the live chunk now. The hard cap
    /// bounds live-buffer memory; the early path commits a window whose snapshots have
    /// grown expensive (> 1.2 s) so per-poll cost stays bounded on old/hot hardware instead
    /// of climbing for the full 25 s. (`.pause` never comes from here — a stability settle
    /// is decided per-snapshot in `captionParts`, see `settleOnStability`.)
    nonisolated static func rotationTrigger(sinceRotation: TimeInterval,
                                            lastSnapshotCost: TimeInterval,
                                            interval: TimeInterval = defaultRotationInterval) -> RotationTrigger? {
        if sinceRotation > interval { return .ceiling }
        // The early path only matters when it beats the cap (the phone's 25 s on old/hot
        // hardware); with a short cap it simply never fires first.
        if sinceRotation > 10, lastSnapshotCost > 1.2 { return .cost }
        return nil
    }

    /// Whether a live window whose decode has survived `stablePolls` consecutive polls
    /// unchanged should settle. Two identical decodes = no new words for at least a full
    /// poll cycle — a real phrase pause on ANY microphone (level thresholds could not say
    /// that; see `pauseTriggered`'s doc). The window guard keeps fragments out of
    /// `committedChunks` exactly like every other rotate.
    nonisolated static func settleOnStability(stablePolls: Int, windowSeconds: Double) -> Bool {
        stablePolls >= stablePollsToSettle && windowSeconds >= minPauseWindow
    }

    /// Whether the chunk that just committed ASKS for a paragraph before whatever comes
    /// next — a pause-settle after a finished sentence. Whether it GETS one is decided
    /// later, when speech resumes (`resolvedJoin`): the settle only proves a pause
    /// STARTED, the resumption says how long it really was. Deciding at settle time gave
    /// every sentence-end breath a paragraph and shredded Tuur's first real takes into
    /// one-line paragraphs (ROUND 11, 2026-07-28: "a lot of gaps in there"). Ceiling and
    /// cost rotates are not speech boundaries (the person kept talking). Timer-only mode
    /// (the phone) can never produce `.pause`, so its committed text is byte-identical.
    nonisolated static func wantsParagraph(afterChunk chunk: String, trigger: RotationTrigger) -> Bool {
        guard trigger == .pause,
              let lastWord = chunk.split(whereSeparator: \.isWhitespace).last else { return false }
        return Paragrapher.endsSentence(String(lastWord))
    }

    /// The join a paragraph-wanting boundary resolves to once speech resumes after
    /// `silence` seconds: a DELIBERATE stop (`Paragrapher.longFormGap` — the same
    /// threshold the Mac file pass uses, so draft and resting note agree) breaks; a
    /// breath joins with a space. The measured silence runs settle → first non-empty
    /// decode, which lags real speech onset by up to a poll cycle — on the Mac's 0.4 s
    /// polls the threshold maps to ~1.5 s of true silence.
    nonisolated static func resolvedJoin(afterSilence silence: TimeInterval) -> String {
        silence >= Paragrapher.longFormGap ? "\n\n" : " "
    }

    /// Next-poll delay after a snapshot that took `cost` seconds. ≥1.5× the cost bounds the
    /// live-caption ASR duty cycle to ~40% so the accelerator breathes between snapshots;
    /// thermal pressure raises the floor (a hot phone throttles into the freeze spiral
    /// otherwise); the 6 s cap keeps captions alive even at `.critical`.
    /// `floor` — the phone keeps the tuned 0.6 s default untouched. The Mac's m2 surface
    /// passes 0.4: a stability settle needs `stablePollsToSettle` whole poll cycles after
    /// the last word, so the poll floor IS the felt settle latency there, and an M4's
    /// ~0.1–0.25 s snapshots stay under a 40% duty cycle even at 0.4 s.
    nonisolated static func pollDelay(afterSnapshotCost cost: TimeInterval,
                                      thermal: ProcessInfo.ThermalState,
                                      floor: TimeInterval = 0.6) -> TimeInterval {
        let paced = min(max(floor, cost * 1.5), 6)
        switch thermal {
        case .serious:  return max(paced, 2.5)
        case .critical: return max(paced, 6)
        default:        return paced
        }
    }

    // MARK: - Buffer helpers (ported from Shhhcribble TextEngine via the phone)

    static func copyBuffer(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let dst = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength) else { return nil }
        dst.frameLength = buffer.frameLength
        let channels = Int(buffer.format.channelCount)
        let frames = Int(buffer.frameLength)
        if let src = buffer.floatChannelData, let out = dst.floatChannelData {
            for ch in 0..<channels { memcpy(out[ch], src[ch], frames * MemoryLayout<Float>.size) }
        }
        return dst
    }

    static func concatenate(buffers: [AVAudioPCMBuffer]) -> AVAudioPCMBuffer? {
        guard let first = buffers.first else { return nil }
        let format = first.format
        let total = buffers.reduce(AVAudioFrameCount(0)) { $0 + $1.frameLength }
        guard total > 0, let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: total) else { return nil }
        out.frameLength = total
        let channels = Int(format.channelCount)
        var offset = 0
        for buf in buffers {
            let frames = Int(buf.frameLength)
            if let src = buf.floatChannelData, let dst = out.floatChannelData {
                for ch in 0..<channels { memcpy(dst[ch] + offset, src[ch], frames * MemoryLayout<Float>.size) }
            }
            offset += frames
        }
        return out
    }
}
