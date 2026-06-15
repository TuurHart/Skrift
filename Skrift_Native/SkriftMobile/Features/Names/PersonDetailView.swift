import SwiftUI
import FluidAudio

/// A single person: avatar + name + voice-enrollment status + delete. Aliases are
/// NOT editable here (the Mac owns them; the phone syncs silently). Voice
/// enrollment runs on-device and ships with Conversation mode (the speaker-
/// embedding extraction is the later diarization track), so "Add voice" surfaces
/// that rather than faking an embedding into the synced DB.
struct PersonDetailView: View {
    let canonical: String
    let onChange: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var person: Person?
    @State private var showEnroll = false
    private let store = NamesStore.shared

    var body: some View {
        ZStack {
            Color.skBg.ignoresSafeArea()
            if let person {
                VStack(spacing: 0) {
                    Avatar(name: NamesDisplay.name(person), size: 84)
                        .padding(.top, 24)
                    Text(NamesDisplay.name(person))
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(Color.skText)
                        .padding(.top, 14)
                        .accessibilityIdentifier("person-detail-name")

                    voiceCard(person)
                        .padding(.top, 28)
                        .padding(.horizontal, Theme.Space.margin)

                    Spacer()

                    Button(role: .destructive, action: deletePerson) {
                        Label("Delete person", systemImage: "trash")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.skRed.opacity(0.14), in: .rect(cornerRadius: Theme.Radius.card, style: .continuous))
                            .foregroundStyle(Color.skRed)
                    }
                    .accessibilityIdentifier("delete-person-button")
                    .padding(.horizontal, Theme.Space.margin)
                    .padding(.bottom, 28)
                }
            } else {
                ProgressView()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: load)
        .sheet(isPresented: $showEnroll) {
            VoiceEnrollView(canonical: canonical,
                            displayName: person.map(NamesDisplay.name) ?? canonical) {
                load(); onChange()   // refresh the card → "Voice enrolled"
            }
        }
    }

    @ViewBuilder private func voiceCard(_ person: Person) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel("VOICE")
            if NamesDisplay.isEnrolled(person) {
                HStack(spacing: 8) {
                    VoiceBars()
                    Text("Voice enrolled")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.skGreen)
                    Spacer()
                }
                Text("Conversation mode can attribute speech to \(NamesDisplay.name(person)).")
                    .font(.footnote).foregroundStyle(Color.skTextDim)
            } else {
                Button { showEnroll = true } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "waveform")
                        Text("Add voice")
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.skTextFaint)
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.skAccent)
                }
                .accessibilityIdentifier("add-voice-button")
                Text("Enroll a short voice sample so Conversation mode can tell who's speaking.")
                    .font(.footnote).foregroundStyle(Color.skTextDim)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .skCard(padding: 16)
    }

    private func load() { person = store.livePeople().first { $0.canonical == canonical } }

    private func deletePerson() {
        store.delete(canonical: canonical)
        onChange()
        dismiss()
    }
}

/// Direct voice enrollment: record a short on-device sample of one person's voice,
/// embed it (wespeaker, 16 kHz mono), and store the voiceprint under their canonical
/// name — the SAME `VoiceEnroller.enroll` pipeline the conversation speaker-naming
/// path uses, so the print syncs to the Mac and Conversation mode can attribute
/// speech to them. Audio is captured to a temp WAV and discarded after embedding;
/// it never leaves the phone. (Was a "Got it" placeholder before 2026-06-15.)
struct VoiceEnrollView: View {
    /// The person's canonical name — the enrollment key (matches the synced person).
    let canonical: String
    /// Display name for the UI.
    var displayName: String = ""
    /// Called on a successful enroll (the detail card refreshes to "Voice enrolled").
    var onEnrolled: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @StateObject private var recorder = FeedbackRecorder()
    @State private var phase: Phase = .idle
    @State private var failure: String?

    private enum Phase { case idle, recording, enrolling, done }

    /// `SpeakerEmbedder.minSamples` is 32 000 (2 s @ 16 kHz); require a touch more so
    /// the embedding is stable (the spike showed unstable cosines under ~2 s).
    private let minSeconds: TimeInterval = 3

