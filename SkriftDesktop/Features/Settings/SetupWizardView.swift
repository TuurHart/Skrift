import SwiftUI
import AppKit

/// First-launch setup: author name + Obsidian vault path (saved to SettingsStore).
/// Shown when neither is configured. Models download on the first Process run —
/// a live HF download progress bar is a follow-up (needs the engines to surface
/// swift-huggingface's Progress, currently ignored by `ensureLoaded`).
struct SetupWizardView: View {
    var onDone: () -> Void = {}
    var interactive = true

    @State private var author = SettingsStore.shared.load().authorName
    @State private var vault = SettingsStore.shared.load().noteFolder

    var body: some View {
        VStack {
            Spacer()
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(LinearGradient(colors: [Theme.rgb(142, 125, 255), Theme.rgb(106, 89, 239)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 34, height: 34)
                            .overlay(Text("S").font(.system(size: 18, weight: .heavy)).foregroundStyle(.white))
                            .shadow(color: Theme.accent.opacity(0.45), radius: 5, y: 2)
                        Text("Welcome to Skrift").font(.system(size: 22, weight: .bold)).foregroundStyle(Theme.textPrimary)
                    }
                    Text("Offline transcription, enhancement, and name-linking for your voice memos — straight into Obsidian.")
                        .font(.system(size: 13)).foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 14) {
                    fieldRow("Your name", placeholder: "used in note frontmatter") {
                        $author
                    }
                    folderRow("Obsidian vault", value: vault) { vault = $0 }
                }
                .padding(16)
                .background(Theme.hairline.opacity(0.022), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.hairline.opacity(0.07), lineWidth: 1))

                HStack(spacing: 7) {
                    Image(systemName: "arrow.down.circle").font(.system(size: 12))
                    Text("The transcription + enhancement models (~0.6 GB + ~9 GB) download automatically the first time you Process a memo.")
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.system(size: 11)).foregroundStyle(Theme.textMuted)

                HStack {
                    Button("Skip for now", action: finish)
                        .buttonStyle(.plain)
                        .font(.system(size: 12.5)).foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Button(action: finish) {
                        Text("Get started")
                            .font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                            .padding(.horizontal, 18).padding(.vertical, 8)
                            .background(Theme.accent, in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(width: 440)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg)
    }

    private func finish() {
        var s = SettingsStore.shared.load()
        s.authorName = author
        s.noteFolder = vault
        SettingsStore.shared.save(s)
        onDone()
    }

    @ViewBuilder private func fieldRow(_ label: String, placeholder: String, _ binding: () -> Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
            if interactive {
                RingedField(placeholder: placeholder, text: binding())
            } else {
                let v = binding().wrappedValue
                Text(v.isEmpty ? placeholder : v)
                    .font(.system(size: 12))
                    .foregroundStyle(v.isEmpty ? Theme.textMuted : Theme.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 9).padding(.vertical, 7)
                    .background(Theme.hairline.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.hairline.opacity(0.08), lineWidth: 1))
            }
        }
    }

    private func folderRow(_ label: String, value: String, set: @escaping (String) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
            HStack(spacing: 8) {
                Text(value.isEmpty ? "Not set" : value)
                    .font(.system(size: 12))
                    .foregroundStyle(value.isEmpty ? Theme.textMuted : Theme.textPrimary)
                    .lineLimit(1).truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 9).padding(.vertical, 7)
                    .background(Theme.hairline.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.hairline.opacity(0.08), lineWidth: 1))
                if interactive {
                    Button("Choose…") {
                        let panel = NSOpenPanel()
                        panel.canChooseDirectories = true
                        panel.canChooseFiles = false
                        if panel.runModal() == .OK, let url = panel.url { set(url.path) }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12)).foregroundStyle(Theme.accent)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Theme.hairline.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
                }
            }
        }
    }
}
