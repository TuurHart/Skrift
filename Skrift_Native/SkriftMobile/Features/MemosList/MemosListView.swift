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
    /// C98: every device's latest words per note. A change here (a head synced in, a pick
    /// made anywhere) recomputes which notes carry the "2 versions" pill — once, here.
    @Query private var editHeads: [MemoEditHead]
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
    /// The note shown in the workbench pane at regular width. nil on the
    /// phone (compact pushes onto `path` instead), so the whole pane path is a
    /// no-op there.
    @State private var selectedMemoID: UUID?
    /// The two panel toggles (iPad regular width, Tuur 2026-07-23): hide the notes
    /// list, hide Connections, or both — "sometimes I just want to focus on writing
    /// and I don't want any distractions". Remembered between launches. This is
    /// the single source of truth for the list column's width — the ONE pinned
    /// ◧ overlay drives it (no split-view `columnVisibility` shadow state — that
    /// binding was the 129 unreliability). Connections is no longer a bound
    /// column: it's MemoDetailView's own per-note visitor sheet (signed
    /// 2026-07-24), so `ipadConnectionsVisible` is retired.
    @AppStorage("ipadListVisible") private var listVisible = true
    /// ⌘F focuses the Notes search field. The shared `SearchField` component
    /// can't carry a focus binding, so the field is inlined below (`searchField`)
    /// with this state; `SearchFocusBridge` posts the request from `.commands`.
    @FocusState private var searchFocused: Bool
    @ObservedObject private var searchFocusBridge = SearchFocusBridge.shared

    private var isRegular: Bool { hSize == .regular }

    var body: some View {
        if isRegular {
            // iPad regular width — the rebuilt stacking (mock
            // ipad-note-chrome-belongs.html, 2026-07-24): ONE flat HStack we
            // own — list (a sliding SURFACE) + note (paper). Connections is no
            // longer a column at all; it's the note's own per-note visitor
            // sheet. `listVisible` is the only layout state, driven by the ONE
            // screen-pinned ◧ overlay; one `withAnimation` moves the list.
            HStack(spacing: 0) {
                // Wrapped in a NavigationStack: hosted RAW, the column keeps a
                // hidden navigation bar's ~50pt reserved at the top — the dead
                // band above "Notes" Tuur hit on device. A NavigationStack
                // collapses that hidden bar (the phone has always looked right
                // for exactly this reason). Fixed at the phone canvas width —
                // the split view's 320–420 drag-resize goes away with it, and
                // with it the squeezed narrow-list rows. Width-collapsed (not
                // removed) so the sheets/covers hanging off `notesRoot` (record,
                // importers) keep presenting while the list is hidden.
                NavigationStack { notesRoot }
                    // The divider hairline sits INSIDE the sliding window so it
                    // clips away with the column instead of ghosting at x=0.
                    .overlay(alignment: .trailing) {
                        Rectangle().fill(Color.skBorder)
                            .frame(width: 0.5).ignoresSafeArea()
                    }
                    .slidingColumn(width: Adaptive.listColumnWidth,
                                   open: listVisible, edge: .leading)
                    // The slide window's .clipped() cuts the column's own
                    // safe-area bleed → black bands above/below the list (Tuur,
                    // live round b130). Paint the SURFACE bleed OUTSIDE the clip;
                    // the window's 0-width collapse takes it along.
                    .background(Color.skSurface.ignoresSafeArea(edges: .vertical))
                noteStack
            }
            // ONE screen-pinned ◧ (signed mock ipad-note-chrome-belongs.html):
            // the list toggle lives HERE, above both columns, so it never moves —
            // whichever surface is under it (the list's gray header when open,
            // the note's bar when closed) simply changes hands beneath it, the
            // iPadOS-26 sidebar pattern. It's the only panel glyph on screen.
            .overlay(alignment: .topLeading) {
                PanelToggle(icon: "sidebar.left", on: listVisible,
                            label: listVisible ? "Hide notes list" : "Show notes list",
                            id: "ipad-toggle-list") {
                    withAnimation(Theme.Motion.snappy) { listVisible.toggle() }
                }
                // Centered on the 48pt chrome-bar line (30pt chip → 9pt inset),
                // 14pt from the leading edge — the fixed pixel it holds forever.
                .padding(.leading, 14).padding(.top, 9)
            }
            // The pane never opens EMPTY (Tuur, live round b130: "when you open
            // the app… empty. strange"): no selection → show the newest note.
            // (`-selectFirstMemo` now just names the default behavior.)
            .onAppear {
                if selectedMemoID == nil {
                    selectedMemoID = memos.first?.id
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
    /// compact, and as the sliding list column at regular width.
    /// The ONLY per-branch difference is `.navigationDestination` (compact only),
    /// kept out here.
    private var notesRoot: some View {
        ZStack(alignment: .bottom) {
                // D135/D136 (one-notes-list): the list column's ground is now the
                // phone's grey EVERYWHERE — the iPad's separate white "surface"
                // material is gone ("I like the gray of the iPhone better"); the
                // cards stay white either way (`NoteCardStyle.skrift.surface`),
                // so they now read as cards against a visibly different ground.
                Color.skBg.ignoresSafeArea()

                VStack(spacing: 0) {
                    if isRegular { macStyleHeader } else { headerRow }
                    verbRow
                    if isRegular { processRow }
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
                    // the book pill only now — D136 drops the phone's red mic
                    // corner button too ("reaching up to record is not that bad"),
                    // Record lives ONLY in `verbRow` on every width now.
                    NotesBottomChrome(showRecordButton: false) {
                        intentBridge.clearPendingStart()
                        // PRESTART (2026-07-26): capture begins HERE, at the
                        // button, while the cover is still animating in —
                        // RecordView claims the running service in onAppear.
                        // Tapping record IS the consent to open the mic.
                        LiveRecordingService.prestart()
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
            .onChange(of: editHeads.map { "\($0.memoID)\($0.editedAt.timeIntervalSince1970)" }, initial: true) {
                EditConflictWatch.shared.refresh(in: context)
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

    /// The workbench at regular width: the selected note (which hosts its own
    /// chrome band + Connections visitor sheet — see `MemoDetailView`), or a
    /// quiet placeholder. `.id(id)` remounts per selection so `MemoDetailView`'s
    /// `initialID`-seeded state actually re-seeds when you pick another note.
    /// The ◧ list toggle is the parent HStack's screen-pinned overlay (it
    /// covers this pane too), so neither branch draws its own.
    private var noteStack: some View {
        NavigationStack {
            if let id = selectedMemoID {
                MemoDetailView(initialID: id, listVisible: $listVisible)
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

    /// Route a memo-open to the active navigation model: the workbench pane at
    /// regular width, a reset push on the stack at compact.
    /// (Row taps append instead — see `listContent`.)
    private func openMemo(_ id: UUID) {
        if isRegular { selectedMemoID = id } else { path = [id] }
    }

    /// Create a typed note and open it — the Mac's ✎/⌘N verb, same author
    /// (`Memo.newTyped`: unrated, `.done`, the `"typed"` marker), landing in the
    /// workbench pane where the body editor is the way in.
    private func newTypedNote() {
        guard let memo = try? Memo.newTyped(into: repository.container.mainContext) else { return }
        openMemo(memo.id)
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
            // D136: the triage line is gone on every width — each chip carries
            // its own count now (`chipCounts`), Filter ends the bar. On BOTH
            // widths now (was iPad-regular only) — the phone's chip bar filters
            // the list too.
            filterChips
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
                            MemoRow(memo: memo, enhancedTitle: enhancedTitleByMemoID[memo.id],
                                    fading: searchFadingIDs.contains(memo.id),
                                    clockLine: clockLine(for: memo, backlinked: backlinked),
                                    quiet: isUnratedLive(memo),
                                    // D136 (one-notes-list, Q33 visual check): the iPad's
                                    // always-on "starts fading …" spine line is retired —
                                    // unrated rows show the amber `clockLine` only within
                                    // `fadeWarningDays`, same as the phone, never a standing
                                    // quiet line. Was `quietTriageLine(for:backlinked:)`.
                                    quietLine: nil,
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
                            MemoRow(memo: memo, enhancedTitle: enhancedTitleByMemoID[memo.id],
                                    selected: memo.id == selectedMemoID) {
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
    /// the 30pt wordmark that sat too low, then the Mac sidebar's verb rows
    /// verbatim — Import · Record · ✎ across, Process N full-width below (the
    /// pile's size ON the button) — then search, the filter chips and the
    /// count/sort line. Compact width keeps the phone's own header below,
    /// untouched.
    /// D136 second pass: the iPad-regular identity row is now JUST the title +
    /// Select — the verb row, Process and the chips all moved out into
    /// `notesRoot` so the phone can share them at compact width too.
    private var macStyleHeader: some View {
        HStack(spacing: 8) {
            // 22pt, hugging the top — "the notes title can be bigger, move
            // the whole notes bit up" (Tuur, live round b130).
            Text(SharedCopy.notesTitle)
                .font(.system(size: 22, weight: .bold))
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
        }
        // Clear the screen-pinned ◧ (14 + 30) and sit on the same 48pt line
        // as the note's chrome bar, so the button reads as belonging to this
        // header while the list is open (signed mock ipad-note-chrome-belongs).
        .padding(.leading, 34)
        .frame(height: 48)
        .padding(.horizontal, 14)
    }

    /// The Mac sidebar's verb row, ported whole and now shared by the PHONE too
    /// (D135/D136, Tuur: "just get the same ones… also unify that" — the phone
    /// gains this row and loses its corner FAB): Import (the picker chooser),
    /// Record, and the typed-note ✎ — the two verbs that BRING MATERIAL IN pair
    /// up with typing, the signed mocks mac-record-button.html option B +
    /// mac-new-note.html m2.
    private var verbRow: some View {
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

            // Start a take — the Mac's Record, same shape as Import (they are
            // the same verb family). D136: this replaces the phone's corner FAB
            // too now ("reaching up to record is not that bad").
            Button {
                intentBridge.clearPendingStart()
                LiveRecordingService.prestart()
                showRecord = true
            } label: {
                HStack(spacing: 6) {
                    Circle().fill(Color.skRed).frame(width: 9, height: 9)
                    Text("Record")
                }
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(Color.skRed)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(Color.skElev, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("ipad-record-button")
            .accessibilityLabel("Record a voice memo")

            // A typed note (the Mac's ✎/⌘N, mocks/mac-new-note.html m2):
            // Import and Record name their sources, typing is the third verb —
            // a quiet fixed-width chip, ⌘N on a hardware keyboard.
            Button { newTypedNote() } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.skText)
                    .frame(width: 34)
                    .padding(.vertical, 7)
                    .background(Color.skElev, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .keyboardShortcut("n", modifiers: .command)
            .accessibilityIdentifier("ipad-new-note-button")
            .accessibilityLabel("New note")
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 2)
    }

    /// "Process N" — the Mac's button, ported whole: N is the pile a polisher
    /// would pick up (ProcessPile.waiting), and pressing it RUNS that pile here
    /// — full-width, like the Mac's. Regular width only (D136's mock: the phone
    /// has no Process row in the unified list).
    private var processRow: some View {
        SwiftUI.Group {
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
        .padding(.horizontal, 14)
    }

    /// The Mac sidebar's chip row (All / Needs Work / Done / Unrated), verbatim
    /// idiom — one `QueueFilter`, the shared word set. Selecting a chip filters
    /// the list (`matchesFilter`); D136: each chip now carries ITS OWN count
    /// (the old triage line's numbers moved here) and Filter ends the bar,
    /// icon-only — on the phone too now, not just the iPad.
    private var filterChips: some View {
        HStack(spacing: 5) {
            ForEach(QueueFilter.allCases, id: \.self) { chip in
                let on = listChip == chip
                HStack(spacing: 3) {
                    Text(chip.rawValue)
                    if let n = chipCounts[chip] {
                        Text("\(n)").fontWeight(.semibold)
                    }
                }
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
            // Icon-only Filter (D136: "Filter" the word doesn't fit next to four
            // counted chips) — same identifier as the old header icon so it
            // stays discoverable at the same tap-order spot.
            Button { showSortFilter = true } label: {
                Image(systemName: filter.isActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(filter.isActive ? Color.skAccent : Color.skTextDim)
            .padding(6)
            .background(Color.skElev, in: RoundedRectangle(cornerRadius: 6))
            .accessibilityIdentifier("sort-filter-button")
            .accessibilityLabel("Sort and filter")
        }
        .padding(.horizontal, 16)
        .padding(.top, 2)
        .padding(.bottom, 4)
    }

    /// D135: "each chip counts its own notes" — over ALL live notes (not the
    /// filtered view), like the Mac's sidebar. `.all` carries no number.
    private var chipCounts: [QueueFilter: Int] {
        let enhanced = enhancedMemoIDs
        return NotesListModel.chipCounts(
            needsWork: memos.filter { ProcessPile.matches(.needsWork, $0, enhancedIDs: enhanced) }.count,
            done: memos.filter { ProcessPile.matches(.done, $0, enhancedIDs: enhanced) }.count,
            notRated: ProcessPile.unrated(memos: memos).count)
    }

    /// The pile a polisher would pick up, by the shared rule. Built off ONE
    /// enhancements query rather than a fetch per memo (body-safe).
    private var processPile: [Memo] {
        ProcessPile.waiting(memos: memos, enhancedIDs: enhancedMemoIDs)
    }

    private var enhancedMemoIDs: Set<UUID> {
        Set(enhancements.lazy.filter(\.isProcessed).map(\.memoID))
    }

    /// memoID → the Mac's GENERATED title, off the same one query (never a fetch per row).
    /// Lets a row show a real title where the user hasn't chosen one, instead of falling
    /// through to the body — which is what made the list disagree with the detail screen.
    private var enhancedTitleByMemoID: [UUID: String] {
        Dictionary(enhancements.lazy.compactMap { e -> (UUID, String)? in
            let t = e.title.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : (e.memoID, t)
        }, uniquingKeysWith: { a, _ in a })
    }

    /// D135/D136: the phone's header simplifies to JUST Notes + Select — Import,
    /// Scan and Filter all leave it (Import/Scan fold into the shared `verbRow`'s
    /// Import menu below; Filter moves into the chip bar's icon-only button).
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
            // (The ⋯ shelf entry lived here 2026-07-18 → 2026-07-21. Q-placement
            // pick B, mocks/wayout-phone-placement.html: the conveyor's one home
            // is the Review feed now — same room as the Mac.)
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
            if ObsidianVault.hasPublished(memo.id) { lockVaultNotice = true }
        }
    }

    /// R88: `copyableText` itself refuses a locked, unauthenticated memo — this
    /// just supplies the right banner instead of the generic "nothing to copy".
    private func copyTranscript(_ memo: Memo) {
        guard let text = memo.copyableText else {
            flashBanner(LockGate.shared.isLocked(memo) ? "Locked note" : "Nothing to copy yet")
            return
        }
        UIPasteboard.general.string = text
        Haptics.tap(.light)
        flashBanner("Copied")
    }

    /// Soft-delete: move the memo to Recently Deleted (audio + sidecars stay on
    /// disk so Restore is lossless; purged for good after ~2 weeks at startup).
    /// Shared by multi-select delete, swipe-to-delete, and the context menu —
    /// all three entry points funnel through here, so gating it once (R88)
    /// covers all three: a locked note needs auth first, the same idiom
    /// `toggleLock`'s Remove-Lock path already uses.
    private func deleteMemo(_ memo: Memo) {
        guard LockGate.shared.isLocked(memo) else {
            repository.softDelete(memo)
            return
        }
        Task {
            guard await LockGate.shared.unlock(memo.id) else { return }
            repository.softDelete(memo)
        }
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
        !NoteConsent.isRated(memo) && memo.deletedAt == nil && !memo.locked
    }

    /// Urgency-only clock line (⏱ eyeball wave 2, 2026-07-22; asymmetry
    /// REVISED 2026-07-23 — the fade above now runs on every width): the line
    /// appears (amber) only when the clock actually matters — fading starts
    /// within `fadeWarningDays`, or the note is already fading (a search hit).
    private func clockLine(for memo: Memo, backlinked: Set<UUID>, now: Date = Date()) -> String? {
        guard !NoteConsent.isRated(memo), memo.deletedAt == nil, !memo.locked else { return nil }
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
        // D136: the chip bar filters on EVERY width now (was iPad-regular only —
        // `listChip` stayed `.all` on the phone before, a no-op).
        if !ProcessPile.matches(listChip, memo, enhancedIDs: enhanced) { return false }
        if filter.unsyncedOnly && memo.syncStatus == .synced { return false }
        if filter.hasPhotosOnly && memo.thumbnailPhotoFilename == nil { return false }
        if filter.notRatedOnly && (NoteConsent.isRated(memo) || memo.locked) { return false }
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
    /// The Mac's generated title, when the user hasn't chosen one (display-only).
    var enhancedTitle: String? = nil
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
            MemoCard(memo: memo, enhancedTitle: enhancedTitle, fading: fading, clockLine: clockLine,
                     quiet: quiet, quietLine: quietLine)
        } else {
            // A Button, NOT .onTapGesture: a tap gesture on a List row fights
            // the context-menu lift on iOS 26 — a long-press just started the
            // row drifting as if scrolling and the menu never opened (device
            // round 1). The system resolves Button-tap vs long-press-menu vs
            // scroll natively.
            Button(action: onTap) {
                MemoCard(memo: memo, enhancedTitle: enhancedTitle, fading: fading, clockLine: clockLine,
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
    /// The Mac's generated title, when the user hasn't chosen one (display-only).
    var enhancedTitle: String? = nil
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

    /// m2 adapter (2026-08-19, chunk 2 of the un-twinning): every derivation this
    /// card owned now FEEDS the shared `NoteCardView` instead of a hand-built
    /// layout — the Mac maps its own rows into the same view, so the two lists
    /// cannot drift again ("make sure the ipad also follows that one to the T").
    var body: some View {
        // Q26 fix (BUGS §4): this used to layer .opacity(0.55) OVER NoteCardView's
        // own quiet dim (0.62), so an unrated row read at 0.34 — nearly invisible.
        // `m.quiet` below already drives the ONE dim; this view adds nothing on top.
        NoteCardView(model: cardModel, style: .skrift)
            .accessibilityIdentifier(memo.isShareCapture ? "capture-row" : "memo-card")
    }

    private var cardModel: NoteCardModel {
        var m = NoteCardModel(stamp: MemoDate.label(memo.recordedAt))
        m.fadingLine = clockLine ?? (fading ? "fading" : nil)
        m.quietLine = quietLine
        m.quiet = quiet
        m.selected = selected
        m.locked = memo.locked
        m.balls = memo.locked ? nil : ThreeBallScale.step(for: memo.significance)
        if let kind = memo.statusKind {
            let pillKind: NoteCardModel.Pill.Kind = switch kind {
            case .synced: .done
            case .waiting: .amber
            case .transcribing: .progress
            case .error: .error
            }
            m.statusPill = .init(label: kind.label, kind: pillKind, pulses: kind == .transcribing)
        }
        // D139: two versions outrank every other state in the pill slot.
        if EditConflictWatch.shared.ids.contains(memo.id) { m.statusPill = .twoVersions }
        if memo.locked {
            m.title = memo.title?.isEmpty == false ? memo.title : "Locked note"
            return m   // locked rows show title + 🔒 and NOTHING else
        }
        if memo.isShareCapture {
            m.title = memo.shareCaptureTitle
            m.snippet = memo.shareCaptureSnippet
        } else if hasTitle {
            m.title = memo.displayTitle(enhancedTitle: enhancedTitle)
            if memo.isBookCapture, let quote = memo.quoteSnippet {
                m.quote = quote
            } else {
                m.snippet = transcriptSnippet
            }
        } else {
            if memo.isBookCapture, let quote = memo.quoteSnippet {
                m.quote = quote
                m.snippet = transcriptSnippet
            } else {
                m.snippet = snippet
            }
        }
        m.chips = chips.map { .init(text: $0.text, systemImage: $0.symbol, isTag: false) }
        // Source glyph joins the chips (m2 has no leading glyph column) + the tags.
        if !memo.isShareCapture, !memo.isBookCapture {
            let kind = SourceKind.of(memo)
            if kind != .voiceMemo {
                m.chips.insert(.init(text: kind.label, systemImage: kind.glyph), at: 0)
            }
        }
        for tag in memo.tags ?? [] {
            m.chips.append(.init(text: "#\(tag)", isTag: true))
        }
        if let filename = memo.thumbnailPhotoFilename,
           let img = MemoImageLoader.thumbnail(at: AppPaths.recordingsDirectory.appendingPathComponent(filename), maxWidth: 96) {
            m.thumb = Image(uiImage: img)
        }
        return m
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

    /// Leading source icon for the default branch — taxonomy-derived: mic for a
    /// voice memo, ✎ for a typed note, the note glyph for an Apple Note import
    /// (before 2026-08-18 this was a hardcoded mic, so a typed note wore a mic
    /// and read as a recording it never was).
    private var voiceGlyph: some View {
        RoundedRectangle.sk(10)
            .fill(Color.skElev)
            .frame(width: 32, height: 32)
            .overlay(
                Image(systemName: SourceKind.of(memo).glyph)
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
        // No duration chip on a note that HAS no audio (typed notes, Apple Note
        // imports) — a permanent "0:00" claims a recording that doesn't exist.
        if !memo.audioFilename.isEmpty {
            out.append(Chip(text: memo.durationLabel, symbol: nil))
        }
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
    /// True when this row has a title to lead with — the user's own, else the Mac's
    /// generated one. Without the second arm a polished note showed its title in detail
    /// and its body text in the list.
    private var hasTitle: Bool {
        if !(memo.title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) { return true }
        return !(enhancedTitle?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }
    private var snippet: String {
        // "Note" for a typed note, "Voice note" otherwise — the shared fallback
        // (mocks/mac-new-note.html m3: "Voice note" on something you wrote reads
        // as a bug).
        guard let line = memo.firstTranscriptLine else {
            return SourceKind.of(memo).emptyTitleFallback
        }
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
    /// title; nil when the memo has neither (not yet transcribed, untitled)
    /// OR when it's locked and this session hasn't unlocked it (R88 — Copy is
    /// gated behind auth, C213 — same rule the player's `audioURL` load uses).
    @MainActor
    var copyableText: String? {
        guard !LockGate.shared.isLocked(self) else { return nil }
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
    /// false at iPad-regular width, where Record moved into the header verb row
    /// (2026-08-18) — the row then carries only the book pill (or nothing).
    var showRecordButton = true
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
            if showRecordButton { recordButton }
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

/// The phone/iPad's colors for the shared m2 note card (NoteCardView) — lives here
/// (app target) and NOT in Theme.swift, which the widget/share-extension targets
/// also compile without Shared/UI in their sources.
extension NoteCardStyle {
    static let skrift = NoteCardStyle(
        accent: .skAccent, accentSoft: .skAccentSoft, accentText: .skAccentText,
        text: .skText, textDim: .skTextDim, textFaint: .skTextFaint,
        amber: .skAmber, green: .skGreen, red: .skRed,
        chipFill: .skElev, surface: .skSurface, border: .skBorder)
}
