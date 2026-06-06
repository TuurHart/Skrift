import SwiftUI

/// Contextual primary action (Process → Export to Obsidian → Re-export) plus a ⋯
/// overflow (re-transcribe, redo per-step). Ported from `NoteActions.tsx`.
/// Actions are stubbed until the export/enhance pipeline is wired to the UI.
struct NoteActions: View {
    let file: PipelineFile
    var coordinator: ProcessingCoordinator
    @Environment(\.modelContext) private var ctx
    @State private var menuOpen = false

    private var enhanceDone: Bool { file.steps.enhance == .done }
    private var exported: Bool { file.steps.export == .done }
    private var isAppleNote: Bool { file.sourceType == .note }
    private var transcribeDone: Bool { file.steps.transcribe == .done }

    private var primaryLabel: String {
        if !enhanceDone { return "Process" }
        return exported ? "Re-export" : "Export to Obsidian"
    }

    private var menuItems: [String] {
        var items: [String] = []
        if transcribeDone && !isAppleNote { items.append("Re-transcribe") }
        let hasParts = !(file.enhancedTitle ?? "").isEmpty
            && !(file.enhancedCopyedit ?? "").isEmpty
            && !(file.enhancedSummary ?? "").isEmpty
        if hasParts {
            items.append(contentsOf: ["Redo title", "Redo copy-edit", "Redo summary"])
        }
        return items
    }

    private func primaryAction() {
        if !enhanceDone {
            Task { await coordinator.process(fileIDs: [file.id], context: ctx) }
        } else {
            coordinator.export(file, context: ctx)
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Button(action: primaryAction) {
                Text(primaryLabel)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)

            if !menuItems.isEmpty {
                Button { menuOpen.toggle() } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15))
                        .foregroundStyle(menuOpen ? Theme.textPrimary : Theme.textSecondary)
                        .frame(width: 30, height: 30)
                        .background(Theme.hairline.opacity(menuOpen ? 0.09 : 0.05), in: RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .overlay(alignment: .topTrailing) {
                    if menuOpen { dropdown }
                }
            }
        }
    }

    /// Custom dropdown (matches the web's styled menu; renders cleanly in snapshots,
    /// unlike the AppKit-backed `Menu`). Default-closed.
    private var dropdown: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(menuItems, id: \.self) { item in
                Button { menuOpen = false } label: {
                    Text(item)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: 184)
        .padding(.vertical, 4)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.hairline.opacity(0.12), lineWidth: 1))
        .shadow(color: .black.opacity(0.4), radius: 14, y: 4)
        .offset(y: 38)
        .zIndex(10)
    }
}
