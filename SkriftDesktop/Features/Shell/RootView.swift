import SwiftUI
import SwiftData

/// The app shell — a resizable 2-pane layout (Sidebar | review surface),
/// mirroring the Electron app's `Group`/`Panel` split.
struct RootView: View {
    @Environment(\.modelContext) private var ctx
    @State private var model = AppModel()
    @State private var coordinator = ProcessingCoordinator()
    @Query(sort: \PipelineFile.uploadedAt, order: .reverse) private var files: [PipelineFile]

    private var activeFile: PipelineFile? { files.first { $0.id == model.activeID } }

    var body: some View {
        HSplitView {
            SidebarView(model: model, files: files, coordinator: coordinator)
                .frame(minWidth: 200, idealWidth: 228, maxWidth: 320)

            NoteDisplayView(file: activeFile, coordinator: coordinator)
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

