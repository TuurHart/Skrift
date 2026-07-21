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
    /// The memo id behind the "not processed yet" peek sheet — set when a Journal
    /// river card points at a memo with no queue row (mocks/lifecycle-ia-explorations.html
    /// #m2, kills the old RootView:34 dead-end flash).
    @State private var unpipelinedSheetID: String?
    @AppStorage(AppTheme.key) private var appTheme = "dark"
    // Live queue = NOT trashed. The predicate keeps soft-deleted files out of the
    // sidebar, selection, and active note.
    // Deleted list now — Review's memo-backed conveyor (mocks/lifecycle-ia-explorations.html
    // #m3) absorbs the queue's old trash sheet, with these as its Mac-local tail.
    @Query(filter: #Predicate<PipelineFile> { $0.deletedAt == nil },
           sort: \PipelineFile.uploadedAt, order: .reverse) private var files: [PipelineFile]

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
                        unpipelinedSheetID = id
                    }
                })
            } else {
                HSplitView {
                    SidebarView(model: model, files: files, coordinator: coordinator,
                                onOpenSettings: { settingsOpen = true })
                        .frame(minWidth: 200, idealWidth: 228, maxWidth: 320)

                    NoteDisplayView(file: activeFile, coordinator: coordinator,
                                    onOpenMemo: { id in model.activeID = id; model.selection = [id] },
                                    searchQuery: model.searchText)
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
        .sheet(isPresented: Binding(
            get: { unpipelinedSheetID != nil },
            set: { if !$0 { unpipelinedSheetID = nil } }
        )) {
            UnpipelinedMemoSheet(
                memoID: unpipelinedSheetID ?? "",
                onClose: { unpipelinedSheetID = nil },
                onProcessed: { id in
                    unpipelinedSheetID = nil
                    model.surface = .queue
                    model.activeID = id
                    model.selection = [id]
                })
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
            // The 60d fading→Recently-Deleted auto-move — a standing heartbeat now
            // (launch + day-change + 24h), not tied to opening Review (Q4).
            LifecycleSweepScheduler.start()
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

