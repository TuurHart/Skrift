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
    var place: String?
    /// Optional date-range filter, applied to either the recorded or added date.
    var dateField: MemoDateField = .recorded
    var from: Date?
    var to: Date?
    var isActive: Bool { unsyncedOnly || hasPhotosOnly || place != nil || from != nil || to != nil }
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
    @Query(filter: #Predicate<Memo> { $0.deletedAt != nil }) private var trashedMemos: [Memo]
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
    @State private var showWayOut = false
    /// Last shelf visit — the ⋯ dot lights only for fade-entries newer than this.
    @AppStorage("fadingLastSeenAt") private var fadingLastSeenTs: Double = 0
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
    @State private var editMode: EditMode = .inactive
    @State private var selected: Set<UUID> = []
    @State private var syncBanner: String?
    @State private var bannerToken = 0

    var body: some View {
        NavigationStack(path: $path) {
            ZStack(alignment: .bottom) {
                Color.skBg.ignoresSafeArea()

                VStack(spacing: 0) {
                    headerRow
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
                    // capsule buried the record button).
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
            .navigationDestination(for: UUID.self) { MemoDetailView(initialID: $0) }
            .fullScreenCover(isPresented: $showRecord) {
                RecordView(onSaved: { newID in path = [newID] })
            }
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
                SortFilterSheet(sort: $sort, filter: $filter, places: availablePlaces)
            }
            // A sheet rather than a push: the stack's path is typed [UUID] for
            // memo detail, which a non-memo destination can't join. (Settings +
            // the audiobook Library moved out to root tabs — see AppTabView.)
            .sheet(isPresented: $showWayOut) { WayOutView() }
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
        }
    }

    // MARK: - Content

    private var listContent: some View {
        VStack(spacing: 0) {
            SearchField(text: $search, prompt: "Search transcripts", fieldID: "memo-search")
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
                            MemoRow(memo: memo) {
                                // Opening a SEARCH RESULT carries the query
                                // along — the note flashes where it matched
                                // (text range, or the photo whose OCR hit).
                                let q = search.trimmingCharacters(in: .whitespaces)
                                if !q.isEmpty { SearchHitBridge.pending = (memo.id, q) }
                                path.append(memo.id)
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
                            MemoRow(memo: memo) { path.append(memo.id) }
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
                // The merged shelf (Q4, 2026-07-20 — mocks/lifecycle-ia-explorations.html):
                // Fading + Recently Deleted collapsed into ONE "On its way out" surface
                // behind this ⋯; the amber dot is the "something is fading" honesty signal.
                Menu {
                    Button { showWayOut = true } label: {
                        Label("On its way out (\(lifecycle.fading.count + trashedMemos.count))",
                              systemImage: "leaf")
                    }
                } label: {
                    // Dot INSIDE the label bounds (an out-of-frame offset gets
                    // mangled square by the menu-source preview snapshot —
                    // 2026-07-18 device finding) + one flattened layer.
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "ellipsis.circle").font(.system(size: 17))
                        // Unread semantics (2026-07-18): lit only when something
                        // ENTERED fading since the shelf was last opened — a
                        // steady trickle would otherwise keep it on forever.
                        if lifecycle.fading.contains(where: {
                            MemoLifecycle.fadeEntersAt($0).timeIntervalSince1970 > fadingLastSeenTs
                        }) {
                            Circle().fill(Color.skAmber).frame(width: 6, height: 6)
                        }
                    }
                    .frame(width: 26, height: 24, alignment: .center)
                    .compositingGroup()
                    .contentShape(Rectangle())
                }
                .tint(.skAccent)
                .accessibilityIdentifier("notes-menu-wayout")
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
        if let id = memoOpen.consume() { path = [id] }
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

    /// The lifecycle split (MemoLifecycle, 2026-07-17): fading notes leave the
    /// main list + search entirely; the ⋯ shelf is their only surface.
    private var lifecycle: (live: [Memo], fading: [Memo]) { MemoLifecycle.partition(memos) }

    private var filtered: [Memo] {
        lifecycle.live.filter { matchesSearch($0) && matchesFilter($0) }.sorted(by: sortComparator)
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

    private var availablePlaces: [String] {
        Array(Set(memos.compactMap { $0.metadata?.location?.placeName }.filter { !$0.isEmpty })).sorted()
    }

    private func matchesSearch(_ memo: Memo) -> Bool {
        memo.matches(query: search)
    }

    /// The rendered Related section: raw semantic hits minus exact matches,
    /// passed through the same filter sheet as everything else.
    private func relatedDisplay(excluding exact: Set<UUID>) -> [Memo] {
        guard !related.isEmpty else { return [] }
        return related.filter { !exact.contains($0.id) && matchesFilter($0) }
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

    private func matchesFilter(_ memo: Memo) -> Bool {
        if filter.unsyncedOnly && memo.syncStatus == .synced { return false }
        if filter.hasPhotosOnly && memo.thumbnailPhotoFilename == nil { return false }
        if let place = filter.place, memo.metadata?.location?.placeName != place { return false }
        if filter.from != nil || filter.to != nil {
            let cal = Calendar.current
            let d = filter.dateField == .added ? memo.addedAt : memo.recordedAt
            if let from = filter.from, d < cal.startOfDay(for: from) { return false }
            if let to = filter.to,
               let end = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: to)),
               d >= end { return false }   // inclusive of the whole 'to' day
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
    let onTap: () -> Void
    @Environment(\.editMode) private var editMode

    var body: some View {
        if editMode?.wrappedValue.isEditing == true {
            MemoCard(memo: memo)
        } else {
            // A Button, NOT .onTapGesture: a tap gesture on a List row fights
            // the context-menu lift on iOS 26 — a long-press just started the
            // row drifting as if scrolling and the menu never opened (device
            // round 1). The system resolves Button-tap vs long-press-menu vs
            // scroll natively.
            Button(action: onTap) {
                MemoCard(memo: memo)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Card

private struct MemoCard: View {
    let memo: Memo

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
                    Text(MemoDate.label(memo.recordedAt))
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(Color.skTextFaint)
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
                    Text(memo.displayTitle)
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundStyle(Color.skText)
                        .lineLimit(1)
                        .multilineTextAlignment(.leading)
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
        }
        .skCard()
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
                Image(systemName: "video.fill")
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
                Image(systemName: "book.closed.fill")
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
            out.append(Chip(text: book, symbol: "book.closed.fill"))
        }
        // Video imports lead the meta line with a "Video" source chip.
        if memo.isVideoImport {
            out.append(Chip(text: "Video", symbol: "video.fill"))
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
    let places: [String]
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
                    Toggle("Unsynced only", isOn: $filter.unsyncedOnly)
                        .accessibilityIdentifier("filter-unsynced")
                    Toggle("Has photos", isOn: $filter.hasPhotosOnly)
                    if !places.isEmpty {
                        Picker("Place", selection: $filter.place) {
                            Text("Any").tag(String?.none)
                            ForEach(places, id: \.self) { Text($0).tag(String?.some($0)) }
                        }
                    }
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
        .presentationDetents([.medium])
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
