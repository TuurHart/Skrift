import SwiftUI
import SwiftData
import UIKit
import UniformTypeIdentifiers

enum MemoSort: String, CaseIterable, Identifiable {
    case added = "Recently added"
    case edited = "Recently edited"
    case recent = "Recently recorded"
    case oldest = "Oldest first"
    case longest = "Longest first"
    var id: String { rawValue }

    /// Compact label for the iPad's inline sort control (the Mac's `SidebarSort`
    /// idiom). `.added` → "Newest", matching the Mac's default word.
    var short: String {
        switch self {
        case .added:   return "Newest"
        case .edited:  return "Edited"
        case .recent:  return "Recorded"
        case .oldest:  return "Oldest"
        case .longest: return "Longest"
        }
    }

    /// Next sort in the cycle — the inline control advances on tap, like the Mac.
    var next: MemoSort {
        let all = Self.allCases
        return all[(all.firstIndex(of: self).map { $0 + 1 } ?? 0) % all.count]
    }
}

/// Which date a date-range filter applies to.
enum MemoDateField: String, CaseIterable, Identifiable {
    case recorded = "Recorded"
    case added = "Added"
    var id: String { rawValue }
}

struct MemoFilter: Equatable {
    var unsyncedOnly = false
    var hasPhotosOnly = false
    /// Couch-triage mode (⏱ eyeball wave 2, 2026-07-22): the Mac's "Unrated"
    /// chip as a pulled lever, not standing chrome — unrated, unlocked notes
    /// only (locked = resolved, matching the Mac band).
    var notRatedOnly = false
    var place: String?
    /// Optional date-range filter, applied to either the recorded or added date.
    var dateField: MemoDateField = .recorded
    var from: Date?
    var to: Date?
    var isActive: Bool { unsyncedOnly || hasPhotosOnly || notRatedOnly || place != nil || from != nil || to != nil }
}

/// The memos surface (mockup3): full-text search, day-group cards with honest
/// status pills, multi-select, a single funnel = Sort & Filter sheet, and the
/// record FAB. Tapping a card opens Memo detail; the FAB opens the recorder
/// (which on Stop pushes detail — the save-now flow).
struct MemosListView: View {
    // Trashed memos (deletedAt != nil) are excluded here and live in the
    // Recently Deleted screen until restored or purged.
    @Query(filter: #Predicate<Memo> { $0.deletedAt == nil },
           sort: \Memo.recordedAt, order: .reverse) private var memos: [Memo]
    /// ONE query behind the header's "Process N" — which notes already carry
    /// polished content. Per-memo enhancement fetches inside a body are the
    /// frozen-library trap (2026-07-23), so the set is built once here.
    @Query private var enhancements: [MemoEnhancement]
    @Environment(\.modelContext) private var context
    private let repository = NotesRepository.shared

    @State private var path: [UUID] = []
    @State private var showRecord = false
    /// Presents the audiobook player for the continue-card's body tap (hoisted
    /// here: a cover on the card itself would die when its List row unmounts).
    @State private var showBookPlayer = false
    @State private var lastHandledStart = 0
    @ObservedObject private var intentBridge = RecordingIntentBridge.shared
    @ObservedObject private var memoOpen = MemoOpenBridge.shared
    /// Long-press → "Remind me…" (chunk 7).
    @State private var reminderMemo: Memo?
    /// Locking a memo that's already published → honest notice (chunk 8).
    @State private var lockVaultNotice = false
    /// In-app document scan (chunk 9) — device-only entry.
    @State private var showDocScanner = false
    /// D8 in-app media import: Files picker (audio + video) and the Photos
    /// video picker — before this there was NO in-app way to import an audio
    /// file at all, and the video picker was built but never wired anywhere.
    @State private var showMediaFileImporter = false
    @State private var showVideoImporter = false
    @State private var showSortFilter = false
    /// Presents WayOutView — the merged Fading + Recently Deleted shelf (Q4,
    /// 2026-07-20). One sheet now instead of two (`showTrash` retired).
    /// Last shelf visit — the ⋯ dot lights only for fade-entries newer than this.
    /// CloudKit (device↔device) sync activity — drives the "Syncing with iCloud…"
    /// strip below the search field. Distinct from the Mac `syncBanner` above.
    @ObservedObject private var cloudSync = CloudSyncMonitor.shared
    /// Share-imports being copied out of the inbox (A14) — drives the top pill so
    /// a big shared movie doesn't look like nothing happened until the drain ends.
    @ObservedObject private var drainState = CaptureDrainState.shared
    @State private var search = LaunchFlags.initialSearch ?? ""
    /// Semantic hits for the current search (P8) — empty unless the journal
    /// index is active AND something clears the floor.
    @State private var related: [Memo] = []
    /// Debounced semantic lookup, held in @State so view-identity churn (the
    /// ticking mini-player) can't cancel it — only a newer query does.
    @State private var searchTask: Task<Void, Never>?
    @State private var sort: MemoSort = .added
    @State private var filter = MemoFilter()
    /// The Mac's triage chip, at regular width only (All / Needs Work / Done /
    /// Unrated — shared `QueueFilter`). Compact keeps the phone's funnel sheet.
    @State private var listChip: QueueFilter = .all
    @State private var editMode: EditMode = .inactive
    @State private var selected: Set<UUID> = []
    @State private var syncBanner: String?
    @State private var bannerToken = 0
    /// iPad wave 1: layout branches on the horizontal size class (NEVER device
    /// idiom — Split View/Stage Manager can make the iPad compact, and compact
    /// must stay the phone layout, pixel-untouched).
    @Environment(\.horizontalSizeClass) private var hSize
    /// The note shown in the split-view detail pane at regular width. nil on the
    /// phone (compact pushes onto `path` instead), so the whole split path is a
    /// no-op there.
    @State private var selectedMemoID: UUID?
    /// The memo the detail pane currently shows (its pager can swipe past the row
    /// you tapped) — published up by `MemoDetailView` so the Connections panel can
    /// live beside the note's NavigationStack instead of under its toolbar.
    @State private var paneMemoID: UUID?
    @State private var showPaneThread = false
    @ObservedObject private var lockGate = LockGate.shared
    /// The two column toggles (iPad regular width, Tuur 2026-07-23): hide the notes
    /// list, hide Connections, or both — "sometimes I just want to focus on writing
    /// and I don't want any distractions". Remembered between launches.
    @AppStorage("ipadListVisible") private var listVisible = true
    @AppStorage("ipadConnectionsVisible") private var connectionsVisible = true
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic
    /// ⌘F focuses the Notes search field. The shared `SearchField` component
    /// can't carry a focus binding, so the field is inlined below (`searchField`)
    /// with this state; `SearchFocusBridge` posts the request from `.commands`.
    @FocusState private var searchFocused: Bool
    @ObservedObject private var searchFocusBridge = SearchFocusBridge.shared

    private var isRegular: Bool { hSize == .regular }

    var body: some View {
        if isRegular {
            // iPad regular width (m1): list column ↔ note page. The sidebar is
            // the phone's entire Notes surface verbatim; the detail pane is the
            // note, or a quiet placeholder.
            NavigationSplitView(columnVisibility: $columnVisibility) {
                // Wrapped in a NavigationStack like the detail's `noteStack`: a
                // split-view column hosted RAW keeps its (hidden) navigation bar's
                // ~50pt reserved at the top — the dead band above "Notes" Tuur hit
                // on device. A NavigationStack collapses that hidden bar (the phone
                // has always looked right for exactly this reason), so the header
                // hugs the top, level with the note bar and Connections.
                NavigationStack { notesRoot }
                    .navigationSplitViewColumnWidth(
                        min: 320, ideal: Adaptive.listColumnWidth, max: 420)
                    // iPadOS adds its OWN sidebar toggle the moment the column
                    // hides — two buttons doing one job. Ours stays (it sits with
                    // the Connections toggle as a pair).
                    .toolbar(removing: .sidebarToggle)
            } detail: {
                detailPane
                    .toolbar(removing: .sidebarToggle)
            }
            .navigationSplitViewStyle(.balanced)
            // The list column follows the toolbar toggle (and vice versa, so the
            // system's own drag/edge-swipe keeps the icon honest).
            .onAppear { columnVisibility = listVisible ? .doubleColumn : .detailOnly }
            .onChange(of: listVisible) { _, show in
                columnVisibility = show ? .doubleColumn : .detailOnly
            }
            .onChange(of: columnVisibility) { _, mode in
                let shown = mode != .detailOnly
                if shown != listVisible { listVisible = shown }
            }
            // Screenshot rig (`-selectFirstMemo`): deterministically fill the
            // detail pane so the m3 layout renders without a tap.
            .onAppear {
                if LaunchFlags.selectFirstMemo, selectedMemoID == nil {
                    selectedMemoID = memos.first(where: { $0.deletedAt == nil })?.id
                }
            }
        } else {
            // Phone (and iPad compact / Split View): today's stack, byte-for-byte.
            NavigationStack(path: $path) {
                notesRoot
                    .navigationDestination(for: UUID.self) { MemoDetailView(initialID: $0) }
            }
        }
    }