    private var canStop: Bool { recorder.elapsed >= minSeconds }
    private var name: String { displayName.isEmpty ? canonical : displayName }

    var body: some View {
        ZStack {
            Color.skBg.ignoresSafeArea()
            VStack(spacing: 16) {
                icon
                Text(title).font(.title3.weight(.bold)).foregroundStyle(Color.skText)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(failure == nil ? Color.skTextDim : Color.skRed)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
                actionButton
                if phase == .recording {
                    Text(String(format: "%.0fs", recorder.elapsed))
                        .font(.system(.title3, design: .monospaced))
                        .foregroundStyle(Color.skTextDim)
                        .accessibilityIdentifier("voice-enroll-timer")
                }
            }
            .padding(.top, 56)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .presentationDetents([.medium])
        .interactiveDismissDisabled(phase == .recording || phase == .enrolling)
        .onDisappear { if phase == .recording { recorder.discard() } }
    }

    private var icon: some View {
        Image(systemName: phase == .done ? "checkmark.circle.fill"
              : phase == .recording ? "waveform.circle.fill" : "mic.circle.fill")
            .font(.system(size: 56))
            .foregroundStyle(phase == .done ? Color.skGreen : Color.skAccent)
            .symbolEffect(.pulse, isActive: phase == .recording)
    }

    private var title: String {
        switch phase {
        case .idle:      return "Add \(name)'s voice"
        case .recording: return "Listening…"
        case .enrolling: return "Learning the voice…"
        case .done:      return "Voice learned"
        }
    }

    private var subtitle: String {
        if let failure { return failure }
        switch phase {
        case .idle:      return "Record a few seconds of \(name) talking so Conversation mode can tell who's speaking. It's processed on-device — your audio never leaves the phone."
        case .recording: return canStop ? "Good — tap to finish." : "Keep talking for a few seconds…"
        case .enrolling: return "Embedding the sample on-device."
        case .done:      return "Conversation mode can now attribute speech to \(name)."
        }
    }

    @ViewBuilder private var actionButton: some View {
        switch phase {
        case .idle:
            button("Start recording", systemImage: "mic.fill", id: "voice-enroll-record") { start() }
        case .recording:
            button("Stop & save", systemImage: "stop.fill", id: "voice-enroll-stop", enabled: canStop) { stopAndEnroll() }
        case .enrolling:
            HStack(spacing: 8) { ProgressView(); Text("Enrolling…").foregroundStyle(Color.skTextDim) }
                .padding(.top, 8)
        case .done:
            EmptyView()
        }
    }

    private func button(_ title: String, systemImage: String, id: String, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(Color.skAccent.opacity(enabled ? 1 : 0.4), in: .rect(cornerRadius: Theme.Radius.card, style: .continuous))
        }
        .disabled(!enabled)
        .accessibilityIdentifier(id)
        .padding(.horizontal, Theme.Space.margin)
        .padding(.top, 8)
    }

    private func start() {
        failure = nil
        do {
            try recorder.start()
            phase = .recording
        } catch {
            failure = "Couldn't start recording — check microphone access in Settings."
        }
    }

    private func stopAndEnroll() {
        recorder.stop()
        guard let url = recorder.finishedFileURL else {
            failure = "Recording was lost — try again."; phase = .idle; return
        }
        phase = .enrolling
        let canonical = canonical
        Task {
            // Resample to 16 kHz mono floats (FeedbackRecorder already writes 16 kHz,
            // but AudioConverter normalises to the [Float] the embedder expects), then
            // embed + store under the canonical name via the shared enroll pipeline.
            let samples = try? AudioConverter(sampleRate: 16000).resampleAudioFile(url)
            recorder.discard()
            let ok: Bool
            if let samples {
                ok = await VoiceEnroller.enroll(name: canonical, clip: samples, using: EmbedderFactory.make())
            } else {
                ok = false
            }
            await MainActor.run {
                if ok {
                    phase = .done
                    onEnrolled()
                    Haptics.tap(.light)
                    Task { try? await Task.sleep(for: .seconds(1.1)); dismiss() }
                } else {
                    failure = "Couldn't learn the voice — record a longer, clearer sample (a few seconds of clear speech)."
                    phase = .idle
                }
            }
        }
    }
}
