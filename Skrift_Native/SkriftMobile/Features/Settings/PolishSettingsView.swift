import SwiftUI

/// Settings → "Polish on this iPad" (mock m5). The local-model play: the same Gemma the
/// Mac uses, downloaded once and run on the iPad's GPU, offered on-demand. Pure UI — it
/// talks ONLY to `PolishCenter` (never the engine), which owns the model download + the
/// `MemoEnhancement` write. Reachable only when `PolishCenter.shared.isAvailable` (M-series
/// iPad); the phone + simulator never surface it. Uses the grouped-Form Settings idiom.
struct PolishSettingsView: View {
    @State private var center = PolishCenter.shared
    /// Bumped by the editor sheets so the "edited/default" subtitles refresh.
    @State private var promptsTick = 0

    private let explainer = "Your Mac polishes every synced note automatically. This iPad can polish too — only the note you're looking at, only when you ask. Same model, same result; whichever ran last wins everywhere."
    private let promptsFooter = "Prompt edits sync between your Mac and iPad — newest edit wins, so both polishers always speak with one voice."
    private let footnote = "Runs on the iPad's Apple-silicon GPU while the app is open — the iPad never polishes in the background or on battery-critical. Needs an M-series iPad with ~5 GB free. Everything stays on device."

    var body: some View {
        Form {
            Section {
                Text(explainer)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.skTextDim)
                    .fixedSize(horizontal: false, vertical: true)
            } footer: {
                Text(footnote).fixedSize(horizontal: false, vertical: true)
            }

            Section {
                modelCard
            } header: {
                Text("Model")
            }

            // The Mac's prompt knobs, verbatim (v2 — Tuur: "same settings as the
            // Mac, also the prompts"). Editing pushes through the synced carrier.
            Section {
                ForEach(PolishPromptKind.allCases, id: \.self) { kind in
                    NavigationLink {
                        PromptEditorView(kind: kind) { promptsTick += 1 }
                    } label: {
                        HStack {
                            Text(kind.label).font(.system(size: 15))
                            Spacer()
                            Text(PolishPromptsStore.isEdited(kind) ? "edited" : "default")
                                .font(.system(size: 12))
                                .foregroundStyle(PolishPromptsStore.isEdited(kind)
                                                 ? Color.skGreen : Color.skTextFaint)
                        }
                        .id(promptsTick)
                    }
                    .accessibilityIdentifier("ipad-polish-prompt-\(kind.label)")
                }
            } header: {
                Text("Prompts")
            } footer: {
                Text(promptsFooter).fixedSize(horizontal: false, vertical: true)
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

// MARK: - Prompt editor (one prompt, full text, reset-to-default)

/// The Mac's `promptRow` TextEditor as a pushed page. Saving stamps the local
/// store (a real edit) and pushes through the synced carrier immediately, so
/// the Mac picks it up on its next reconcile.
struct PromptEditorView: View {
    let kind: PolishPromptKind
    var onSaved: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    var body: some View {
        VStack(spacing: 0) {
            TextEditor(text: $text)
                .font(.system(size: 14))
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 12).padding(.top, 8)
                .background(Color.skSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(16)
                .accessibilityIdentifier("ipad-prompt-editor")
            if PolishPromptsStore.isEdited(kind) || text != defaultText {
                Button("Reset to default") {
                    text = defaultText
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.skAccentText)
                .padding(.bottom, 14)
                .accessibilityIdentifier("ipad-prompt-reset")
            }
        }
        .frame(maxWidth: Adaptive.readingMaxWidth)
        .frame(maxWidth: .infinity)
        .background(Color.skBg.ignoresSafeArea())
        .navigationTitle(kind.label)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("ipad-prompt-save")
            }
        }
        .onAppear { text = currentText }
    }

    private var defaultText: String {
        switch kind {
        case .copyEdit: return PolishPrompts.copyEdit
        case .summary: return PolishPrompts.summary
        case .title: return PolishPrompts.title
        }
    }

    private var currentText: String {
        switch kind {
        case .copyEdit: return PolishPromptsStore.copyEdit()
        case .summary: return PolishPromptsStore.summary()
        case .title: return PolishPromptsStore.title()
        }
    }

    private func save() {
        PolishPromptsStore.setText(text, for: kind)
        PolishPromptsCloudSync.run(NotesRepository.shared)   // push-on-edit
        onSaved()
        dismiss()
    }
}