    /// The Notes surface — header + list + bottom chrome + every sheet / cover /
    /// handler that hangs off it. Hosted directly in the `NavigationStack` on
    /// compact, and as the `NavigationSplitView` sidebar column at regular width.
    /// The ONLY per-branch difference is `.navigationDestination` (compact only),
    /// kept out here.
    private var notesRoot: some View {
        ZStack(alignment: .bottom) {
                Color.skBg.ignoresSafeArea()

                VStack(spacing: 0) {
                    if isRegular { macStyleHeader } else { headerRow }
                    if memos.isEmpty {
                        // No list to scroll — the card sits pinned here.
                        ContinueListeningCard(openPlayer: { showBookPlayer = true })
                            .padding(.horizontal, 16)
                            .padding(.bottom, 2)
                        emptyState
                    } else {
                        listContent
                    }
                }

                if editMode.isEditing {
                    selectionBar
                } else {
                    // ONE bottom row (Option A, mocks/notes-bottom-chrome.html):
                    // compact book pill left (session-gated) + record right —
                    // explicitly side by side so they can never overlap (the
                    // build-40 regression: a tab-level safeAreaInset never
                    // propagated into this NavigationStack on iOS 26 and the
                    // capsule buried the record button). At regular width this
                    // row rides INSIDE the sidebar column (capture is a
                    // list-side act; the reading pane stays calm — m1).
                    NotesBottomChrome {
                        intentBridge.clearPendingStart()
                        showRecord = true
                    }
                }
            }
            // Compact header (mock notes-compact-header.html, 2026-07-07): the
            // stock toolbar + large-title rows are replaced by ONE hand-rolled
            // header line (~44pt returned to content). Root-only — pushed
            // detail views keep their own nav bars.
            .toolbar(.hidden, for: .navigationBar)
            // Screenshot rig (`-showFilterSheet`) — on notesRoot so it fires for
            // BOTH the phone (NavigationStack) and the iPad (split view).
            .onAppear { if LaunchFlags.showFilterSheet { showSortFilter = true } }
            .overlay(alignment: .top) {
                // Import pill outranks the transient sync banner (both are rare;
                // the drain runs at foreground before sync chatter starts).
                if drainState.pendingCount > 0 {
                    importPendingPill
                } else {
                    syncBannerView
                }
            }
            .animation(Theme.Motion.spring, value: syncBanner)
            .animation(Theme.Motion.spring, value: drainState.pendingCount)
            // Record presentation is an idiom fact (BASE law): a centered card
            // sheet on iPad (m7 — the room stays visible behind it), a full-screen
            // cover on the phone. Memo detail is the split-view detail pane at
            // regular width, so `.navigationDestination` lives on the compact
            // branch only (see `body`).
            .modifier(RecordPresentation(isPresented: $showRecord, isPad: Adaptive.isPadIdiom) {
                RecordView(onSaved: { newID in openMemo(newID) })
            })
            .fullScreenCover(isPresented: $showBookPlayer) {
                AudiobookPlayerView()
            }
            .onChange(of: intentBridge.startRequestID) { handleStartRequest() }
            .onChange(of: memoOpen.requestID) { handleOpenRequest() }
            // Also catch a request that fired during a COLD launch (App Intent /
            // widget / deep link / shared video) BEFORE this view subscribed —
            // onChange alone misses it, which left Siri/widget "opens but doesn't
            // record" and a shared video not opening on a cold launch.
            .onAppear {
                handleStartRequest(); handleOpenRequest()
                // Round-2 evidence for the invisible doc-scan button: was the
                // capability gate the culprit, or the iOS-26 toolbar?
                DevLog.log("docScan: isSupported=\(DocScanView.isSupported)")
            }
            // Round-3 evidence for "photo search finds nothing": per query,
            // how many memos match at all, and how many via photo OCR text —
            // separates 'Vision read nothing' from 'search doesn't match'.
            // DEBUG-only: the photoHits corpus scan fed a log line that never
            // prints in Release, but the scan itself ran there per keystroke.
            #if DEBUG
            .onChange(of: search) { _, q in
                let query = q.trimmingCharacters(in: .whitespaces).lowercased()
                guard !query.isEmpty else { return }
                let photoHits = memos.filter {
                    $0.metadata?.imageManifest?.contains {
                        $0.text?.lowercased().contains(query) == true
                    } == true
                }.count
                DevLog.log("search '\(query)' → \(filtered.count)/\(memos.count) hits, \(photoHits) via photoText")
            }
            #endif
            .sheet(isPresented: $showSortFilter) {
                SortFilterSheet(sort: $sort, filter: $filter, showNotRated: !isRegular)
            }
            // A sheet rather than a push: the stack's path is typed [UUID] for
            // memo detail, which a non-memo destination can't join. (Settings +
            // the audiobook Library moved out to root tabs — see AppTabView.)
            // D8: Files import (audio + video) — routes through the same
            // AppURLHandler path as open-in/AirDrop: video → strip audio +
            // frame, audio → transcribed memo, both jump to the new note.
            .fileImporter(isPresented: $showMediaFileImporter,
                          allowedContentTypes: [.audio, .movie],
                          allowsMultipleSelection: true) { result in
                if case .success(let urls) = result {
                    for url in urls { AppURLHandler.handle(url) }
                }
            }
            .sheet(isPresented: $showVideoImporter) {
                VideoImportPicker { id in
                    showVideoImporter = false
                    if let id { MemoOpenBridge.shared.open(id) }
                }
            }
            // ⌘F (SkriftApp `.commands`) posts here → focus the Notes search field.
            .onChange(of: searchFocusBridge.focusRequestID) { searchFocused = true }
    }

    /// The split-view detail pane at regular width: the selected note (wrapped in
    /// its own `NavigationStack` so its toolbar renders — the split view only
    /// *instantiates* `MemoDetailView`, DETAIL owns its internals), or a quiet
    /// placeholder. `.id(id)` remounts per selection so `MemoDetailView`'s
    /// `initialID`-seeded state actually re-seeds when you pick another note.
    private var detailPane: some View {
        // Note stack | Connections panel as SIBLINGS: the panel must live outside
        // the note's NavigationStack, or the note's floating toolbar capsule spans
        // the panel's column too (Tuur, live iPad round 2026-07-23).
        HStack(spacing: 0) {
            noteStack
            if connectionsVisible, let memo = paneMemo, !lockGate.isLocked(memo) {
                ConnectionsPanel(
                    memo: memo,
                    onOpenMemo: { id in
                        guard memos.contains(where: { $0.id == id }) else { return }
                        withAnimation(Theme.Motion.snappy) { selectedMemoID = id }
                    },
                    onViewThread: { showPaneThread = true })
            }
        }
        .sheet(isPresented: $showPaneThread) {
            if let memo = paneMemo { ThreadView(seedID: memo.id) }
        }
        .onChange(of: selectedMemoID) { _, new in if new == nil { paneMemoID = nil } }
    }

    /// The memo the detail pane is currently showing (the pager can swipe past the
    /// row you tapped) — published up by `MemoDetailView`.
    private var paneMemo: Memo? { memos.first { $0.id == paneMemoID } }

