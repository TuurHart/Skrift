import SwiftUI

/// Settings → "Review & search": the consent flow that turns the semantic
/// half of P8 ON. Enabling downloads EmbeddingGemma (295 MB, one-time, on
/// device) and starts the foreground sweeps; disabling stops sweeps and hides
/// every semantic surface (Related, threads, search Related). The model and
/// index stay on disk so re-enabling is instant.
///
/// States + copy come from the SHARED `RetrievalGate` (one machine with the
/// Mac's Connections panel): real download %, then PREPARING while the CoreML
/// compile/ANE load runs (~2 min on an A15 — this used to sit on one frozen
/// indeterminate spinner across BOTH phases), then indexing N of M.
struct JournalIndexSettingsSection: View {
    @AppStorage(JournalIndexService.enabledDefaultsKey) private var enabled = false
    @State private var phase: Phase = .idle
    private let service = JournalIndexService.shared

    enum Phase: Equatable {
        case idle
        case downloading(Double)
        case preparing
        case failed(String)
    }

    var body: some View {
        Section {
            Toggle(RetrievalGate.Copy.settingTitle, isOn: $enabled)
                .accessibilityIdentifier("setting-journal-index")
                .disabled(phase != .idle && phase.isBusy)
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
            Text("Review & search")
        } footer: {
            Text(RetrievalGate.Copy.gateBody(
                device: UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"))
        }
    }

    @ViewBuilder
    private var statusRow: some View {
        switch phase {
        case .downloading(let fraction):
            VStack(alignment: .leading, spacing: 5) {
                Text(RetrievalGate.Copy.downloadingTitle)
                    .foregroundStyle(Color.skText)
                ProgressView(value: fraction)
                    .tint(Color.skAccent)
                Text(RetrievalGate.Copy.downloadingSub(fraction: fraction))
                    .font(.footnote)
                    .foregroundStyle(Color.skTextDim)
            }
        case .preparing:
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(RetrievalGate.Copy.preparingTitle)
                        .foregroundStyle(Color.skText)
                }
                Text(RetrievalGate.Copy.preparingSub)
                    .font(.footnote)
                    .foregroundStyle(Color.skTextDim)
            }
        case .failed(let message):
            Text(RetrievalGate.Copy.downloadFailed(message))
                .font(.footnote)
                .foregroundStyle(Color.skRed)
        case .idle:
            if enabled, let p = service.sweepProgress {
                VStack(alignment: .leading, spacing: 5) {
                    Text(RetrievalGate.Copy.indexingTitle)
                        .foregroundStyle(Color.skText)
                    ProgressView(value: p.total > 0 ? Double(p.done) / Double(p.total) : 0)
                        .tint(Color.skGreen)
                    Text(RetrievalGate.Copy.indexingSub(done: p.done, total: p.total))
                        .font(.footnote)
                        .foregroundStyle(Color.skTextDim)
                }
            } else if enabled, let err = service.lastError {
                // A failed sweep shows here as on the Mac (R58) — it was invisible on phone/iPad.
                Text(err)
                    .font(.footnote)
                    .foregroundStyle(Color.skRed)
            } else if enabled && GemmaEmbedder.isModelDownloaded {
                Text(RetrievalGate.Copy.readyLine)
                    .font(.footnote)
                    .foregroundStyle(Color.skTextDim)
            } else if !enabled && GemmaEmbedder.isModelDownloaded {
                Text(RetrievalGate.Copy.pausedLine)
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
        phase = .downloading(0)
        // Mirrored into the service so the iPad Connections panel shows the same
        // downloading/preparing states (one RetrievalGate derivation).
        service.downloadFraction = 0
        GemmaEmbedder.downloadProgress = { received, total in
            Task { @MainActor in
                // Bytes done → the ANE compile runs next; name it (frozen-bar lesson).
                // A late callback after success/failure must not resurrect a bar.
                guard phase.isBusy else { return }
                let f = total > 0 ? Double(received) / Double(total) : 0
                phase = f >= 0.999 ? .preparing : .downloading(f)
                JournalIndexService.shared.downloadFraction = f
            }
        }
        Task {
            do {
                try await GemmaEmbedder.shared.prepare()
                phase = .idle
                JournalIndexService.shared.downloadFraction = nil
                JournalIndexService.shared.sweepSoon(NotesRepository.shared)
            } catch {
                phase = .failed(error.localizedDescription)
                JournalIndexService.shared.downloadFraction = nil
                enabled = false
            }
            GemmaEmbedder.downloadProgress = nil
        }
    }
}

extension JournalIndexSettingsSection.Phase {
    var isBusy: Bool {
        switch self {
        case .downloading, .preparing: return true
        case .idle, .failed: return false
        }
    }
}
