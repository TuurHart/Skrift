import SwiftUI
import UIKit

/// Caption-first record screen (mockup4 ready · mockup5 recording + camera).
/// The live transcript is the hero; the waveform/timer are compact; the camera
/// is on-demand (a sheet that slides up while recording keeps running). On stop
/// the memo is persisted immediately and `onSaved` fires with its id so the
/// caller can open it in Memo detail (the save-now post-record flow).
struct RecordView: View {
    // `@Observable` service (not ObservableObject): SwiftUI tracks reads
    // PER PROPERTY PER VIEW BODY, so the high-frequency state (elapsed,
    // level/waveform, caption) invalidates only the small child views that
    // read it — this shell re-renders on rare changes (isRecording, pause,
    // route notice), not 30×/s like the old whole-object observation.
    @State private var service = LiveRecordingService()
    @StateObject private var camera = PhotoCaptureService()
    @Environment(\.dismiss) private var dismiss

    var onSaved: (UUID) -> Void = { _ in }
    /// When set, Stop APPENDS the new clip to this existing memo (memo detail →
    /// "Add recording") instead of creating a new one. `onSaved` then fires with
    /// the same id so the caller stays on that memo.
    var appendTo: UUID? = nil
    private let saver = MemoSaver()

    @State private var showCamera = false
    @State private var emptyRecording = false
    /// Context captured when the recorder opens — shown as ready-state chips and
    /// reused at save (so we don't capture location/weather twice).
    @State private var context: MemoMetadata?
    @ObservedObject private var modelStatus = ModelLoadStatus.shared
    @ObservedObject private var intentBridge = RecordingIntentBridge.shared
    @State private var autoStarted = false
    /// Instant record means the legacy "Ready to record" screen no longer greets
    /// you — it FLASHED for the few hundred ms before the engine's first frames
    /// and read as a broken state (logged 2026-06-11). While the auto-start is in
    /// flight a quiet placeholder shows instead; the manual ready screen remains
    /// only as the retry surface after an empty stop, or the fallback when the
    /// auto-start retry loop gives up (~5 s: no mic permission, contended session).
    @State private var showManualReady = false
    /// Photo markers to weave into the LIVE caption: each records the spoken-word
    /// count at the moment the shutter fired, so `[photo N]` lands inline near where
    /// you were speaking. Word counts shift as the caption re-transcribes, so the
    /// renderer clamps each marker to the current word count (never crashes / never
    /// reorders). Cleared on start.
    @State private var photoMarks: [PhotoMark] = []
    /// Live captioning on/off — the same persisted preference as Settings →
    /// "Live transcription". The record-screen toggle flips it for the current
    /// recording AND remembers it (sticky), so a run of long battery-saving
    /// recordings doesn't need re-toggling each time. The engine reads this at
    /// `start()`; the toggle also applies it mid-recording via `setLiveTranscription`.
    @AppStorage("liveTranscription") private var liveTranscription = true
    // (The live-caption auto-off — Settings → Recording, default 1 min — is
    // owned by the service's own clock now: watching `service.elapsed` from a
    // view `.onChange` re-rendered the whole screen every tick.)

    private struct PhotoMark: Equatable { let wordIndex: Int; let anchor: [String]; let number: Int }