    private var noteStack: some View {
        NavigationStack {
            if let id = selectedMemoID {
                MemoDetailView(initialID: id, paneMemoID: $paneMemoID,
                               listVisible: $listVisible, connectionsVisible: $connectionsVisible)
                    .id(id)
            } else {
                ZStack {
                    Color.skBg.ignoresSafeArea()
                    Text("Select a note")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.skTextDim)
                }
                .toolbar(.hidden, for: .navigationBar)
                .accessibilityIdentifier("ipad-detail-placeholder")
            }
        }
    }

    /// Route a memo-open to the active navigation model: the detail pane at
    /// regular width (iPad split view), a reset push on the stack at compact.
    /// (Row taps append instead — see `listContent`.)
    private func openMemo(_ id: UUID) {
        if isRegular { selectedMemoID = id } else { path = [id] }
    }

    // MARK: - Content

    /// The Notes search field. A faithful inline copy of the shared `SearchField`
    /// (same tokens, same `memo-search` id) — reproduced here ONLY because that
    /// component (DesignSystem/Components.swift, read-only this wave) exposes no
    /// focus binding, and ⌘F needs `.focused($searchFocused)` on the TextField.
    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 14)).foregroundStyle(Color.skTextFaint)
            TextField("", text: $search, prompt: Text(SharedCopy.searchPlaceholder).foregroundStyle(Color.skTextFaint))
                .font(.system(size: 14)).foregroundStyle(Color.skText).tint(.skAccent)
                .autocorrectionDisabled()
                .focused($searchFocused)
                .accessibilityIdentifier("memo-search")
            if !search.isEmpty {
                Button { search = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Color.skTextFaint) }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(Color.skSurface, in: .rect(cornerRadius: Theme.Radius.field, style: .continuous))
        .overlay(RoundedRectangle.sk(Theme.Radius.field).stroke(Color.skBorder, lineWidth: 1))
    }

    private var listContent: some View {
        VStack(spacing: 0) {
            searchField
                .sheet(item: $reminderMemo) { memo in
                    ReminderSheet(memo: memo) { NotesRepository.shared.save() }
                }
                .fullScreenCover(isPresented: $showDocScanner) {
                    DocScanView(
                        onScan: { pages in
                            showDocScanner = false
                            Task {
                                if let id = await DocScanner.save(pages: pages,
                                                                  repository: NotesRepository.shared) {
                                    MemoOpenBridge.shared.open(id)
                                }
                            }
                        },
                        onCancel: { showDocScanner = false }
                    )
                    .ignoresSafeArea()
                }
                .alert("Already in your vault", isPresented: $lockVaultNotice) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text("This note was published to Obsidian before you locked it. Skrift never deletes vault files — remove it there if you want it gone. New publishes will skip it.")
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 6)

            // ONE derived pass for the whole body eval — the per-row flatIndex
            // access used to re-run the entire filter+sort each time (O(N²)).
            let d = derived
            // Same rule for the backlink scan (never per row) — feeds the
            // Mac-parity clock line on unrated rows.
            let backlinked = MemoLifecycle.backlinkedIDs(in: memos)
            // The Mac sidebar's triage line (regular only): chips carry membership
            // (the count line is the two ACTIONABLE numbers — ready to review · to
            // process — with the sort control trailing, exactly like the Mac). The
            // chips themselves ride in `macStyleHeader` above, under search.
            if isRegular { macTriageLine }
            // Native List → reliable swipe-to-delete (.swipeActions) + native
            // multi-select (EditMode + selection binding, incl. drag-over-rows).
            // Plain style + cleared backgrounds keep the custom card look.
            List(selection: $selected) {
                // The continue-card is the FIRST ROW — content under the pinned
                // search bar, scrolling away with the notes (device round 5,
                // build 49: pinned-above-search read as stuck chrome). Renders
                // nothing while a session is live / dismissed today / no book.
                ContinueListeningCard(openPlayer: { showBookPlayer = true })
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 8, trailing: 16))
                ForEach(d.groups, id: \.title) { group in
                    Section {
                        ForEach(group.memos) { memo in
                            MemoRow(memo: memo, fading: searchFadingIDs.contains(memo.id),
                                    clockLine: clockLine(for: memo, backlinked: backlinked),
                                    quiet: isUnratedLive(memo),
                                    quietLine: quietTriageLine(for: memo, backlinked: backlinked),
                                    selected: memo.id == selectedMemoID) {
                                // Opening a SEARCH RESULT carries the query
                                // along — the note flashes where it matched
                                // (text range, or the photo whose OCR hit).
                                let q = search.trimmingCharacters(in: .whitespaces)
                                if !q.isEmpty { SearchHitBridge.pending = (memo.id, q) }
                                // Regular width (iPad split view) drives the detail
                                // pane; compact pushes onto the stack as before.
                                if isRegular { selectedMemoID = memo.id }
                                else { path.append(memo.id) }
                            }
                                .tag(memo.id)
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                                .accessibilityIdentifier("memo-row-\(d.flatIndex[memo.id] ?? 0)")
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) { deleteMemo(memo) } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                    .accessibilityIdentifier("swipe-delete-button")
                                }
                                // Quick copy without opening the memo (today: open → ⋯ →
                                // Copy). Leading edge so Delete keeps the trailing edge +
                                // full swipe to itself.
                                .swipeActions(edge: .leading) {
                                    Button { copyTranscript(memo) } label: {
                                        Label("Copy", systemImage: "doc.on.doc")
                                    }
                                    .tint(.skAccent)
                                    .accessibilityIdentifier("swipe-copy-button")
                                }
                                .contextMenu {
                                    // Second path to the same actions; empty while
                                    // selecting so long-press can't fight multi-select.
                                    if !editMode.isEditing {
                                        Button { reminderMemo = memo } label: {
                                            Label("Remind me…", systemImage: "bell")
                                        }
                                        .accessibilityIdentifier("context-remind-button")
                                        Button { toggleLock(memo) } label: {
                                            Label(memo.locked ? "Remove Lock" : "Lock Note",
                                                  systemImage: memo.locked ? "lock.open" : "lock")
                                        }
                                        .accessibilityIdentifier("context-lock-button")
                                        Button { copyTranscript(memo) } label: {
                                            Label("Copy transcript", systemImage: "doc.on.doc")
                                        }
                                        .accessibilityIdentifier("context-copy-button")
                                        Button(role: .destructive) { deleteMemo(memo) } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                                }
                        }
                    } header: {
                        Text(group.title.uppercased())
                            .font(.system(size: 11.5, weight: .bold))
                            .kerning(0.5)
                            .foregroundStyle(Color.skTextDim)
                    }
                }
                if d.groups.isEmpty && d.related.isEmpty {
                    Text("No matches")
                        .font(.subheadline)
                        .foregroundStyle(Color.skTextDim)
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .padding(.top, 60)
                }
                // P8: semantic "Related" under the exact matches — appears only
                // when the journal index is active (or -mockJournalIndex) and
                // something clears the floor; passes the same filter sheet.
                if !d.related.isEmpty {
                    Section {
                        ForEach(d.related) { memo in
                            MemoRow(memo: memo, selected: memo.id == selectedMemoID) {
                                if isRegular { selectedMemoID = memo.id }
                                else { path.append(memo.id) }
                            }
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                        }
                    } header: {
                        HStack(spacing: 6) {
                            Text("RELATED")
                                .font(.system(size: 11.5, weight: .bold))
                                .kerning(0.5)
                                .foregroundStyle(Color.skTextDim)
                            Text("similar in meaning")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.skTextFaint)
                        }
                        .accessibilityIdentifier("related-section-header")
                    }
                }
                Color.clear.frame(height: 80)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            // Room for the bottom chrome row (pill + record): the row spans the
            // full width now, so without this the LAST card could never scroll
            // clear of it.
            .contentMargins(.bottom, 84, for: .scrollContent)
            // Device finding 2026-07-07 (build 40): no way to close the keyboard
            // after searching — swipe the list to dismiss it.
            .scrollDismissesKeyboard(.immediately)
            // ROUND-5 FIX: was `.task(id: search)` — on device, the ticking
            // mini-player churns the List's identity every frame, restarting
            // the task ~15×/40ms and cancelling every debounce sleep before
            // the query could run (devlog 11:51:17.934–.976). An @State-held
            // Task survives view-identity churn; only a NEW query cancels it.
            .onChange(of: search) { _, _ in scheduleRelated() }
            .task { scheduleRelated() } // initial (-initialSearch route)
            .environment(\.editMode, $editMode)
            .accessibilityIdentifier("memos-list")
            // Pull-to-refresh: a manual nudge for "show me what synced" — runs the
            // materialize/merge sweeps so any rows/blobs that arrived from another
            // device land now (CloudKit's own server pull stays system-scheduled, but
            // push makes that prompt anyway). Clearer than the Mac sync button.
            .refreshable {
                AssetMaterializer.run(repository)
                NamesCloudSync.run(repository)
                VocabularyCloudSync.run(repository)
                await AudiobookCloudSync.reconcile(repository: repository)
                try? await Task.sleep(for: .milliseconds(400))
            }
            // CloudKit sync indicator: a floating capsule anchored at the BOTTOM (over
            // the list's empty tail, never over the notes at the top — the earlier
            // top-overlay covered the first row), fading in/out. The monitor debounces
            // the signal so it doesn't flicker during CloudKit's event bursts.
            .overlay(alignment: .bottom) {
                if cloudSync.isSyncing {
                    HStack(spacing: 7) {
                        ProgressView().controlSize(.mini)
                        Text("Syncing with iCloud…").font(.caption)
                    }
                    .foregroundStyle(Color.skTextDim)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(Color.skElev))
                    .overlay(Capsule().stroke(Color.skBorder, lineWidth: 1))
                    .padding(.bottom, 14)
                    .transition(.opacity)
                    .accessibilityIdentifier("cloud-sync-indicator")
                }
            }
            .animation(.easeInOut(duration: 0.2), value: cloudSync.isSyncing)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 0) {
            ContentUnavailableView(
                "No notes yet",
                systemImage: "waveform",
                description: Text("Tap the mic to record your first note.")
            )
            .accessibilityIdentifier("memos-empty")
        }
    }


    // MARK: - Toolbar

    /// ONE header line: "Notes" 30pt + Select · scan · filter inline right
    /// (mock notes-compact-header.html — the stock toolbar row above the large
    /// title was pure cost). The iOS-26 "second trailing toolbar item gets
    /// eaten" gotcha (build-35 probe) doesn't apply to a hand-rolled HStack,
    /// so doc-scan rejoins the actions cluster.
    /// iPad-regular header — the MAC's construction (signed mock A, section 0;
    /// Tuur: the Mac "just looks way better"): a compact identity line instead of
    /// the 30pt wordmark that sat too low, the day's two verbs as real buttons
    /// (Import · Process N, the pile's size ON the button), then search, the
    /// filter chips and the count/sort line. Compact width keeps the phone's own
    /// header below, untouched.
    private var macStyleHeader: some View {
        VStack(spacing: 7) {
            HStack(spacing: 8) {
                Text(SharedCopy.notesTitle)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.skText)
                Spacer(minLength: 0)
                Button(editMode.isEditing ? "Done" : "Select") {
                    withAnimation(Theme.Motion.snappy) {
                        if editMode.isEditing { editMode = .inactive; selected.removeAll() }
                        else { editMode = .active }
                    }
                }
                .font(.system(size: 13))
                .tint(.skAccent)
                .accessibilityIdentifier("select-button")
                // The Filter control moved DOWN to the triage line (one button
                // owns sort + filter; Tuur 2026-07-23: "we don't need the
                // redundancy"). The identity row is just Notes + Select now.
            }

            HStack(spacing: 7) {
                // Import IS the picker chooser now (Tuur: "when you click import
                // you should see if you want files or video from photos").
                Menu {
                    Button { showMediaFileImporter = true } label: {
                        Label("Audio or video from Files", systemImage: "folder")
                    }
                    Button { showVideoImporter = true } label: {
                        Label("Video from Photos", systemImage: "photo.on.rectangle")
                    }
                    if DocScanView.isSupported {
                        Button { showDocScanner = true } label: {
                            Label("Scan a document", systemImage: "doc.viewfinder")
                        }
                    }
                } label: {
                    Label(SharedCopy.importVerb, systemImage: "plus")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Color.skText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(Color.skElev, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .accessibilityIdentifier("ipad-import-button")

                // "Process N" — the Mac's button, ported whole: N is the pile a
                // polisher would pick up (ProcessPile.waiting — RATED and not yet
                // written back), and pressing it RUNS that pile here. It exists
                // only where this device can actually process; the unrated pile
                // has its own tap target on the count line below (they are
                // different piles: one waits on a model, one waits on Tuur).
                if PolishCenter.shared.isAvailable {
                    if let run = PolishCenter.shared.pileRun {
                        Button { PolishCenter.shared.cancelPile() } label: {
                            HStack(spacing: 6) {
                                ProgressView(value: run.fraction)
                                    .progressViewStyle(.linear)
                                    .frame(width: 54)
                                    .tint(.white)
                                Text(run.line)
                                    .font(.system(size: 11.5, weight: .semibold))
                                    .lineLimit(1)
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background(Color.skAccent, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("ipad-process-pile-running")
                        .accessibilityLabel("\(run.line). Tap to stop.")
                    } else {
                        Button { PolishCenter.shared.processPile(processPile) } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "play.fill").font(.system(size: 10, weight: .bold))
                                Text(SharedCopy.processVerb).font(.system(size: 12.5, weight: .semibold))
                                if !processPile.isEmpty {
                                    Text("\(processPile.count)")
                                        .font(.system(size: 12, weight: .bold).monospacedDigit())
                                        .opacity(0.8)
                                }
                            }
                            .lineLimit(1)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background(Color.skAccent.opacity(processPile.isEmpty ? 0.4 : 1),
                                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(processPile.isEmpty)
                        .accessibilityIdentifier("ipad-process-pile-button")
                    }
                }
            }

            filterChips
        }
        .padding(.horizontal, 14)
        .padding(.top, 4)
        .padding(.bottom, 2)
    }

    /// The Mac sidebar's chip row (All / Needs Work / Done / Unrated), verbatim
    /// idiom — one `QueueFilter`, the shared word set. Selecting a chip filters
    /// the list (`matchesFilter`); the Unrated chip carries the not-rated number.
    private var filterChips: some View {
        HStack(spacing: 5) {
            ForEach(QueueFilter.allCases, id: \.self) { chip in
                let on = listChip == chip
                // The Mac's chip, opacity-for-opacity (Tuur, 2026-07-23: the Mac's
                // chips "just look better") — accent text on accent@0.14, no count
                // on the chip (the number lives in the triage line, like the Mac).
                Text(chip.rawValue)
                    .font(.system(size: 11))
                    .lineLimit(1).fixedSize()
                    .foregroundStyle(on ? Color.skAccent : Color.skTextDim)
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(on ? Color.skAccent.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6)
                        .stroke(on ? Color.skAccent.opacity(0.22) : .clear, lineWidth: 1))
                    .contentShape(Rectangle())
                    .onTapGesture { withAnimation(Theme.Motion.snappy) { listChip = chip } }
                    .accessibilityIdentifier("ipad-chip-\(chip.rawValue)")
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 2)
    }

    /// The Mac's triage line: the two actionable counts + the sort cycle. Counts
    /// are over ALL live notes (not the filtered view), like the Mac's sidebar.
    private var macTriageLine: some View {
        HStack(spacing: 0) {
            // Under the Unrated chip the line becomes the not-rated count (the
            // number the chip used to carry) — the Mac's own branch.
            if listChip == .notRated {
                Text("\(unratedCount) not rated")
                    .foregroundStyle(Color.skTextDim).fontWeight(.semibold)
            } else {
                Text("\(readyToReviewCount) ready to review")
                    .foregroundStyle(Color.skAccentText).fontWeight(.semibold)
                if toProcessCount > 0 {
                    Text(" · \(toProcessCount) to process").foregroundStyle(Color.skTextFaint)
                }
            }
            Spacer(minLength: 6)
            // ONE control: sort + filter behind a single button (Tuur
            // 2026-07-23: collapse the inline "Newest" and the ⋯ — "we don't
            // need the redundancy"). Opens the sheet, which carries Sort AND the
            // metadata filters; the Unrated chip already owns "not rated".
            Button { showSortFilter = true } label: {
                HStack(spacing: 4) {
                    Image(systemName: "line.3.horizontal.decrease").font(.system(size: 10, weight: .semibold))
                    Text("Filter").font(.system(size: 10.5, weight: .medium))
                }
                .foregroundStyle(filter.isActive ? Color.skAccent : Color.skTextDim)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .fixedSize()
            .accessibilityIdentifier("ipad-filter-button")
        }
        .font(.system(size: 11))
        .lineLimit(1)
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
        .accessibilityIdentifier("ipad-triage-count-line")
    }

    /// Processed notes ready to read (rated + a `MemoEnhancement` with content).
    private var readyToReviewCount: Int {
        ProcessPile.done(memos: memos, enhancedIDs: enhancedMemoIDs).count
    }

    /// The pile a polisher would pick up — the SAME count the Process button
    /// shows, so the two never disagree.
    private var toProcessCount: Int { processPile.count }

    /// Live notes that carry no rating — the pile waiting on TUUR, not on a
    /// model (the count line's tap target).
    private var unratedCount: Int { ProcessPile.unrated(memos: memos).count }

    /// The pile a polisher would pick up, by the shared rule. Built off ONE
    /// enhancements query rather than a fetch per memo (body-safe).
    private var processPile: [Memo] {
        ProcessPile.waiting(memos: memos, enhancedIDs: enhancedMemoIDs)
    }

    private var enhancedMemoIDs: Set<UUID> {
        Set(enhancements.lazy.filter(\.hasContent).map(\.memoID))
    }

    private var headerRow: some View {
        HStack(spacing: 18) {
            ScreenTitle("Notes")
            Spacer(minLength: 0)
            Button(editMode.isEditing ? "Done" : "Select") {
                withAnimation(Theme.Motion.snappy) {
                    if editMode.isEditing { editMode = .inactive; selected.removeAll() }
                    else { editMode = .active }
                }
            }
            .font(.system(size: 16))
            .tint(.skAccent)
            .accessibilityIdentifier("select-button")
            if !editMode.isEditing {
                // D8: import media into Skrift without the share sheet — a Files
                // picker (audio + video) and the Photos video picker.
                Menu {
                    Button { showMediaFileImporter = true } label: {
                        Label("Audio or video from Files", systemImage: "folder")
                    }
                    Button { showVideoImporter = true } label: {
                        Label("Video from Photos", systemImage: "photo.on.rectangle")
                    }
                } label: {
                    Image(systemName: "square.and.arrow.down").font(.system(size: 17))
                }
                .tint(.skAccent)
                .accessibilityIdentifier("import-media-button")
                if DocScanView.isSupported {
                    // Scan a paper document → PDF capture (chunk 9). No sim
                    // camera → the button honestly disappears there.
                    Button { showDocScanner = true } label: {
                        Image(systemName: "doc.viewfinder").font(.system(size: 17))
                    }
                    .tint(.skAccent)
                    .accessibilityIdentifier("doc-scan-button")
                }
                Button { showSortFilter = true } label: {
                    Image(systemName: filter.isActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease")
                        .font(.system(size: 17))
                }
                .tint(.skAccent)
                .accessibilityIdentifier("sort-filter-button")
                // (The ⋯ shelf entry lived here 2026-07-18 → 2026-07-21. Q-placement
                // pick B, mocks/wayout-phone-placement.html: the conveyor's one home
                // is the Review feed now — same room as the Mac.)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    // MARK: - Bottom bars

    /// "Importing N share(s)…" — visible only while the drainer is copying inbox
    /// blobs (A14). Same capsule styling as the sync banner so the top edge stays
    /// one visual language.
    private var importPendingPill: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(drainState.pendingCount == 1 ? "Importing share…"
                 : "Importing \(drainState.pendingCount) shares…")
        }
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(Color.skText)
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(Color.skElev, in: .capsule)
        .overlay(Capsule().stroke(Color.skBorder, lineWidth: 1))
        .padding(.top, 6)
        .transition(.move(edge: .top).combined(with: .opacity))
        .accessibilityIdentifier("import-pending-pill")
    }

    @ViewBuilder private var syncBannerView: some View {
        if let syncBanner {
            Text(syncBanner)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.skText)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Color.skElev, in: .capsule)
                .overlay(Capsule().stroke(Color.skBorder, lineWidth: 1))
                .padding(.top, 6)
                .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    /// Show the top banner briefly. The token keeps an earlier banner's expiry
    /// from clipping a newer one.
    private func flashBanner(_ text: String) {
        bannerToken += 1
        let token = bannerToken
        syncBanner = text
        Task {
            try? await Task.sleep(for: .seconds(2.2))
            if bannerToken == token { syncBanner = nil }
        }
    }

    /// Present the recorder + auto-start for a Record intent / widget / deep link.
    /// `lastHandledStart` makes it fire once per request and catches a request that
    /// arrived during a cold launch before `.onChange` was subscribed.
    private func handleStartRequest() {
        guard intentBridge.startRequestID > lastHandledStart else { return }
        lastHandledStart = intentBridge.startRequestID
        // Just present — RecordView consumes the bridge's pending start once it's
        // foreground-active (no stale-flag propagation through the cover).
        showRecord = true
    }

    /// A shared video imported on foreground → open it. It relocates to the
    /// video's filming date, so it'd otherwise vanish from the top of the list;
    /// resetting the path to it (like the record-saved path) lands the user on it.
    private func handleOpenRequest() {
        if let id = memoOpen.consume() { openMemo(id) }
    }

    // (recordFAB moved into NotesBottomChrome — the Option-A split row at the
    // bottom of this file.)

    private var selectionBar: some View {
        HStack {
            Text("\(selected.count) selected").font(.subheadline.weight(.semibold)).foregroundStyle(Color.skTextDim)
            Spacer()
            Button(role: .destructive, action: deleteSelected) {
                Label("Delete", systemImage: "trash")
            }
            .disabled(selected.isEmpty)
            .accessibilityIdentifier("delete-selected-button")
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
        .background(.ultraThinMaterial)
        .clipShape(.rect(topLeadingRadius: 20, topTrailingRadius: 20))
    }

    // MARK: - Actions

    private func deleteSelected() {
        for id in selected {
            guard let memo = memos.first(where: { $0.id == id }) else { continue }
            deleteMemo(memo)
        }
        selected.removeAll()
        editMode = .inactive
    }

    /// Quick copy straight from the list: transcript (fallback: title) → pasteboard,
    /// with a light haptic + the same top banner as sync. An empty memo says so
    /// instead of silently copying nothing.
    /// Lock (instant; honesty copy lives on the detail page too) / remove lock
    /// (requires auth — Apple Notes idiom). Locking an already-published memo
    /// surfaces the vault notice; Skrift never deletes vault files.
    private func toggleLock(_ memo: Memo) {
        if memo.locked {
            Task {
                guard await LockGate.shared.authorizeRemoveLock() else { return }
                memo.locked = false
                memo.markEdited()
                NotesRepository.shared.save()
            }
        } else {
            guard LockGate.shared.canAuthenticate() else { return }
            memo.locked = true
            memo.markEdited()
            NotesRepository.shared.save()
            if ExportStateStore.shared.record(for: memo.id) != nil { lockVaultNotice = true }
        }
    }

    private func copyTranscript(_ memo: Memo) {
        guard let text = memo.copyableText else {
            flashBanner("Nothing to copy yet")
            return
        }
        UIPasteboard.general.string = text
        Haptics.tap(.light)
        flashBanner("Copied")
    }

    /// Soft-delete: move the memo to Recently Deleted (audio + sidecars stay on
    /// disk so Restore is lossless; purged for good after ~2 weeks at startup).
    /// Shared by multi-select delete, swipe-to-delete, and the context menu.
    private func deleteMemo(_ memo: Memo) {
        repository.softDelete(memo)
    }

    // MARK: - Derived

    /// How close a note's fade must be before the notebook mentions it.
    private static let fadeWarningDays = 7

    /// Unrated-live = the quiet FADE, every width (m1b B + Tuur's 2026-07-23
    /// phone extension — his flow rates important notes AT capture, so an
    /// unrated row genuinely means untriaged, not fresh: "when I take a note
    /// that I know is important I give it a score straight away"). Rating IS
    /// the flag (no Flag verb anywhere, same correction as the Mac's m6 peek);
    /// tap opens the note, whose Importance circles are the rating surface.
    private func isUnratedLive(_ memo: Memo) -> Bool {
        memo.significance == 0 && memo.deletedAt == nil && !memo.locked
    }

    /// The quiet row's ALWAYS-ON spine line — triage surfaces only (iPad
    /// regular; the Mac list has its own). The phone notebook keeps the
    /// urgency-only amber `clockLine` below instead: fade = the universal
    /// signal, the standing line = triage-bench detail.
    private func quietTriageLine(for memo: Memo, backlinked: Set<UUID>, now: Date = Date()) -> String? {
        guard isRegular, isUnratedLive(memo) else { return nil }
        return MemoSpine.oneLiner(for: MemoSpine.station(for: .from(memo, backlinked: backlinked), now: now), now: now)
    }

    /// Urgency-only clock line (⏱ eyeball wave 2, 2026-07-22; asymmetry
    /// REVISED 2026-07-23 — the fade above now runs on every width): the line
    /// appears (amber) only when the clock actually matters — fading starts
    /// within `fadeWarningDays`, or the note is already fading (a search hit).
    private func clockLine(for memo: Memo, backlinked: Set<UUID>, now: Date = Date()) -> String? {
        guard memo.significance == 0, memo.deletedAt == nil, !memo.locked else { return nil }
        let station = MemoSpine.station(for: .from(memo, backlinked: backlinked), now: now)
        switch station {
        case .fading:
            return MemoSpine.oneLiner(for: station, now: now)
        case .new(let fadesAt):
            let warnAt = fadesAt.addingTimeInterval(-Double(Self.fadeWarningDays) * 86_400)
            return now >= warnAt ? MemoSpine.oneLiner(for: station, now: now) : nil
        default:
            return nil
        }
    }

    /// The lifecycle split (MemoLifecycle, 2026-07-17): fading notes leave the
    /// main LIST — but not SEARCH (no-bad-info, 2026-07-21): "no results" about
    /// a note that exists-and-is-recoverable is the worst possible answer to
    /// "where did my note go?". A fading search hit wears an amber tag.
    private var lifecycle: (live: [Memo], fading: [Memo]) { MemoLifecycle.partition(memos) }

    private var searchingNow: Bool { !search.trimmingCharacters(in: .whitespaces).isEmpty }

    private var filtered: [Memo] {
        // Built ONCE per body eval — the chip predicate needs it per row, and a
        // per-row rebuild would be O(N·E) (the frozen-library trap in miniature).
        let enhanced = enhancedMemoIDs
        var out = lifecycle.live.filter { matchesSearch($0) && matchesFilter($0, enhanced: enhanced) }
        if searchingNow {
            out += lifecycle.fading.filter { matchesSearch($0) && matchesFilter($0, enhanced: enhanced) }
        }
        return out.sorted(by: sortComparator)
    }

    /// Ids of fading notes currently surfaced by search — drives the row tag.
    private var searchFadingIDs: Set<UUID> {
        guard searchingNow else { return [] }
        return Set(lifecycle.fading.map(\.id))
    }

    private struct Group { let title: String; let memos: [Memo] }

    /// Everything the list body derives from one filter+sort pass. These were
    /// separate computed properties, and the per-ROW `flatIndex` access re-ran
    /// the whole filter+sort (metadata decodes included) once per visible row.
    private struct Derived { let groups: [Group]; let flatIndex: [UUID: Int]; let related: [Memo] }

    private var derived: Derived {
        let f = filtered
        return Derived(
            groups: groups(from: f),
            flatIndex: Dictionary(f.enumerated().map { ($0.element.id, $0.offset) },
                                  uniquingKeysWith: { a, _ in a }),
            related: relatedDisplay(excluding: Set(f.map(\.id))))
    }

    private func groups(from filtered: [Memo]) -> [Group] {
        if sort == .longest {
            return filtered.isEmpty ? [] : [Group(title: "Longest first", memos: filtered)]
        }
        var order: [String] = []
        var bucket: [String: [Memo]] = [:]
        for memo in filtered {
            let key = MemoDate.group(groupDate(memo))
            if bucket[key] == nil { order.append(key); bucket[key] = [] }
            bucket[key]?.append(memo)
        }
        return order.map { Group(title: $0, memos: bucket[$0] ?? []) }
    }


    private func matchesSearch(_ memo: Memo) -> Bool {
        memo.matches(query: search)
    }

    /// The rendered Related section: raw semantic hits minus exact matches,
    /// passed through the same filter sheet as everything else.
    private func relatedDisplay(excluding exact: Set<UUID>) -> [Memo] {
        guard !related.isEmpty else { return [] }
        let enhanced = enhancedMemoIDs
        return related.filter { !exact.contains($0.id) && matchesFilter($0, enhanced: enhanced) }
    }

    /// Debounced semantic lookup for the current query (P8). Exact matches
    /// never wait on this — it fills the Related section in async.
    private func scheduleRelated() {
        // Engine load starts at the FIRST keystroke, not after the debounce —
        // a cold load is minutes on device (devlog 2026-07-08), so every
        // head-start counts. No-op when warm or when the index is off.
        if !search.isEmpty { JournalIndexService.shared.warmUp() }
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            await refreshRelated()
        }
    }

    private func refreshRelated() async {
        let q = search.trimmingCharacters(in: .whitespaces)
        // Round-5 trace: device searches produced ZERO SemanticSearch lines
        // while sweeps ran fine — log the entry + every gate's verdict.
        if !q.isEmpty {
            let service = JournalIndexService.shared
            DevLog.log("refreshRelated '\(q.prefix(30))' active=\(service.isActive) enabled=\(service.isEnabled) model=\(GemmaEmbedder.isModelDownloaded)")
        }
        guard !q.isEmpty, JournalIndexService.shared.isActive else {
            if !related.isEmpty { related = [] }
            return
        }
        let scores = await JournalIndexService.shared.searchScores(q, repository: repository)
        guard !Task.isCancelled, q == search.trimmingCharacters(in: .whitespaces) else { return }
        let byID = Dictionary(memos.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        related = JournalIndexService.relatedResults(scores: scores, excluding: [], memosByID: byID)
    }

    private func matchesFilter(_ memo: Memo, enhanced: Set<UUID>) -> Bool {
        // The Mac's triage chip (regular width only). `.all` is a no-op, so
        // compact and the phone are untouched (listChip stays .all there).
        if isRegular && !ProcessPile.matches(listChip, memo, enhancedIDs: enhanced) { return false }
        if filter.unsyncedOnly && memo.syncStatus == .synced { return false }
        if filter.hasPhotosOnly && memo.thumbnailPhotoFilename == nil { return false }
        if filter.notRatedOnly && (memo.significance > 0 || memo.locked) { return false }
        if let place = filter.place, memo.metadata?.location?.placeName != place { return false }
        if filter.from != nil || filter.to != nil {
            let d = filter.dateField == .added ? memo.addedAt : memo.recordedAt
            if !DateRangeFilter.contains(d, from: filter.from, to: filter.to) { return false }
        }
        return true
    }

    private func sortComparator(_ a: Memo, _ b: Memo) -> Bool {
        switch sort {
        case .added:  return a.addedAt > b.addedAt
        case .edited: return a.lastEditedAt > b.lastEditedAt
        case .recent: return a.recordedAt > b.recordedAt
        case .oldest: return a.recordedAt < b.recordedAt
        case .longest: return a.duration > b.duration
        }
    }

    /// The date a memo is grouped under (day-headers), matching the active sort so
    /// the headers and the order agree.
    private func groupDate(_ memo: Memo) -> Date {
        switch sort {
        case .added:  return memo.addedAt
        case .edited: return memo.lastEditedAt
        default:      return memo.recordedAt   // recent / oldest (longest = single group)
        }
    }
}

// MARK: - Row

/// A memo row: taps open detail in normal mode; in EditMode the tap is left to the
/// List so its native multi-select (incl. drag-over-rows) and selection circle work.
/// Conditionally attaching the tap (rather than guarding inside it) is what frees the
/// tap for List selection — a no-op gesture would still swallow it. No NavigationLink,
/// so no disclosure chevron over the card.
private struct MemoRow: View {
    let memo: Memo
    var fading: Bool = false
    var clockLine: String? = nil
    /// Unrated-live fade (every width — see MemoCard.quiet).
    var quiet: Bool = false
    /// The always-on spine line, triage surfaces (iPad regular) only.
    var quietLine: String? = nil
    /// iPad split view (m1): the row backing the detail pane wears `skAccentSoft`.
    /// Always false on the phone (`selectedMemoID` is nil there).
    var selected: Bool = false
    let onTap: () -> Void
    @Environment(\.editMode) private var editMode

    var body: some View {
        if editMode?.wrappedValue.isEditing == true {
            // Multi-select uses the List's own selection chrome — no detail-pane
            // highlight while editing.
            MemoCard(memo: memo, fading: fading, clockLine: clockLine,
                     quiet: quiet, quietLine: quietLine)
        } else {
            // A Button, NOT .onTapGesture: a tap gesture on a List row fights
            // the context-menu lift on iOS 26 — a long-press just started the
            // row drifting as if scrolling and the menu never opened (device
            // round 1). The system resolves Button-tap vs long-press-menu vs
            // scroll natively.
            Button(action: onTap) {
                MemoCard(memo: memo, fading: fading, clockLine: clockLine,
                         quiet: quiet, quietLine: quietLine, selected: selected)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Card

private struct MemoCard: View {
    let memo: Memo
    /// Surfaced by SEARCH while fading — wears the honest amber tag.
    var fading: Bool = false
    /// The urgency-only clock line ("starts fading 28 Jul" / "moves to
    /// Recently Deleted in 3d"), computed once at the list level (backlink
    /// scan is never per-row). Non-nil ⇒ the clock is short ⇒ amber.
    var clockLine: String? = nil
    /// Unrated-live fade (m1b B + Tuur's 2026-07-23 phone extension: "when I
    /// take a note that I know is important I give it a score straight away" —
    /// so unrated genuinely means untriaged, on EVERY width): the row dims and
    /// wears the hollow ○ (the unfilled significance circles' own idiom).
    /// Rating the note IS the flag — no Flag verb anywhere.
    var quiet: Bool = false
    /// The spine one-liner a quiet row carries on TRIAGE surfaces only (iPad
    /// regular; the Mac list has its own) — the phone notebook keeps its
    /// urgency-only amber `clockLine` instead. Faint, not amber: quiet ≠
    /// urgent; a present status pill outranks it in the slot.
    var quietLine: String? = nil
    /// iPad split view (m1): the selected row (its note is in the detail pane)
    /// gets an accent-soft fill. Always false on the phone.
    var selected: Bool = false

    private var isQuiet: Bool { quiet }

    var body: some View {
        HStack(spacing: 11) {
            // C3 share-item captures: link/text/image glyph (per mock state 2)
            if memo.isShareCapture {
                captureGlyph
            // Audiobook captures wear a book glyph as their source icon
            // (mock state 5; detected via the C2 book metadata).
            } else if memo.isBookCapture {
                bookGlyph
            // Video imports wear a video glyph (the trailing frame thumbnail means
            // "has an image"; this leading glyph means "source: video").
            } else if memo.isVideoImport {
                videoGlyph
            // Plain voice memos (the default) wear a mic — so EVERY row carries a
            // source glyph, matching the Mac's sidebar (user call 2026-06-15).
            } else {
                voiceGlyph
            }

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    // fixedSize: the stamp was wrapping to two lines ("Yesterday ·"
                    // / "14:00") once the status pill shared the row in the iPad's
                    // narrower column (2026-07-23 shot).
                    Text(MemoDate.label(memo.recordedAt))
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(Color.skTextFaint)
                        .lineLimit(1)
                        .fixedSize()
                    if let clockLine {
                        Text("· \(clockLine)")
                            .font(.system(size: 11.5))
                            .foregroundStyle(Color.skAmber.opacity(0.9))
                            .lineLimit(1)
                    } else if let quietLine, memo.statusKind == nil {
                        // The status pill outranks the quiet spine line in this
                        // slot (Error/Transcribing is the more urgent story, and
                        // both together overcrowd the row — 2026-07-23 shot).
                        Text("· \(quietLine)")
                            .font(.system(size: 11.5))
                            .foregroundStyle(Color.skTextFaint)
                            .lineLimit(1)
                    }
                    Spacer()
                    statusPill
                }

                // Locked notes: title + 🔒 only — the preview never shows
                // (chunk 8). Content requires Face ID on the detail page.
                if memo.locked {
                    HStack(spacing: 6) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.skTextDim)
                        Text(memo.title?.isEmpty == false ? memo.title! : "Locked note")
                            .font(.system(size: 14.5, weight: .semibold))
                            .foregroundStyle(Color.skText)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 6)
                    .accessibilityIdentifier("locked-row-title")
                // C3 share-item captures lead with the resolved title (urlTitle /
                // text snippet / "Image") and the annotation as the secondary line.
                // They never have a voice transcript, so the standard snippet path
                // is bypassed entirely.
                } else if memo.isShareCapture {
                    Text(memo.shareCaptureTitle)
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundStyle(Color.skText)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 6)
                        .accessibilityIdentifier("capture-row-title")

                    if let snippet = memo.shareCaptureSnippet {
                        Text(snippet)
                            .font(.system(size: 12.5, weight: .regular))
                            .foregroundStyle(Color.skTextDim)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 2)
                    }
                // Titled memos lead with the user-set title; the transcript snippet
                // drops to a dimmer second line. Untitled memos keep the
                // transcript-first behaviour. Audiobook captures lead with the
                // quote — italic, accent-❝, per the signed-off mock — and the
                // ramble as the dim second line; a phone-set title still wins
                // the top line, with the quote taking the secondary line.
                } else if hasTitle {
                    HStack(spacing: 6) {
                        Text(memo.displayTitle)
                            .font(.system(size: 14.5, weight: .semibold))
                            .foregroundStyle(Color.skText)
                            .lineLimit(1)
                            .multilineTextAlignment(.leading)
                        if fading {
                            Text("fading")
                                .font(.system(size: 9.5, weight: .semibold))
                                .foregroundStyle(Color.skAmber)
                                .padding(.horizontal, 6).padding(.vertical, 1.5)
                                .background(Color.skAmber.opacity(0.13), in: Capsule())
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 6)

                    if memo.isBookCapture, let quote = memo.quoteSnippet {
                        quoteText(quote)
                            .font(.system(size: 12.5, weight: .regular))
                            .foregroundStyle(Color.skTextDim)
                            .lineLimit(1)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 2)
                    } else if let secondary = transcriptSnippet {
                        Text(secondary)
                            .font(.system(size: 12.5, weight: .regular))
                            .foregroundStyle(Color.skTextDim)
                            .lineLimit(1)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 2)
                    }
                } else if memo.isBookCapture, let quote = memo.quoteSnippet {
                    quoteText(quote)
                        .font(.system(size: 14.5, weight: .medium))
                        .foregroundStyle(Color.skText)
                        .lineLimit(1)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 6)

                    if let ramble = memo.rambleSnippet {
                        Text(ramble)
                            .font(.system(size: 12.5, weight: .regular))
                            .foregroundStyle(Color.skTextDim)
                            .lineLimit(1)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 2)
                    }
                } else {
                    Text(snippet)
                        .font(.system(size: 14.5, weight: .medium))
                        .foregroundStyle(hasTranscript ? Color.skText : Color.skTextFaint)
                        .italic(!hasTranscript)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 6)
                }

                FlowLayout(spacing: 5, lineSpacing: 5) {
                    ForEach(chips, id: \.self) { chip in
                        ContextChip(text: chip.text, systemImage: chip.symbol)
                            // FlowLayout measures children at their IDEAL width, so
                            // an uncapped chip (a long book title) grows past the
                            // card and clips off-screen. The cap turns overflow into
                            // tail-truncation — ContextChip's Text already has
                            // lineLimit(1) + .tail; short chips keep their ideal
                            // width (maxWidth never stretches under FlowLayout).
                            .frame(maxWidth: 220, alignment: .leading)
                    }
                    ForEach(memo.tags.prefix(2), id: \.self) { tag in
                        Text("#\(tag)")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.skAccentText)
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Color.skAccentSoft, in: .rect(cornerRadius: 7, style: .continuous))
                    }
                }
                .padding(.top, 9)
            }

            if hasPhoto {
                RoundedRectangle.sk(11)
                    .fill(LinearGradient(colors: [Color(hex: 0x2b3350), Color(hex: 0x1a1f33)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 48, height: 48)
                    .overlay(memo.locked ? nil : photoThumb)
                    .overlay(RoundedRectangle.sk(11).stroke(Color.skBorder, lineWidth: 1))
            }

            // m1b B: the hollow circle — the unfilled significance circles' own
            // idiom (the Mac quiet row's exact glyph). Rate the note to fill it.
            if isQuiet {
                Image(systemName: "circle")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.skTextFaint.opacity(0.8))
            }
        }
        .opacity(isQuiet ? 0.55 : 1)
        .modifier(SelectableCard(selected: selected))
        // Accessibility identifier for capture rows (used by UI tests and the
        // detail "capture-link-card" test). The existing "memo-row-N" id remains
        // on the ForEach wrapper; this adds the semantic capture identifier.
        .accessibilityIdentifier(memo.isShareCapture ? "capture-row" : "memo-card")
    }

    // A failed on-device transcription is informational, not a dead end: the memo
    // syncs as raw audio (the Mac transcribes it) and can be hand-edited in detail.
    // `statusKind` is nil for phone-only (significance 0) memos → no sync pill.
    @ViewBuilder private var statusPill: some View {
        if let kind = memo.statusKind {
            StatusPill(style: kind.pillStyle, label: kind.label)
        }
    }

    /// Leading source icon for C3 share-item captures (link/text/image glyph per
    /// the mock's `.mrow .ic`). Uses the same 32×32 rounded-rect as `bookGlyph`.
    private var captureGlyph: some View {
        RoundedRectangle.sk(10)
            .fill(Color.skElev)
            .frame(width: 32, height: 32)
            .overlay(
                Image(systemName: memo.shareCaptureGlyph)
                    .font(.system(size: 14))
                    .foregroundStyle(Color.skTextDim)
            )
            .accessibilityIdentifier("capture-row-glyph")
    }

    /// Leading source icon for plain voice memos (the default) — a neutral mic, so
    /// every row carries a source glyph like the Mac sidebar.
    private var voiceGlyph: some View {
        RoundedRectangle.sk(10)
            .fill(Color.skElev)
            .frame(width: 32, height: 32)
            .overlay(
                Image(systemName: "mic.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.skTextDim)
            )
            .accessibilityIdentifier("voice-row-glyph")
    }

    /// Leading source icon for video imports (a neutral film glyph, matching the
    /// share-capture source-glyph family — same 32×32 rounded-rect).
    private var videoGlyph: some View {
        RoundedRectangle.sk(10)
            .fill(Color.skElev)
            .frame(width: 32, height: 32)
            .overlay(
                Image(systemName: SourceKind.video.glyph)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.skTextDim)
            )
            .accessibilityIdentifier("video-row-glyph")
    }

    /// Leading source icon for audiobook capture rows (accent-tinted book, per
    /// the mock's `.mrow.cap .ic`).
    private var bookGlyph: some View {
        RoundedRectangle.sk(10)
            .fill(Color.skAccentSoft)
            .frame(width: 32, height: 32)
            .overlay(
                Image(systemName: SourceKind.audiobookQuote.glyph)
                    .font(.system(size: 14))
                    .foregroundStyle(Color.skAccent)
            )
    }

    /// "❝ quote" — accent, heavy quote mark + italic body. The caller sets the
    /// line's base font/color, which the explicitly-styled ❝ keeps overriding.
    private func quoteText(_ quote: String) -> Text {
        Text("❝ ").foregroundStyle(Color.skAccent).fontWeight(.heavy)
            + Text(quote).italic()
    }

    @ViewBuilder private var photoThumb: some View {
        // Downsampled + cached decode (MemoImageLoader is the "600× with a
        // picture" fix from the editor) — a full-res UIImage here decoded the
        // whole photo at compositing time for a 48pt tile, per row, uncached.
        if let filename = memo.thumbnailPhotoFilename,
           let img = MemoImageLoader.thumbnail(at: AppPaths.recordingsDirectory.appendingPathComponent(filename), maxWidth: 96) {
            Image(uiImage: img).resizable().scaledToFill()
                .frame(width: 48, height: 48)
                .clipShape(.rect(cornerRadius: 11, style: .continuous))
        } else {
            Image(systemName: "photo").font(.system(size: 16)).foregroundStyle(Color.skTextFaint)
        }
    }

    private struct Chip: Hashable { let text: String; let symbol: String? }

    private var chips: [Chip] {
        var out: [Chip] = []
        // C3 share-item captures show a type label + optional domain instead of duration.
        if memo.isShareCapture {
            out.append(Chip(text: memo.shareCaptureTypeLabel, symbol: memo.shareCaptureGlyph))
            if let domain = memo.shareCaptureURLDomain {
                out.append(Chip(text: domain, symbol: nil))
            }
            return out
        }
        // Audiobook captures lead the meta line with "Book · ch. N".
        if let book = memo.bookCaptionLabel {
            out.append(Chip(text: book, symbol: SourceKind.audiobookQuote.glyph))
        }
        // Video imports lead the meta line with a "Video" source chip.
        if memo.isVideoImport {
            out.append(Chip(text: SourceKind.video.label, symbol: SourceKind.video.glyph))
        }
        out.append(Chip(text: memo.durationLabel, symbol: nil))
        if let place = memo.metadata?.location?.placeName, !place.isEmpty {
            out.append(Chip(text: place, symbol: "mappin.circle.fill"))
        }
        if let w = memo.metadata?.weather { out.append(Chip(text: "\(w.temperature)°", symbol: "cloud.sun.fill")) }
        return out
    }

    private var hasTranscript: Bool { !(memo.transcript ?? "").isEmpty }
    /// A photo tile shows iff the NOTE visibly carries a photo (deleting every
    /// photo from the body must clear the tile too, not just swap it).
    private var hasPhoto: Bool { memo.thumbnailPhotoFilename != nil }
    /// True when the user gave the memo an explicit (non-blank) title.
    private var hasTitle: Bool {
        !(memo.title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }
    private var snippet: String {
        guard let line = memo.firstTranscriptLine else { return "Voice note" }
        guard let transcript = memo.transcript else { return line }
        // Show the (2-line) transcript, but strip `[[img_NNN]]` markers so the raw
        // marker never reads as the row text — a VIDEO import always opens with
        // `[[img_001]]` (the frame), which otherwise filled the whole snippet.
        let cleaned = transcript
            .replacingOccurrences(of: #"\[\[img_\d+\]\]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\n{2,}"#, with: "\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? line : cleaned
    }
    /// Secondary line for titled rows: the transcript's first line, markers stripped.
    /// Nil when there's no transcript yet (the title alone carries the row).
    private var transcriptSnippet: String? { memo.firstTranscriptLine }
}

// MARK: - Quick copy

extension Memo {
    /// What a quick "Copy" copies: the transcript when there is one, else the
    /// title; nil when the memo has neither (not yet transcribed, untitled).
    var copyableText: String? {
        if let t = transcript, !t.isEmpty { return t }
        if let t = title, !t.isEmpty { return t }
        return nil
    }
}

// MARK: - Sort & Filter sheet

private struct SortFilterSheet: View {
    @Binding var sort: MemoSort
    @Binding var filter: MemoFilter
    /// The Unrated CHIP owns "not rated" at regular width, so the sheet hides that
    /// one toggle on the iPad; the phone (no chips) keeps it. Place + Photos are
    /// gone from BOTH now (Tuur 2026-07-23: "we don't even need to filter by photos
    /// or place" — place lives on the Review screen). Sort + Unsynced + Date on both.
    var showNotRated = true
    @Environment(\.dismiss) private var dismiss

    // Optional-date bindings: a toggle enables the bound (today by default), the
    // DatePicker then adjusts it; toggling off clears back to nil (no filter).
    private var fromEnabled: Binding<Bool> {
        Binding(get: { filter.from != nil },
                set: { filter.from = $0 ? Calendar.current.startOfDay(for: Date()) : nil })
    }
    private var toEnabled: Binding<Bool> {
        Binding(get: { filter.to != nil }, set: { filter.to = $0 ? Date() : nil })
    }
    private var fromBinding: Binding<Date> {
        Binding(get: { filter.from ?? Date() }, set: { filter.from = $0 })
    }
    private var toBinding: Binding<Date> {
        Binding(get: { filter.to ?? Date() }, set: { filter.to = $0 })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Sort") {
                    Picker("Sort", selection: $sort) {
                        ForEach(MemoSort.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                Section("Filter") {
                    if showNotRated {
                        Toggle("Not rated", isOn: $filter.notRatedOnly)
                            .accessibilityIdentifier("filter-notrated")
                    }
                    Toggle("Unsynced only", isOn: $filter.unsyncedOnly)
                        .accessibilityIdentifier("filter-unsynced")
                }
                Section {
                    Picker("Date field", selection: $filter.dateField) {
                        ForEach(MemoDateField.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("filter-date-field")
                    Toggle("From", isOn: fromEnabled)
                    if filter.from != nil {
                        DatePicker("From date", selection: fromBinding, displayedComponents: .date)
                            .labelsHidden()
                    }
                    Toggle("To", isOn: toEnabled)
                    if filter.to != nil {
                        DatePicker("To date", selection: toBinding, displayedComponents: .date)
                            .labelsHidden()
                    }
                } header: {
                    Text("Date")
                } footer: {
                    Text("Filter by when each note was \(filter.dateField == .added ? "added to Skrift" : "recorded").")
                }
                if filter.isActive {
                    Button("Clear filters", role: .destructive) { filter = MemoFilter() }
                }
            }
            .navigationTitle("Sort & Filter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.accessibilityIdentifier("sortfilter-done")
                }
            }
        }
        // Bigger than the cramped medium box (Tuur 2026-07-23: "this could be
        // bigger… doesn't have to be this weird small shape").
        .presentationDetents([.large])
    }
}

// MARK: - Bottom chrome (Option A — mocks/notes-bottom-chrome.html)

/// The Notes bottom row: compact book pill LEFT (only while a book session is
/// active) + the record button RIGHT — one 60pt row, explicitly side by side so
/// the two can never stack or overlap (the build-40 regression). No session →
/// just the record button in the right corner. Its own view so only IT
/// re-renders on the session's 2 Hz playback ticks, never the memos list.
private struct NotesBottomChrome: View {
    let onRecord: () -> Void
    @ObservedObject private var session = AudiobookSession.shared
    /// Mirror of the continue-card's dismissal day: starting a book VOIDS a
    /// ×-for-today (re-engagement rule, device round 4). It lives HERE because
    /// this view stays mounted while the card's List row comes and goes.
    @AppStorage("continueCardDismissedDay") private var cardDismissedDay = ""

    var body: some View {
        // 16pt pill↔record gap (V2a "real air" — Henry's separation note).
        HStack(spacing: 16) {
            if session.isActive {
                AudiobookMiniPill()
                    .frame(maxWidth: .infinity)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                Spacer(minLength: 0)
            }
            recordButton
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
        .animation(Theme.Motion.spring, value: session.isActive)
        .onChange(of: session.isActive) { _, active in
            if active {
                DevLog.log("bottomChrome void — session active, clearing cardDismissedDay (was '\(cardDismissedDay)')")
                cardDismissedDay = ""
            }
        }
    }

    private var recordButton: some View {
        Button(action: onRecord) {
            Image(systemName: "mic.fill")
                .font(.system(size: 23))
                .foregroundStyle(.white)
                .frame(width: 60, height: 60)
                .background(Color.skRed, in: .circle)
                .overlay(Circle().stroke(.white.opacity(0.12), lineWidth: 4))
                .shadow(color: .skRed.opacity(0.45), radius: 12, y: 8)
        }
        .accessibilityIdentifier("new-recording-button")
    }
}

// MARK: - iPad shell helpers

/// A memo card's background. Identical to `.skCard()` when unselected (so the
/// phone — where `selected` is never true — is byte-for-byte unchanged); an
/// accent-soft fill + accent hairline when it backs the split-view detail pane
/// (m1). Kept local (not folded into `.skCard()`) because that shared helper is
/// read-only this wave.
private struct SelectableCard: ViewModifier {
    let selected: Bool
    func body(content: Content) -> some View {
        content
            .padding(Theme.Space.cardPadding)
            .background(selected ? Color.skAccentSoft : Color.skSurface,
                        in: .rect(cornerRadius: Theme.Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle.sk(Theme.Radius.card)
                    .stroke(selected ? Color.skAccent.opacity(0.5) : Color.skBorder, lineWidth: 1)
            )
    }
}

/// Record presentation, per BASE's idiom rule: a centered card **sheet** on iPad
/// (m7 — `.presentationSizing(.form)`, the room stays dimmed-but-visible behind
/// it), a full-screen **cover** on the phone. Swapping the modifier type needs a
/// ViewModifier (an `if` in a chain can't).
private struct RecordPresentation<Presented: View>: ViewModifier {
    @Binding var isPresented: Bool
    let isPad: Bool
    @ViewBuilder var presented: () -> Presented

    func body(content: Content) -> some View {
        Group {
            if isPad {
                content.sheet(isPresented: $isPresented) {
                    presented().presentationSizing(.form)
                }
            } else {
                content.fullScreenCover(isPresented: $isPresented, content: presented)
            }
        }
    }
}

/// One-shot ⌘F seam: `SkriftApp`'s `.commands` calls `requestFocus()`, and
/// `MemosListView` observes the bump to move keyboard focus into its search
/// field (the shared `SearchField` can't carry a focus binding). Mirrors the
/// `RecordingIntentBridge` singleton pattern.
final class SearchFocusBridge: ObservableObject {
    static let shared = SearchFocusBridge()
    private init() {}
    @Published private(set) var focusRequestID = 0
    func requestFocus() { focusRequestID += 1 }
}
