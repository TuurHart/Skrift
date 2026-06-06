import SwiftUI

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
        .sheet(isPresented: $showEnroll) { VoiceEnrollView(name: person.map(NamesDisplay.name) ?? "") }
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

/// Placeholder voice-enrollment flow. The on-device speaker-embedding extraction
/// (FluidAudio diarizer) is the later Conversation-mode track, so this explains
/// what enrollment will do rather than writing a fake embedding into the synced
/// names DB. Replace with the real record→embed flow when diarization lands.
struct VoiceEnrollView: View {
    let name: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.skBg.ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(Color.skAccent)
                Text("Voice enrollment")
                    .font(.title3.weight(.bold)).foregroundStyle(Color.skText)
                Text("Recording a short sample of \(name)'s voice runs on-device and ships with Conversation mode. Your audio never leaves the phone.")
                    .font(.subheadline)
                    .foregroundStyle(Color.skTextDim)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
                Button("Got it") { dismiss() }
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(Color.skAccent, in: .rect(cornerRadius: Theme.Radius.card, style: .continuous))
                    .padding(.horizontal, Theme.Space.margin)
                    .padding(.top, 8)
            }
            .padding(.top, 60)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .presentationDetents([.medium])
    }
}
