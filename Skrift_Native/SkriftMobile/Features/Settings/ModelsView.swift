import SwiftUI

/// Settings → Models: the on-device ML models — downloaded state + size on
/// disk, plus a manual Download / retry for the transcription model (the one
/// the app can't transcribe without). A user who skips the model step in
/// onboarding — or whose download failed — recovers from here instead of being
/// stuck with no transcription and no way to fetch it. Inventory data comes from
/// `ModelInventory` (FluidAudio cache dirs); live download progress comes from
/// `ModelLoadStatus` (driven by `TranscriptionService`).
struct ModelsView: View {
    @State private var entries: [ModelInventory.Entry] = []
    @ObservedObject private var modelStatus = ModelLoadStatus.shared
    /// Set the instant Download is tapped so the row shows a spinner before
    /// `ModelLoadStatus` flips to `.downloading`/`.preparing`.
    @State private var asrRequested = false

    /// The transcription model — the only one with a manual download here. The
    /// others (speaker recognition, custom-word spotting) genuinely fetch on
    /// first use, so they keep their read-only "Not downloaded" label.
    private static let asrID = "asr"

    private var totalLine: String {
        let total = entries.compactMap(\.sizeBytes).reduce(0, +)
        return total > 0 ? "Total: \(ModelInventory.format(bytes: total))" : "No models downloaded yet."
    }

    var body: some View {
        Form {
            Section {
                ForEach(entries) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(entry.name)
                                .font(.system(size: 15, weight: .medium))
                            Spacer()
                            trailing(for: entry)
                        }
                        Text(entry.detail)
                            .font(.system(size: 12))
                            .foregroundStyle(Color.skTextDim)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 2)
                    .accessibilityIdentifier("model-row-\(entry.id)")
                }
            } footer: {
                Text("\(totalLine) Models download automatically when first needed and run fully on-device — nothing leaves your phone.")
            }
        }
        .navigationTitle("Models")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { entries = ModelInventory.entries() }
        .refreshable { entries = ModelInventory.entries() }
        // When a download finishes, re-read sizes so the row flips to its size.
        .onChange(of: modelStatus.phase) { _, phase in
            if phase == .ready { entries = ModelInventory.entries() }
        }
    }

    /// Trailing control for a row: the size when downloaded, a Download control
    /// for the transcription model when it isn't, and the plain "Not downloaded"
    /// label for the fetch-on-demand models.
    @ViewBuilder
    private func trailing(for entry: ModelInventory.Entry) -> some View {
        if let size = entry.sizeBytes {
            Text(ModelInventory.format(bytes: size))
                .font(.system(size: 13))
                .foregroundStyle(Color.skTextDim)
        } else if entry.id == Self.asrID {
            asrDownloadControl
        } else {
            Text("Not downloaded")
                .font(.system(size: 13))
                .foregroundStyle(Color.skTextFaint)
        }
    }

    @ViewBuilder
    private var asrDownloadControl: some View {
        if let progress = modelStatus.downloadProgress {
            VStack(alignment: .trailing, spacing: 2) {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .frame(width: 72).tint(.skAccent)
                Text("\(Int(progress * 100))%")
                    .font(.system(size: 11)).foregroundStyle(Color.skTextFaint)
            }
        } else if asrRequested || modelStatus.loading {
            ProgressView().controlSize(.small).tint(.skAccent)
        } else {
            Button("Download", action: downloadASR)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.skAccent)
                .accessibilityIdentifier("model-download-asr")
        }
    }

    private func downloadASR() {
        asrRequested = true
        // Progress + ready come from ModelLoadStatus; we just kick it off and
        // refresh sizes when it settles (success → onChange handles it too;
        // this also clears the spinner on failure so the button returns).
        Task {
            try? await TranscriptionService.shared.ensureLoaded()
            await MainActor.run {
                asrRequested = false
                entries = ModelInventory.entries()
            }
        }
    }
}
