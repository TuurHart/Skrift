import SwiftUI
import UIKit

/// Caption-first record screen (mockup4 ready · mockup5 recording + camera).
/// The live transcript is the hero; the waveform/timer are compact; the camera
/// is on-demand (a sheet that slides up while recording keeps running). On stop
/// the memo is persisted immediately and `onSaved` fires with its id so the
/// caller can open it in Memo detail (the save-now post-record flow).
struct RecordView: View {
    @StateObject private var service = LiveRecordingService()
    @StateObject private var camera = PhotoCaptureService()
    @Environment(\.dismiss) private var dismiss

    var onSaved: (UUID) -> Void = { _ in }
    /// When set, Stop APPENDS the new clip to this existing memo (memo detail →
    /// "Add recording") instead of creating a new one. `onSaved` then fires with
    /// the same id so the caller stays on that memo.
    var appendTo: UUID? = nil
    private let saver = MemoSaver()

    // Same key MemoSaver reads, so toggling it here actually enables conversation-mode
    // diarization for the recording (it was a dead local @State before).
    @AppStorage("conversationDefault") private var conversation = false
    @State private var showCamera = false
    @State private var emptyRecording = false
    /// Context captured when the recorder opens — shown as ready-state chips and
    /// reused at save (so we don't capture location/weather twice).
    @State private var context: MemoMetadata?
    @ObservedObject private var modelStatus = ModelLoadStatus.shared
    @ObservedObject private var intentBridge = RecordingIntentBridge.shared
    @State private var autoStarted = false

    var body: some View {
        ZStack {
            Color.skBg.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                if service.isRecording {
                    recordingContent
                } else {
                    readyContent
                }
            }

            if showCamera {
                cameraOverlay
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(Theme.Motion.spring, value: showCamera)
        .onAppear {
            camera.configure()
            autoStartIfActive()
        }
        // Cold launch (Record intent / Siri / widget): the auto-start MUST wait
        // until the app is foreground-`.active` — iOS blocks mic capture before
        // then, so firing in onAppear/.task (scene still `.inactive`) silently
        // no-ops. `didBecomeActiveNotification` is the reliable signal on cold
        // launch (and avoids scenePhase not propagating into a fullScreenCover).
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            autoStartIfActive()
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
        .task {
            context = await MetadataProviderFactory.make().capture()
            // Preload the model on the ready screen so the status goes live
            // (downloading → ready) before recording, and the first record isn't
            // a cold start. Skipped in the mock/sim path (no ANE, no download).
            if LaunchFlags.seedTranscript == nil {
                Task { try? await TranscriptionService.shared.ensureLoaded() }
            }
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

            Button { conversation.toggle() } label: {
                HStack(spacing: 8) {
                    Text("Conversation")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.skText)
                    ToggleDot(on: conversation)
                }
                .padding(.leading, 12).padding(.trailing, 6).padding(.vertical, 6)
                .background(Color.skSurface, in: .capsule)
                .overlay(Capsule().stroke(Color.skBorder, lineWidth: 1))
            }
            .accessibilityIdentifier("conversation-toggle")
        }
        .padding(.horizontal, Theme.Space.margin)
        .padding(.top, 8)
    }

    // MARK: - Ready (mockup4)

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

            LiveCaption(text: service.liveCaption)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.top, 18)
                .accessibilityIdentifier("live-caption")

            HStack(spacing: 14) {
                RecordWaveform(samples: service.waveform)
                    .frame(height: 52)
                Text(timeString)
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.skTextDim)
                    .accessibilityIdentifier("record-timer")
            }
            .padding(.top, 6)

            controls
                .padding(.top, 22)
                .padding(.bottom, 30)
        }
        .padding(.horizontal, Theme.Space.margin)
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
                HStack(spacing: 8) {
                    Circle().fill(Color.skRed).frame(width: 9, height: 9).shadow(color: .skRed, radius: 5)
                    Text("Recording · \(timeString)")
                    Text("— still listening").foregroundStyle(Color.skTextFaint)
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.skTextDim)
                .padding(.top, 54)
                Spacer()
            }

            CameraSheet(
                camera: camera,
                elapsed: service.elapsed,
                onDone: { showCamera = false }
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

    private var timeString: String {
        let total = Int(service.elapsed)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private func closeTapped() {
        if service.isRecording { service.cancel(); camera.discardAll() }
        dismiss()
    }

    /// Auto-start for a Record intent / Siri / widget cold launch — only once the
    /// app is foreground-`.active` (iOS blocks mic capture before then). Retries
    /// briefly because Siri may still be releasing the audio session right after a
    /// voice launch. Recording is independent of the model; the live caption
    /// buffers + catches up once the model finishes loading.
    /// Auto-start for a Record intent / Siri / widget. Hard-won on-device fixes:
    /// 1. Gate on foreground-`.active` FIRST — iOS blocks mic capture before then
    ///    (don't consume the pending start while inactive or it's wasted).
    /// 2. Read the pending flag from the live bridge singleton (set at intent
    ///    time) — a param passed through the fullScreenCover arrived stale on cold
    ///    launch.
    /// 3. NO haptic here — haptics share the audio session, and right after a Siri
    ///    launch Siri still owns it, so a haptic blocks the main actor and the
    ///    start Task never runs.
    /// 4. Brief delay + retry: let Siri fully release the mic before we contend.
    /// Recording is independent of the model; the live caption catches up once the
    /// model loads.
    private func autoStartIfActive() {
        guard !autoStarted, !service.isRecording,
              UIApplication.shared.applicationState == .active else { return }
        guard intentBridge.consumePendingStart() else { return }
        autoStarted = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(700))
            for _ in 0..<16 {
                if service.isRecording { return }
                do { try service.start(); return }
                catch { try? await Task.sleep(for: .milliseconds(300)) }
            }
        }
    }

    private func startTapped() {
        Haptics.tap()
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

/// A small accent/elev pill toggle dot matching the mock's `.sw`.
private struct ToggleDot: View {
    let on: Bool
    var body: some View {
        Capsule()
            .fill(on ? Color.skAccent : Color.skElev)
            .frame(width: 38, height: 22)
            .overlay(
                Circle().fill(.white).frame(width: 18, height: 18)
                    .padding(2)
                    .frame(maxWidth: .infinity, alignment: on ? .trailing : .leading)
            )
            .animation(Theme.Motion.snappy, value: on)
    }
}

/// Live transcript with a three-tier fade (older → dim) + an accent caret, like
/// the mockup's `.old/.mid/.now`.
private struct LiveCaption: View {
    let text: String

    var body: some View {
        (oldText + midText + nowText + caret)
            .font(.system(size: 22, weight: .medium))
            .lineSpacing(5)
    }

    private var words: [String] { text.split(separator: " ").map(String.init) }

    private var oldText: Text {
        let w = words
        guard w.count > 18 else { return Text("") }
        return Text(w[0..<(w.count - 18)].joined(separator: " ") + " ").foregroundColor(.skTextFaint)
    }
    private var midText: Text {
        let w = words
        guard w.count > 6 else { return Text("") }
        let start = max(0, w.count - 18)
        return Text(w[start..<(w.count - 6)].joined(separator: " ") + " ").foregroundColor(.skTextDim)
    }
    private var nowText: Text {
        let w = words
        let start = max(0, w.count - 6)
        guard start < w.count else { return Text("") }
        return Text(w[start...].joined(separator: " ")).foregroundColor(.skText)
    }
    private var caret: Text {
        Text(" ▏").foregroundColor(.skAccent)
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
