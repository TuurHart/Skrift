import SwiftUI
import SwiftData

/// The app shell — a resizable 2-pane layout (Sidebar | review surface),
/// mirroring the Electron app's `Group`/`Panel` split.
struct RootView: View {
    @Environment(\.modelContext) private var ctx
    @State private var model = AppModel()
    @State private var coordinator = ProcessingCoordinator()
    @State private var settingsOpen = false
    @State private var showWizard = false
    @Query(sort: \PipelineFile.uploadedAt, order: .reverse) private var files: [PipelineFile]

    private var activeFile: PipelineFile? { files.first { $0.id == model.activeID } }

    var body: some View {
        HSplitView {
            SidebarView(model: model, files: files, coordinator: coordinator,
                        onOpenSettings: { settingsOpen = true })
                .frame(minWidth: 200, idealWidth: 228, maxWidth: 320)

            NoteDisplayView(file: activeFile, coordinator: coordinator)
                .frame(minWidth: 480, maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 900, minHeight: 600)
        .background(Theme.bg)
        .preferredColorScheme(.dark)   // app is dark-only; keep all controls light-on-dark
        .sheet(isPresented: $settingsOpen) {
            SettingsView(onClose: { settingsOpen = false })
        }
        .overlay {
            if showWizard {
                SetupWizardView(onDone: { showWizard = false })
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .top) {
            if let toast = coordinator.toast {
                Text(toast)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(Theme.accent, in: Capsule())
                    .shadow(color: .black.opacity(0.3), radius: 10, y: 3)
                    .padding(.top, 16)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: coordinator.toast)
        .task {
            // Real app starts empty; `-demo` populates with sample notes for dev/demo.
            if ProcessInfo.processInfo.arguments.contains("-demo") {
                DemoSeed.seedIfEmpty(ctx)
            } else {
                let s = SettingsStore.shared.load()
                if s.authorName.isEmpty && s.noteFolder.isEmpty { showWizard = true }
            }
            // Recover any run stranded mid-flight by a previous crash/quit.
            coordinator.reconcileInterruptedRuns(context: ctx)
        }
        .onChange(of: files.count, initial: true) { _, _ in ensureSelection() }
    }

    private func ensureSelection() {
        if model.activeID == nil, let first = files.first {
            model.activeID = first.id
            model.selection = [first.id]
        }
    }
}

