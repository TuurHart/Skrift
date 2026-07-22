import SwiftUI

/// Settings → "Polish on this iPad" (mock m5). The local-model play: the same Gemma the
/// Mac uses, downloaded once and run on the iPad's GPU, offered on-demand. Pure UI — it
/// talks ONLY to `PolishCenter` (never the engine), which owns the model download + the
/// `MemoEnhancement` write. Reachable only when `PolishCenter.shared.isAvailable` (M-series
/// iPad); the phone + simulator never surface it. Uses the grouped-Form Settings idiom.
struct PolishSettingsView: View {
    @State private var center = PolishCenter.shared
    @AppStorage(PolishGate.polishOnOpenKey) private var polishOnOpen = false

    private let explainer = "Your Mac polishes every synced note automatically. This iPad can polish too — only the note you're looking at, only when you ask. Same model, same result; whichever ran last wins everywhere."
    private let toggleSub = "An unpolished note starts polishing as you read it. Off = only the ⋯ menu's \"Polish now\"."
    private let footnote = "Runs on the iPad's Apple-silicon GPU while the app is open — the iPad never polishes in the background or on battery-critical. Needs an M-series iPad with ~5 GB free. Everything stays on device."

    var body: some View {
        Form {
            Section {
                Text(explainer)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.skTextDim)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section {
                modelCard
            } header: {
                Text("Model")
            }

            Section {
                Toggle("Polish when I open a note", isOn: $polishOnOpen)
                    .accessibilityIdentifier("ipad-polish-on-open")
            } footer: {
                VStack(alignment: .leading, spacing: 12) {
                    Text(toggleSub)
                    Text(footnote)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.skBg.ignoresSafeArea())
        .navigationTitle("Polish on this iPad")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { center.refreshModelState() }
    }

    // MARK: - Model card (name · size · Download / % / Downloaded ✓)

    private var modelCard: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 17))
                .foregroundStyle(Color.skAccent)
            VStack(alignment: .leading, spacing: 3) {
                Text("Gemma 4 E4B — the model your Mac uses")
                    .font(.system(size: 15, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
                Text("4.6 GB · downloads once, runs entirely on this iPad")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.skTextDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            trailingControl
        }
        .padding(.vertical, 2)
        .accessibilityIdentifier("ipad-polish-model-card")
    }

    @ViewBuilder
    private var trailingControl: some View {
        switch center.modelPhase {
        case .unknown, .checking:
            ProgressView().controlSize(.small).tint(.skAccent)
        case .notDownloaded:
            Button("Download") { center.downloadModelForSettings() }
                .buttonStyle(.borderless)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.skAccent)
                .accessibilityIdentifier("ipad-polish-download")
        case .downloading(let p):
            VStack(alignment: .trailing, spacing: 2) {
                ProgressView(value: p)
                    .progressViewStyle(.linear)
                    .frame(width: 72).tint(.skAccent)
                Text("\(Int(p * 100))%")
                    .font(.system(size: 11)).foregroundStyle(Color.skTextFaint)
            }
        case .downloaded:
            Label("Downloaded", systemImage: "checkmark.circle.fill")
                .labelStyle(.titleAndIcon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.skTextDim)
                .accessibilityIdentifier("ipad-polish-downloaded")
        case .failed:
            Button("Retry") { center.downloadModelForSettings() }
                .buttonStyle(.borderless)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.skAccent)
                .accessibilityIdentifier("ipad-polish-retry")
        }
    }
}