    var body: some View {
        ZStack {
            Color.skBg.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                if service.isRecording {
                    recordingContent
                } else if showManualReady {
                    readyContent
                } else {
                    startingContent
                }
            }

            if showCamera {
                cameraOverlay
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(Theme.Motion.spring, value: showCamera)
        .onAppear {
            // The camera session starts when the camera sheet opens (see the
            // Photo button), not here — an eagerly-running AVCaptureSession
            // heated the phone for the whole recording even when never used.
            startIfActive()
        }
        // Cold launch (Record intent / Siri / widget): the auto-start MUST wait
        // until the app is foreground-`.active` — iOS blocks mic capture before
        // then, so firing in onAppear/.task (scene still `.inactive`) silently
        // no-ops. `didBecomeActiveNotification` is the reliable signal on cold
        // launch (and avoids scenePhase not propagating into a fullScreenCover).
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            startIfActive()
        }
        .onDisappear { camera.stop() }
        .alert("Nothing recorded", isPresented: $emptyRecording) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("That recording captured no audio — check that Skrift has microphone access, and hold the recording a moment before stopping.")
        }
        .onChange(of: intentBridge.stopRequestID) {
            if service.isRecording { stopTapped() }
        }
        // A recording ended but we're still on this screen (the empty-capture
        // retry case) → from here on the manual ready screen is the idle state.
        .onChange(of: service.isRecording) { was, now in
            if was, !now {
                showManualReady = true
                // Restore the sticky preference after a transient auto-off, so the
                // ready screen + next recording reflect the user's real choice.
                service.setLiveTranscription(liveTranscription)
            }
        }
        // A photo was captured mid-record → drop a `[photo N]` marker into the live
        // caption at the current spoken-word position (the count badge still updates
        // separately). New markers only — never re-add when the count drops to 0 on save.
        .onChange(of: camera.capturedCount) { old, new in
            guard new > old, service.isRecording else { return }
            // Anchor the mark to the words it follows (last ≤3) — the live chunk
            // re-transcribes wholesale, so a bare index drifts; the anchor words
            // move with the rewrite and re-locate the mark at render.
            let captionWords = service.liveCaption
                .split(whereSeparator: { $0.isWhitespace }).map(String.init)
            photoMarks.append(PhotoMark(wordIndex: captionWords.count,
                                        anchor: Array(captionWords.suffix(3)),
                                        number: new))
        }
        .animation(Theme.Motion.snappy, value: service.routeNotice)
        .task {
            // Preload the model FIRST — it's the caption's critical path, and it
            // used to wait behind the GPS fix below. Skipped in the mock/sim
            // path (no ANE, no download).
            if LaunchFlags.seedTranscript == nil {
                Task { try? await TranscriptionService.shared.ensureLoaded() }
            }
            // The context capture (GPS fix + reverse-geocode + weather fetch +
            // pedometer) is save-time data, not start-time: give the engine and
            // model the first seconds of an older phone's CPU. If the user
            // stops before this lands, MemoSaver captures at save instead.
            try? await Task.sleep(for: .seconds(2))
            context = await MetadataProviderFactory.make().capture()
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack {
            Button(action: closeTapped) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.skTextDim)
                    .frame(width: 32, height: 32)
                    .background(Color.skSurface, in: .circle)
                    .overlay(Circle().stroke(Color.skBorder, lineWidth: 1))
            }
            .accessibilityIdentifier("cancel-record")

