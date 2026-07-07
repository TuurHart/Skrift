import SwiftUI

/// Settings → "Journal & search": the consent flow that turns the semantic
/// half of P8 ON. Enabling downloads EmbeddingGemma (295 MB, one-time, on
/// device) and starts the foreground sweeps; disabling stops sweeps and hides
/// every semantic surface (Related, threads, search Related). The model and
/// index stay on disk so re-enabling is instant.
struct JournalIndexSettingsSection: View {
    @AppStorage(JournalIndexService.enabledDefaultsKey) private var enabled = false
    @State private var phase: Phase = .idle

    enum Phase: Equatable {
        case idle
        case downloading
        case failed(String)
    }

    var body: some View {
        Section {
            Toggle("Semantic journal index", isOn: $enabled)
                .accessibilityIdentifier("setting-journal-index")
                .disabled(phase == .downloading)
                .onChange(of: enabled) { _, on in
                    if on { activate() } else { phase = .idle }
                }
            statusRow
            #if DEBUG
            Button("Log score histogram (dev)") {
                JournalIndexService.shared.logScoreHistogram(NotesRepository.shared)
            }
            .font(.footnote)
            .foregroundStyle(Color.skTextDim)
            #endif
        } header: {
            Text("Journal & search")
        } footer: {
            Text("Finds notes by meaning — Related notes, threads, and semantic search. Runs fully on this \(UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"); nothing leaves the device. The language model is a one-time 295 MB download.")
        }
    }

    @ViewBuilder
    private var statusRow: some View {
        switch phase {
        case .downloading:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Downloading model (295 MB)…")
                    .foregroundStyle(Color.skTextDim)
            }
        case .failed(let message):
            Text("Download failed — \(message)")
                .font(.footnote)
                .foregroundStyle(Color.skRed)
        case .idle:
            if enabled && GemmaEmbedder.isModelDownloaded {
                Text("Ready — your notes index when the app opens.")
                    .font(.footnote)
                    .foregroundStyle(Color.skTextDim)
            } else if !enabled && GemmaEmbedder.isModelDownloaded {
                Text("Model downloaded · index paused")
                    .font(.footnote)
                    .foregroundStyle(Color.skTextDim)
            }
        }
    }

    private func activate() {
        guard !GemmaEmbedder.isModelDownloaded else {
            JournalIndexService.shared.sweepSoon(NotesRepository.shared)
            return
        }
        phase = .downloading
        Task {
            do {
                try await GemmaEmbedder.shared.prepare()
                phase = .idle
                JournalIndexService.shared.sweepSoon(NotesRepository.shared)
            } catch {
                phase = .failed(error.localizedDescription)
                enabled = false
            }
        }
    }
}
