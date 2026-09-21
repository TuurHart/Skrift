import SwiftUI
import SwiftData

/// The app shell — a resizable 2-pane layout (Sidebar | review surface),
/// mirroring the Electron app's `Group`/`Panel` split.
struct RootView: View {
    @Environment(\.modelContext) private var ctx
    @State private var model = AppModel()
    @State private var coordinator = ProcessingCoordinator()
    /// The Mac's ONE live take, end to end (LANES-2026-07-28/BRIEF_LIVEUI.md §7: RootView
    /// owns it, hands it to the sidebar's Record/stop buttons and the pane's draft view).
    /// Built eagerly in `init()`, not lazily on `.task` — `SharedStore.container` (the SAME
    /// container `.modelContainer(SharedStore.container)` binds into `\.modelContext`) is
    /// already available at init time, so there's no optional / first-frame-nil session to
    /// thread through the sidebar and the pane switch below.
    @State private var liveSession: LiveRecordingSession
    @State private var settingsOpen = false
    @State private var showWizard = false
    /// The memo id behind the "not processed yet" peek sheet — set when a Journal
    /// river card points at a memo with no queue row (mocks/lifecycle-ia-explorations.html
    /// #m2, kills the old RootView:34 dead-end flash).
    @State private var unpipelinedSheetID: String?
    @AppStorage(AppTheme.key) private var appTheme = "dark"
    /// Written by the note bar's ◧ toggle (NoteDisplayView.sidebarToggle).
    @AppStorage("macSidebarVisible") private var sidebarVisible = true
    // Live queue = NOT trashed. The predicate keeps soft-deleted files out of the
    // sidebar, selection, and active note.
    // Deleted list now — Review's memo-backed conveyor (mocks/lifecycle-ia-explorations.html
    // #m3) absorbs the queue's old trash sheet, with these as its Mac-local tail.
    @Query(filter: #Predicate<PipelineFile> { $0.deletedAt == nil },
           sort: \PipelineFile.uploadedAt, order: .reverse) private var files: [PipelineFile]

    private var activeFile: PipelineFile? { files.first { $0.id == model.activeID } }

    init() {
        let c = ProcessingCoordinator()
        _coordinator = State(initialValue: c)
        _liveSession = State(initialValue: LiveRecordingSession(coordinator: c, context: SharedStore.container.mainContext))
    }

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
                    // The notes list can be closed from the note bar's ◧ (2026-07-23,
                    // the iPad's arrangement ported back) — same persisted key the
                    // toggle writes.
                    if sidebarVisible {
                        SidebarView(model: model, files: files, coordinator: coordinator,
                                    session: liveSession, onOpenSettings: { settingsOpen = true })
                            // 240 is the MEASURED floor for the header row (identity +
                            // gear, Import + Process, the four filter chips) — at the
                            // old ideal 228 that content overflowed and clipped on BOTH
                            // sides: the app badge sliced in half, "All" and the
                            // "N ready to review" count cut off. Found 2026-07-25 by the
                            // hosted `-snapshot-shell` render (the plain ImageRenderer
                            // path draws this whole column as one placeholder, which is
                            // why it hid for so long). minWidth rises with it — dragging
                            // below the content's floor is what produced the clip.
                            .frame(minWidth: 240, idealWidth: 292, maxWidth: 360)   // m2 cards breathe at ~290 (signed mock)
                    }

                    // ONE selection, ONE pane. `activeID` is the note's id either way —
                    // a synced memo's `PipelineFile` carries the memo UUID as its id
                    // (the contract spine), so the two kinds share an id space. If a
                    // pipeline row exists we render it; if not, the id is an unrated
                    // memo, which `UnratedNotePane` projects into the SAME
                    // `NoteDisplayView`. There is no second renderer and no second
                    // selection state — an unrated note is just a note (Tuur, 2026-07-25:
                    // "its just a normal note. nothing special").
                    //
                    // A live take pre-empts all three: while `liveSession` is mid-take the
                    // pane IS the recording draft (mocks/mac-live-transcription.html m1/m2),
                    // whatever `activeID` happens to be. `.failed` deliberately falls through
                    // to the ordinary switch below — a refusal is not a draft state, it only
                    // ever shows via the sidebar's alert (BRIEF_LIVEUI.md §6).
                    switch liveSession.phase {
                    case .starting, .live, .settling:
                        RecordingDraftView(session: liveSession)
                            .frame(minWidth: 480, maxWidth: .infinity, maxHeight: .infinity)
                    default:
                        if let activeFile {
                            NoteDisplayView(file: activeFile, coordinator: coordinator,
                                            onOpenMemo: { id in model.select(id) },
                                            searchQuery: model.searchText)
                                .frame(minWidth: 480, maxWidth: .infinity, maxHeight: .infinity)
                        } else if let id = model.activeID {
                            UnratedNotePane(memoID: id, coordinator: coordinator,
                                            // A rating pipelines it; the id doesn't change,
                                            // so the pane swaps to the real row by itself the
                                            // moment the sweep's `@Query` yields it.
                                            onRated: { _ in },
                                            onOpenMemo: { other in model.select(other) },
                                            searchQuery: model.searchText)
                                .frame(minWidth: 480, maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            NoteDisplayView(file: nil, coordinator: coordinator)
                                .frame(minWidth: 480, maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
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
                },
                onDeleted: { _ in unpipelinedSheetID = nil })
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
            // One-clock doctrine switch (2026-07-22): old parked notes get a
            // fresh clock once, so nothing fades out from under the user.
            if let cloudCtx = MemoCloudStore.container?.mainContext {
                MemoLifecycle.runOneClockMigrationOnce(context: cloudCtx)
            }
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
            #if DEBUG
            // The synthetic corpus (test-fixtures/corpus): `-corpus <path>` seeds it into the
            // shared MEMO store, so the reconcile sweep ingests it like phone notes.
            if let corpus = CorpusSeed.launchPath, let cloudCtx = MemoCloudStore.container?.mainContext {
                let outcome = (try? CorpusSeed.seed(from: corpus, into: cloudCtx,
                                                    recordingsDirectory: AppPaths.recordingsDirectory,
                                                    names: NamesStore.shared)).map(String.init(describing:))
                FileHandle.standardError.write(Data(((outcome ?? "corpus: seed FAILED at \(corpus.path)") + "\n").utf8))
            }
            #endif
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
        // At rest (m5): a completed take hands back a `noteID` and returns to `.idle` —
        // select it so the shell follows the take to wherever it landed (a normal
        // PipelineFile row or, being freshly unrated, the quiet-row/UnratedNotePane path;
        // either way `model.select` doesn't care which). No `initial:` — this must fire
        // only on an actual settling→idle transition, never on launch's starting `.idle`.
        .onChange(of: liveSession.phase) { _, new in
            if new == .idle, let id = liveSession.noteID { model.select(id) }
        }
    }

    private func ensureSelection() {
        if model.activeID == nil, let first = files.first {
            model.activeID = first.id
            model.selection = [first.id]
        }
    }
}

