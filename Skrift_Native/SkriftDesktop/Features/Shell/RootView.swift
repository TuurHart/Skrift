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
    @State private var trashOpen = false
    @AppStorage(AppTheme.key) private var appTheme = "dark"
    // Live queue = NOT trashed (Recently Deleted is its own sheet). The predicate
    // keeps soft-deleted files out of the sidebar, selection, and active note.
    @Query(filter: #Predicate<PipelineFile> { $0.deletedAt == nil },
           sort: \PipelineFile.uploadedAt, order: .reverse) private var files: [PipelineFile]
    @Query(filter: #Predicate<PipelineFile> { $0.deletedAt != nil },
           sort: \PipelineFile.deletedAt, order: .reverse) private var trashedFiles: [PipelineFile]

    private var activeFile: PipelineFile? { files.first { $0.id == model.activeID } }

    var body: some View {
        Group {
            if model.surface == .journal {
                // Journal (signed mock journal-desktop.html): rail + reading column.
                // A card click jumps to that memo's row in the Queue when it exists.
                JournalView(model: model, coordinator: coordinator, onOpenInQueue: { id in
                    if files.contains(where: { $0.id == id }) {
                        model.surface = .queue
                        model.activeID = id
                        model.selection = [id]
                    } else {
                        coordinator.flash("Not in the queue — this note hasn't been processed on the Mac")
                    }
                })
            } else {
                HSplitView {
                    SidebarView(model: model, files: files, coordinator: coordinator,
                                trashedCount: trashedFiles.count,
                                onOpenSettings: { settingsOpen = true },
                                onOpenTrash: { trashOpen = true })
                        .frame(minWidth: 200, idealWidth: 228, maxWidth: 320)

                    NoteDisplayView(file: activeFile, coordinator: coordinator,
                                    onOpenMemo: { id in model.activeID = id; model.selection = [id] })
                        .frame(minWidth: 480, maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .background(Theme.bg)
        .preferredColorScheme(AppTheme.colorScheme(appTheme))
        // Keep the AppKit layer (placeholders/carets/menus) in lock-step with the
        // SwiftUI colorScheme when the user switches theme.
        .onChange(of: appTheme) { _, new in AppTheme.applyToApp(new) }
        .sheet(isPresented: $settingsOpen) {
            SettingsView(onClose: { settingsOpen = false })
        }
        .sheet(isPresented: $trashOpen) {
            RecentlyDeletedView(files: trashedFiles, onClose: { trashOpen = false })
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
            // Real app starts empty; `-demo` populates with sample notes for dev/demo,
            // `-naming-demo` (DEBUG) seeds one self-consistent naming-review example.
            let args = ProcessInfo.processInfo.arguments
            #if DEBUG
            let namingDemo = args.contains("-naming-demo")
            #else
            let namingDemo = false
            #endif
            if namingDemo {
                #if DEBUG
                DemoSeed.seedNamingDemo(ctx)
                #endif
            } else if args.contains("-demo") {
                DemoSeed.seedIfEmpty(ctx)
            } else {
                let s = SettingsStore.shared.load()
                if s.authorName.isEmpty && s.noteFolder.isEmpty { showWizard = true }
            }
            // Recover any run stranded mid-flight by a previous crash/quit.
            coordinator.reconcileInterruptedRuns(context: ctx)
            // Purge trash older than the retention window (mirrors the phone's
            // launch purge) — permanently drops the record + trashes its folder.
            DesktopTrash.purgeExpired(in: ctx)
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