            Spacer()
            // Live-transcription toggle (the device-requested "turn off live
            // transcription for a long, battery-saving recording" affordance).
            // Sticky via @AppStorage; applies mid-recording too.
            Button(action: toggleLiveTranscription) {
                // `text.bubble.fill` (on) / `text.bubble` (off) — both are valid
                // SF Symbols on every iOS; state is shown by fill + colour, NOT a
                // `.slash` variant (captions.bubble.slash doesn't exist on iOS 26,
                // so it rendered as an EMPTY button — device-reported 2026-06-17).
                // Reflect the EFFECTIVE live state (`service.liveTranscription`), so it
                // shows "off" the moment the auto-off timer fires, not just the pref.
                Image(systemName: service.liveTranscription ? "text.bubble.fill" : "text.bubble")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(service.liveTranscription ? Color.skAccent : Color.skTextDim)
                    .frame(width: 32, height: 32)
                    .background(Color.skSurface, in: .circle)
                    .overlay(Circle().stroke(Color.skBorder, lineWidth: 1))
            }
            .accessibilityIdentifier("live-transcription-toggle")
            .accessibilityLabel(service.liveTranscription ? "Live transcription on" : "Live transcription off")
        }
        .padding(.horizontal, Theme.Space.margin)
        .padding(.top, 8)
    }

    /// Flip live captioning for this recording (and remember it). When recording,
    /// `setLiveTranscription` tears the live stream down / brings it up; otherwise
    /// the engine picks up the new value at `start()`.
    private func toggleLiveTranscription() {
        // Flip from the EFFECTIVE state (so a tap after the auto-off turns captions
        // back ON), update the sticky preference, and apply to the live stream.
        let newOn = !service.liveTranscription
        liveTranscription = newOn
        service.setLiveTranscription(newOn)
    }

    // MARK: - Starting (instant record in flight)

    /// The moment between the screen appearing and the engine's first frames —
    /// usually a few hundred ms. Deliberately quiet (no mic button, no
    /// "Recording" claim): the live caption pops in when the tap goes live.
    private var startingContent: some View {
        VStack(spacing: 12) {
            Spacer()
            ProgressView()
                .tint(Color.skTextDim)
            Text("Starting…")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.skTextDim)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("record-starting")
    }

    // MARK: - Ready (mockup4 — manual retry surface only)

    private var readyContent: some View {
        VStack(spacing: 0) {
            Spacer()
            Image(systemName: "waveform")
                .font(.system(size: 40, weight: .regular))
                .foregroundStyle(Color.skTextFaint)
            Text("Ready to record")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.skText)
                .padding(.top, 14)
            HStack(spacing: 6) {
                Circle().fill(statusColor).frame(width: 7, height: 7)
                Text(statusText)
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color.skTextDim)
            .padding(.top, 8)

            if !contextChips.isEmpty {
                FlowLayout(spacing: 6, lineSpacing: 6) {
                    ForEach(contextChips) { chip in
                        ContextChip(text: chip.text, systemImage: chip.symbol)
                    }
                }
                .padding(.top, 16)
                .padding(.horizontal, 24)
            }

            Spacer()

            Button(action: startTapped) {
                ZStack {
                    Circle().stroke(Color.skRed.opacity(0.35), lineWidth: 4).frame(width: 84, height: 84)
                    Circle().fill(Color.skRed).frame(width: 68, height: 68)
                    Image(systemName: "mic.fill").font(.system(size: 26)).foregroundStyle(.white)
                }
            }
            .accessibilityIdentifier("record-button")
            .accessibilityLabel("Start recording")

            Text("Tap to start recording")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.skTextDim)
                .padding(.top, 14)
                .padding(.bottom, 40)
        }
        .padding(.horizontal, Theme.Space.margin)
    }

    // MARK: - Recording (mockup5)

    private var recordingContent: some View {
        VStack(spacing: 0) {
            HStack(spacing: 7) {
                Circle().fill(Color.skRed).frame(width: 9, height: 9).shadow(color: .skRed, radius: 5)
                Text(service.isPaused ? "Paused" : "Recording")
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Color.skTextDim)
            .padding(.top, 18)

            if service.liveTranscription {
                LiveCaptionPane(
                    service: service,
                    marks: photoMarks.map {
                        LiveCaptionLayout.Mark(wordIndex: $0.wordIndex, number: $0.number, anchor: $0.anchor)
                    },
                    modelLoading: !modelStatus.ready && modelStatus.phase != .failed
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.top, 18)
                .accessibilityIdentifier("live-caption")
            } else {
                liveOffPlaceholder
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.top, 18)
            }

            if let notice = service.routeNotice {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11, weight: .semibold))
                    Text(notice)
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(Color.skAmber)
                .padding(.horizontal, 11).padding(.vertical, 6)
                .background(Color.skAmber.opacity(0.12), in: .capsule)
                .padding(.top, 8)
                .transition(.opacity)
                .accessibilityIdentifier("route-notice")
            }

            WaveformTimerRow(service: service)
                .padding(.top, 6)

            controls
                .padding(.top, 22)
                .padding(.bottom, 30)
        }
        .padding(.horizontal, Theme.Space.margin)
    }

    /// Shown in place of the live caption when live transcription is off — makes
    /// the battery-saving mode legible (it's not broken; it transcribes on stop).
    private var liveOffPlaceholder: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "text.bubble")
                .font(.system(size: 34, weight: .regular))
                .foregroundStyle(Color.skTextFaint)
            Text("Live transcription off")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.skText)
            Text("Saving battery — this recording is transcribed when you stop.")
                .font(.system(size: 13))
                .foregroundStyle(Color.skTextDim)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
        .accessibilityIdentifier("live-caption-off")
    }

    private var controls: some View {
        HStack {
            Spacer()
            ControlButton(
                title: service.isPaused ? "Resume" : "Pause",
                systemImage: service.isPaused ? "play.fill" : "pause.fill",
                id: "pause-button",
                action: togglePause
            )

            Spacer()
            Button(action: stopTapped) {
                ZStack {
                    Circle().stroke(Color.skRed.opacity(0.35), lineWidth: 4).frame(width: 74, height: 74)
                    RoundedRectangle.sk(8).fill(Color.skRed).frame(width: 28, height: 28)
                }
            }
            .accessibilityIdentifier("record-button")
            .accessibilityLabel("Stop recording")

            Spacer()
            ControlButton(title: "Photo", systemImage: "camera.fill", accent: true, id: "photo-button") {
                camera.configure()   // spin the session up now — first open shows the preview in ~½ s
                showCamera = true
            }
            .overlay(alignment: .topTrailing) {
                if camera.capturedCount > 0 {
                    Text("\(camera.capturedCount)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 19, height: 19)
                        .background(Color.skAccent, in: .circle)
                        .overlay(Circle().stroke(Color.skBg, lineWidth: 2))
                        .offset(x: -4, y: -2)
                        .accessibilityIdentifier("photo-count")
                }
            }
            Spacer()
        }
    }

    // MARK: - Camera overlay (mockup5 middle)

    private var cameraOverlay: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.55).ignoresSafeArea()
                .onTapGesture {}   // swallow taps to the recording layer

            VStack {
                RecordingTimeHeader(service: service)
                    .padding(.top, 54)
                Spacer()
            }

            CameraSheet(
                camera: camera,
                // A closure, not `service.elapsed`: passing the value would make
                // this whole overlay re-render at every timer tick just to keep a
                // capture offset fresh; the sheet reads it at shutter time instead.
                recordingOffset: { service.elapsed },
                onDone: {
                    showCamera = false
                    camera.stop()   // camera off between uses; reopening restarts it
                }
            )
        }
    }

    // MARK: - Model status (live)

    private var statusText: String {
        switch modelStatus.phase {
        case .downloading(let p): return "Downloading model · \(Int(p * 100))%"
        case .preparing(let p?):  return "Preparing model · \(Int(p * 100))%"
        case .preparing(nil):     return "Preparing model…"
        case .ready:              return "On-device transcription · ready"
        case .failed:             return "Couldn’t load model"
        case .idle:
            // Once cached, never claim "not downloaded" — the preload is bringing
            // it back from disk (a fast reload, not a re-download).
            return modelStatus.everDownloaded ? "Preparing model…" : "Transcription model not downloaded"
        }
    }

    private var statusColor: Color {
        switch modelStatus.phase {
        case .ready:  return .skGreen
        case .failed: return .skRed
        default:      return .skAmber
        }
    }

    // MARK: - Context chips

    private struct Chip: Identifiable { let id = UUID(); let text: String; let symbol: String? }

    private var contextChips: [Chip] {
        var out: [Chip] = []
        if let place = context?.location?.placeName, !place.isEmpty {
            out.append(Chip(text: place, symbol: "mappin.circle.fill"))
        }
        if let w = context?.weather { out.append(Chip(text: "\(w.temperature)°", symbol: "cloud.sun.fill")) }
        if let period = context?.dayPeriod { out.append(Chip(text: period.label, symbol: period.symbol)) }
        return out
    }

    // MARK: - Actions

    private func closeTapped() {
        if service.isRecording { service.cancel(); camera.discardAll() }
        dismiss()
    }

    /// INSTANT RECORD: every way into this screen — FAB, memo-detail "+" append,
    /// Record intent / Siri / widget — starts recording the moment the screen is
    /// up (no second tap on a "ready" screen; the model keeps loading in the
    /// background and the caption catches up). Hard-won on-device rules, shared
    /// with the old intent-only auto-start:
    /// 1. Gate on foreground-`.active` FIRST — iOS blocks mic capture before then
    ///    (so a cold Siri launch waits for `didBecomeActiveNotification`).
    /// 2. Read the pending-intent flag from the live bridge singleton (set at
    ///    intent time) — a param passed through the fullScreenCover arrived stale
    ///    on cold launch. A pending intent means Siri may still own the audio
    ///    session, so that path gets a grace delay before contending for the mic.
    /// 3. NO haptic here — haptics share the audio session, and right after a Siri
    ///    launch Siri still owns it, so a haptic blocks the main actor and the
    ///    start Task never runs.
    /// The retry loop itself lives in `LiveRecordingService.startRetrying`, owned
    /// by the service so a dismissed recorder can't ghost-start a recording.
    private func startIfActive() {
        guard !autoStarted, !service.isRecording,
              UIApplication.shared.applicationState == .active else { return }
        let viaIntent = intentBridge.consumePendingStart()
        autoStarted = true
        photoMarks = []
        service.startRetrying(siriGrace: viaIntent)
        // If the retry loop gives up (~5 s: Siri grace 700 ms + 16×300 ms — no mic
        // permission, contended session), surface the manual ready screen rather
        // than sitting on the starting placeholder forever. Recording-in-progress
        // always wins over this flag in the body, so a late success self-heals.
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(7))
            if !service.isRecording { showManualReady = true }
        }
    }

    /// Manual start — only reachable after an auto-started recording was stopped
    /// as empty (the recorder stays up on the ready screen for a retry).
    private func startTapped() {
        Haptics.tap()
        photoMarks = []
        try? service.start()
    }

    private func stopTapped() {
        Haptics.recordingTap()
        guard let result = service.stop() else { dismiss(); return }
        // Empty capture (no audio frames — fast start→stop, or an unavailable
        // mic/session): discard it and tell the user instead of saving a silent,
        // blank note. Stay on the recorder so they can retry.
        guard result.duration >= 0.4 else {
            try? FileManager.default.removeItem(at: result.url)
            emptyRecording = true
            return
        }
        // Append mode: fold the new clip into an existing memo, stay on it.
        if let appendTo {
            saver.appendRecording(to: appendTo, tempURL: result.url,
                                  duration: result.duration, liveCaption: result.liveCaption)
            Haptics.success()
            onSaved(appendTo)
            dismiss()
            return
        }
        let id = saver.save(
            tempURL: result.url,
            duration: result.duration,
            photos: camera.takeAll(),
            provisionalTranscript: result.liveCaption,
            capturedMetadata: context
        )
        Haptics.success()
        // Set the navigation target before dismissing the cover — pushing onto
        // the stack from a closure fired *during* dismissal can no-op.
        onSaved(id)
        dismiss()
    }

    private func togglePause() {
        Haptics.recordingTap()
        service.isPaused ? service.resume() : service.pause()
    }
}

