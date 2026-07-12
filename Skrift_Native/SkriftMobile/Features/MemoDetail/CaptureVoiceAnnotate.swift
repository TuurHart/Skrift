import SwiftUI

/// Track B (wave-2 mock m4): voice-annotate a CAPTURE in-app. The share sheet
/// can't record (iOS entitlement-blocks extension mics — device-proven builds
/// 60–62), so the ramble happens HERE, after the jump-open: idle = the mic
/// pill; recording = an inline strip with the live caption (the exact recorder
/// engine, no new audio code); stop = the words transcribe on-device and
/// append below the typed ramble, then the pill demotes to "Add another".
///
/// The AUDIO is consumed after transcription (the shipped capture-dictation
/// model). Keeping it attached as playable memo audio flips the Mac's
/// capture-ingest discriminator (capture = memo WITHOUT audio) — that half
/// waits for the Mac counterpart (ledgered, backlog Wave-2 round 3).
struct CaptureVoiceAnnotate: View {
    let memo: Memo
    let repository: NotesRepository

    @State private var service = LiveRecordingService()
    @State private var transcribing = false
    @State private var addedThisSession = false
    @State private var micUnavailable = false

    var body: some View {
        Group {
            if service.isRecording {
                recordingStrip
            } else if transcribing {
                transcribingStrip
            } else {
                idlePill
            }
        }
        .animation(Theme.Motion.snappy, value: service.isRecording)
        .animation(Theme.Motion.snappy, value: transcribing)
    }

    // MARK: - Idle (the pill)

    private var idlePill: some View {
        VStack(spacing: 6) {
            Button {
                startTapped()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 12, weight: .semibold))
                    Text(addedThisSession ? "Add another" : "Add a voice note")
                        .font(.system(size: 13.5, weight: .bold))
                }
                .foregroundStyle(addedThisSession ? Color.skTextDim : .white)
                .padding(.horizontal, 20)
                .padding(.vertical, 11)
                .background(
                    addedThisSession ? AnyShapeStyle(Color.skSurface) : AnyShapeStyle(Color.skAccent),
                    in: .capsule
                )
                .overlay(Capsule().strokeBorder(
                    addedThisSession ? Color.skBorder : .clear, lineWidth: 1))
                .shadow(color: addedThisSession ? .clear : Color.skAccent.opacity(0.4),
                        radius: 9, y: 3)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("capture-voice-annotate")

            if micUnavailable {
                Text("The microphone isn't available right now")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.skTextFaint)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Recording (inline strip, mock m4 state 2)

    private var recordingStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 9) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 9, height: 9)
                    .opacity(blink ? 0.35 : 1)
                    .animation(.easeInOut(duration: 0.6).repeatForever(), value: blink)
                    .onAppear { blink = true }
                Text("Recording")
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundStyle(Color.skText)
                Spacer(minLength: 6)
                Text(clock(service.elapsed))
                    .font(.system(size: 12.5).monospacedDigit())
                    .foregroundStyle(Color.skTextDim)
                Button {
                    stopTapped()
                } label: {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.red)
                        .frame(width: 30, height: 30)
                        .background(Color.red.opacity(0.16), in: .circle)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("capture-voice-stop")
            }
            // The live caption streaming — same engine as the recorder.
            Text(service.liveCaption.isEmpty ? "Listening…" : service.liveCaption)
                .font(.system(size: 13))
                .foregroundStyle(service.liveCaption.isEmpty ? Color.skTextFaint : Color.skTextDim)
                .lineLimit(2)
                .frame(maxWidth: .infinity, minHeight: 34, alignment: .bottomLeading)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .background(Color.skSurface, in: .rect(cornerRadius: 15, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .strokeBorder(Color.skAccent.opacity(0.4), lineWidth: 1)
        )
        .accessibilityIdentifier("capture-voice-recording")
    }

    @State private var blink = false

    private var transcribingStrip: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("Transcribing your voice note…")
                .font(.system(size: 13))
                .foregroundStyle(Color.skTextDim)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 11)
    }

    // MARK: - Actions

    private func startTapped() {
        // The main recorder owns the session when it's live — don't fight it.
        guard !LiveRecordingService.isRecordingActive else { return }
        micUnavailable = false
        Haptics.tap()
        do { try service.start() } catch { micUnavailable = true }
    }

    private func stopTapped() {
        Haptics.recordingTap()
        guard let result = service.stop() else { return }
        guard result.duration >= 0.4 else {
            try? FileManager.default.removeItem(at: result.url)
            return
        }
        transcribing = true
        Task { @MainActor in
            var text = result.liveCaption.trimmingCharacters(in: .whitespacesAndNewlines)
            // Full-quality pass over the clip; the live caption is the fallback.
            if let r = try? await TranscriberFactory.make().transcribe(audioURL: result.url,
                                                                       imageManifest: []) {
                let t = r.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty { text = t }
            }
            if !text.isEmpty {
                let existing = memo.annotationText ?? ""
                memo.annotationText = existing.isEmpty ? text : existing + "\n\n" + text
                memo.markEdited()
                repository.save()
            }
            try? FileManager.default.removeItem(at: result.url)   // dictation model: text stays, audio goes
            transcribing = false
            addedThisSession = true
            Haptics.success()
        }
    }

    private func clock(_ t: TimeInterval) -> String {
        let s = Int(t)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
