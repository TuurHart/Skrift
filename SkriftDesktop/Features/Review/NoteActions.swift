import SwiftUI

/// Contextual primary action (Process → Export to Obsidian → Re-export) plus a ⋯
/// overflow (re-transcribe, redo per-step). Ported from `NoteActions.tsx`.
/// Actions are stubbed until the export/enhance pipeline is wired to the UI.
struct NoteActions: View {
    let file: PipelineFile
    var coordinator: ProcessingCoordinator
    @Environment(\.modelContext) private var ctx

    private var enhanceDone: Bool { file.steps.enhance == .done }
    private var exported: Bool { file.steps.export == .done }
    private var isAppleNote: Bool { file.sourceType == .note }
    private var transcribeDone: Bool { file.steps.transcribe == .done }

    private var primaryLabel: String {
        if !enhanceDone { return "Process" }
        return exported ? "Re-export" : "Export to Obsidian"
    }

    private var hasParts: Bool {
        !(file.enhancedTitle ?? "").isEmpty
            && !(file.enhancedCopyedit ?? "").isEmpty
            && !(file.enhancedSummary ?? "").isEmpty
    }
    private var canRetranscribe: Bool { transcribeDone && !isAppleNote }
    private var hasOverflow: Bool { canRetranscribe || hasParts }

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

            if hasOverflow {
                // Native Menu: auto-dismisses on outside click (N3) and the items
                // run real actions (N4). Default-closed, so it snapshots fine.
                Menu {
                    if canRetranscribe {
                        Button("Re-transcribe") { Task { await coordinator.retranscribe(file, context: ctx) } }
                    }
                    if hasParts {
                        Button("Redo title") { Task { await coordinator.redo(.title, for: file, context: ctx) } }
                        Button("Redo copy-edit") { Task { await coordinator.redo(.copyEdit, for: file, context: ctx) } }
                        Button("Redo summary") { Task { await coordinator.redo(.summary, for: file, context: ctx) } }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 30, height: 30)
                        .background(Theme.hairline.opacity(0.05), in: RoundedRectangle(cornerRadius: 7))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
        }
    }

}