// MARK: - Pieces

/// m:ss for the record timer (shared by the waveform row + camera header).
private enum RecordClock {
    static func string(_ elapsed: TimeInterval) -> String {
        let total = Int(elapsed)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// Reads the hot caption state (`liveCaption` + committed count, ~1.7 Hz) in
/// its OWN body so caption updates re-render only this pane — the shell above
/// re-renders on rare state changes only.
private struct LiveCaptionPane: View {
    let service: LiveRecordingService
    let marks: [LiveCaptionLayout.Mark]
    let modelLoading: Bool

    var body: some View {
        LiveCaption(
            text: service.liveCaption,
            photoMarks: marks,
            solidWordCount: service.liveCommittedWordCount,
            modelLoading: modelLoading
        )
    }
}

/// Reads the hot meter state (waveform ~10 Hz, elapsed 4 Hz) in its own body.
private struct WaveformTimerRow: View {
    let service: LiveRecordingService

    var body: some View {
        HStack(spacing: 14) {
            RecordWaveform(samples: service.waveform)
                .frame(height: 52)
            Text(RecordClock.string(service.elapsed))
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.skTextDim)
                .accessibilityIdentifier("record-timer")
        }
    }
}

/// The "Recording · 0:42 — still listening" strip over the camera — isolates
/// the 4 Hz elapsed read from the camera overlay.
private struct RecordingTimeHeader: View {
    let service: LiveRecordingService

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(Color.skRed).frame(width: 9, height: 9).shadow(color: .skRed, radius: 5)
            Text("Recording · \(RecordClock.string(service.elapsed))")
            Text("— still listening").foregroundStyle(Color.skTextFaint)
        }
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(Color.skTextDim)
    }
}

