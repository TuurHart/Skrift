import SwiftUI
import SwiftData

/// The app shell — a resizable 2-pane layout (Sidebar | review surface),
/// mirroring the Electron app's `Group`/`Panel` split.
struct RootView: View {
    @Environment(\.modelContext) private var ctx
    @State private var model = AppModel()
    @Query(sort: \PipelineFile.uploadedAt, order: .reverse) private var files: [PipelineFile]

    private var activeFile: PipelineFile? { files.first { $0.id == model.activeID } }

    var body: some View {
        HSplitView {
            SidebarView(model: model, files: files)
                .frame(minWidth: 200, idealWidth: 228, maxWidth: 320)

            DetailPane(file: activeFile)
                .frame(minWidth: 480, maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 900, minHeight: 600)
        .background(Theme.bg)
        .task { DemoSeed.seedIfEmpty(ctx) }
        .onChange(of: files.count, initial: true) { _, _ in ensureSelection() }
    }

    private func ensureSelection() {
        if model.activeID == nil, let first = files.first {
            model.activeID = first.id
            model.selection = [first.id]
        }
    }
}

/// Placeholder for the review surface (built out in chunks 2–4: toolbar,
/// properties, body + karaoke).
struct DetailPane: View {
    let file: PipelineFile?

    var body: some View {
        Group {
            if let file {
                VStack(spacing: 8) {
                    Text(file.queueTitle)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Review surface — building next")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textMuted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 30))
                        .foregroundStyle(Theme.textMuted.opacity(0.4))
                    Text("Select a note to get started")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.textMuted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Theme.bg)
    }
}