/// Live transcript, scrollable. The solid body = words in COMMITTED (rotated)
/// chunks, which never re-transcribe — a real finalized signal, not the old
/// trailing-N-words approximation that visibly lied (solid words still changed,
/// 2026-06-10 device finding). Everything in the current live chunk renders
/// lighter until its rotation locks it in. Photos captured mid-record appear as
/// tinted `[photo N]` tokens inline. While the model is still loading and
/// nothing has been transcribed yet, a placeholder stands in (recording is
/// already capturing audio — the caption just catches up once the model is ready).
///
/// Auto-scroll (F2): sticks to the newest text as words append, but if the user
/// scrolls up to re-read, auto-stick pauses until they scroll back to the bottom.
private struct LiveCaption: View {
    let text: String
    /// Markers to splice in — anchored to the words they followed at capture.
    var photoMarks: [LiveCaptionLayout.Mark] = []
    /// How many leading words are FINAL (committed chunks) — render solid.
    var solidWordCount: Int = 0
    var modelLoading = false

    var body: some View {
        ScrollView(.vertical) {
            Group {
                if words.isEmpty && modelLoading {
                    Text("Model loading — your words appear once it’s ready")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color.skTextFaint)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("caption-loading")
                } else {
                    // ONE Text over ONE AttributedString — constant view depth no
                    // matter how long the recording runs. (The previous per-word
                    // `Text + Text` chain made SwiftUI resolve thousands of nested
                    // concatenations recursively → stack overflow / SIGSEGV in
                    // ConcatenatedTextStorage.resolve on long recordings.)
                    Text(caption)
                        .font(.system(size: 22, weight: .medium))
                        .lineSpacing(5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .scrollIndicators(.automatic)
        // Auto-stick to the newest text as words append: `.bottom` keeps the
        // content pinned to the bottom edge as it grows. Scrolling up to re-read is
        // free; scrolling back to the bottom re-engages the stick — exactly the
        // read-back behaviour F2 asks for, natively (no manual scroll tracking).
        .defaultScrollAnchor(.bottom)
    }

    private var words: [String] { text.split(whereSeparator: { $0.isWhitespace }).map(String.init) }

    /// The styled caption as a SINGLE AttributedString: solid finalized body +
    /// lighter trailing (volatile) words + inline tinted `[photo N]` tokens at
    /// their captured word positions + the accent caret. The run layout comes
    /// from `LiveCaptionLayout.segments` (pure + unit-tested); this just maps
    /// each segment style to its colour/font.
    private var caption: AttributedString {
        var out = AttributedString()
        let segments = LiveCaptionLayout.segments(
            words: words, photoMarks: photoMarks,
            firstVolatile: min(max(0, solidWordCount), words.count)
        )
        for segment in segments {
            var run = AttributedString(segment.text)
            switch segment.style {
            case .solid:
                run.foregroundColor = .skText
            case .volatile:
                run.foregroundColor = .skTextDim
            case .photo:
                // Distinct accent + size so it reads as a non-spoken annotation,
                // not transcript text.
                run.foregroundColor = .skAccentText
                run.font = .system(size: 18, weight: .semibold)
            }
            out.append(run)
        }
        var caret = AttributedString("▏")
        caret.foregroundColor = .skAccent
        out.append(caret)
        return out
    }
}

/// Pure layout maths for the live caption — extracted so the volatile-word boundary
/// (F3), the photo-marker clamping (F4), and the style-run flattening are
/// unit-testable without a view. Stale photo word-indices (the caption
/// re-transcribes wholesale, so counts drift) are clamped into range here, never
/// overshooting the current word count.
enum LiveCaptionLayout {
    /// How one run of caption text renders: solid finalized body, lighter trailing
    /// (volatile) words, or a tinted `[photo N]` annotation token.
    enum Style: Equatable { case solid, volatile, photo }

    /// One styled run of the caption. Adjacent words of the same style coalesce
    /// into a single segment, so a long recording stays a handful of runs.
    struct Segment: Equatable {
        let text: String
        let style: Style
    }

    /// A `[photo N]` marker captured mid-recording: the caption word count at
    /// capture + the last few caption words it followed (its ANCHOR). The live
    /// caption re-transcribes its current chunk wholesale, so the absolute index
    /// can drift — the anchor words move WITH a rewrite and re-locate the mark.
    struct Mark: Equatable {
        let wordIndex: Int
        let number: Int
        var anchor: [String] = []
    }

    /// Photo markers grouped by the word index they follow (0 = before the first
    /// word, `wordCount` = after the last). Anchored marks re-locate to their
    /// anchor words; the rest clamp into `0...wordCount`.
    static func marksByIndex(_ marks: [Mark], words: [String]) -> [Int: [Int]] {
        var out: [Int: [Int]] = [:]
        for mark in marks {
            out[resolvedIndex(of: mark, in: words), default: []].append(mark.number)
        }
        return out
    }

    /// Where a mark sits in the CURRENT caption: find its anchor word sequence
    /// (normalised — re-transcription adds punctuation/casing) nearest the
    /// captured index, within a ±12-word window; fall back to the clamped index
    /// when the anchor was rewritten away.
    static func resolvedIndex(of mark: Mark, in words: [String]) -> Int {
        let clamped = min(max(0, mark.wordIndex), words.count)
        let anchor = mark.anchor.map(normalise)
        let span = anchor.count
        guard span > 0, words.count >= span else { return clamped }
        let normalised = words.map(normalise)
        let candidates = (span...words.count).sorted { abs($0 - clamped) < abs($1 - clamped) }
        for end in candidates where abs(end - clamped) <= 12 {
            if Array(normalised[(end - span)..<end]) == anchor { return end }
        }
        return clamped
    }

    private static func normalise(_ word: String) -> String {
        word.lowercased().trimmingCharacters(in: .punctuationCharacters)
    }

    /// Flatten the caption into style runs: words (each with a trailing space)
    /// coalesced per style, with `[photo N]` tokens spliced in at their clamped
    /// word positions. The view renders these as AttributedString runs inside ONE
    /// `Text`, keeping the view depth CONSTANT regardless of recording length —
    /// the per-word `Text + Text` chain this replaces overflowed the stack
    /// (SwiftUI resolves concatenated Text recursively) on long recordings.
    static func segments(words: [String],
                         photoMarks: [Mark],
                         firstVolatile: Int) -> [Segment] {
        let firstVolatile = min(max(0, firstVolatile), words.count)
        let marks = marksByIndex(photoMarks, words: words)

        var out: [Segment] = []
        func appendWord(_ text: String, style: Style) {
            if let last = out.last, last.style == style {
                out[out.count - 1] = Segment(text: last.text + text, style: style)
            } else {
                out.append(Segment(text: text, style: style))
            }
        }
        func appendMarks(at index: Int) {
            for number in marks[index] ?? [] {
                out.append(Segment(text: "[photo \(number)] ", style: .photo))
            }
        }

        appendMarks(at: 0)   // markers anchored before the first word
        for (i, word) in words.enumerated() {
            appendWord(word + " ", style: i < firstVolatile ? .solid : .volatile)
            appendMarks(at: i + 1)
        }
        return out
    }
}

/// Compact live waveform: centered rounded bars with an accent gradient, driven
/// by the rolling level history. (Custom view for pixel-fidelity to the mock;
/// DSWaveformImage powers the static playback scrubber in Memo detail.)
struct RecordWaveform: View {
    let samples: [Float]
    private let barCount = 40

    var body: some View {
        GeometryReader { geo in
            let bars = padded
            HStack(alignment: .center, spacing: 3) {
                ForEach(bars.indices, id: \.self) { i in
                    Capsule()
                        .fill(LinearGradient(colors: [.skAccent, Color(hex: 0xa99cff)],
                                             startPoint: .bottom, endPoint: .top))
                        .frame(height: max(3, CGFloat(bars[i]) * geo.size.height))
                        .opacity(0.45 + Double(bars[i]) * 0.55)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .animation(.easeOut(duration: 0.08), value: samples)
        }
        .accessibilityHidden(true)
    }

    /// Right-align the newest samples; pad the left with quiet bars.
    private var padded: [Float] {
        if samples.count >= barCount { return Array(samples.suffix(barCount)) }
        return Array(repeating: 0.04, count: barCount - samples.count) + samples
    }
}

/// A round secondary control with a label below (Pause/Photo). The
/// accessibility id sits on the `Button` itself so XCUITest can find it.
private struct ControlButton: View {
    let title: String
    let systemImage: String
    var accent = false
    let id: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                ZStack {
                    Circle()
                        .fill(accent ? Color.skAccentSoft : Color.skSurface)
                        .frame(width: 54, height: 54)
                    Circle().stroke(accent ? Color.skAccent.opacity(0.3) : Color.skBorder, lineWidth: 1)
                        .frame(width: 54, height: 54)
                    Image(systemName: systemImage)
                        .font(.system(size: 20))
                        .foregroundStyle(accent ? Color.skAccentText : Color.skText)
                }
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.skTextDim)
            }
        }
        .accessibilityIdentifier(id)
    }
}
