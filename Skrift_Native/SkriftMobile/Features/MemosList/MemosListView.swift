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
           sort: \Memo.recordedAt, order: .reverse) var memos: [Memo]
    /// ONE query behind the header's "Process N" — which notes already carry
    /// polished content. Per-memo enhancement fetches inside a body are the
    /// frozen-library trap (2026-07-23), so the set is built once here.
    @Query var enhancements: [MemoEnhancement]
    /// C98: every device's latest words per note. A change here (a head synced in, a pick
    /// made anywhere) recomputes which notes carry the "2 versions" pill — once, here.
    @Query var editHeads: [MemoEditHead]
    @Environment(\.modelContext) var context
    let repository = NotesRepository.shared

    @State var path: [NoteRoute] = []
    @State var showRecord = false
    /// Presents the audiobook player for the continue-card's body tap (hoisted
    /// here: a cover on the card itself would die when its List row unmounts).
    @State var showBookPlayer = false
    @State var lastHandledStart = 0
    @State var lastHandledQuickNote = 0
    @ObservedObject var intentBridge = RecordingIntentBridge.shared
    @ObservedObject var memoOpen = MemoOpenBridge.shared
    @ObservedObject var quickNoteBridge = QuickNoteBridge.shared
    /// Long-press → "Remind me…" (chunk 7).
    @State var reminderMemo: Memo?
    /// Locking a memo that's already published → honest notice (chunk 8).
    @State var lockVaultNotice = false
    /// In-app document scan (chunk 9) — device-only entry.
    @State var showDocScanner = false
    /// D8 in-app media import: Files picker (audio + video) and the Photos
    /// video picker — before this there was NO in-app way to import an audio
    /// file at all, and the video picker was built but never wired anywhere.
    @State var showMediaFileImporter = false
    @State var showVideoImporter = false
    @State var showSortFilter = false
    /// Presents WayOutView — the merged Fading + Recently Deleted shelf (Q4,
    /// 2026-07-20). One sheet now instead of two (`showTrash` retired).
    /// Last shelf visit — the ⋯ dot lights only for fade-entries newer than this.
    /// CloudKit (device↔device) sync activity — drives the "Syncing with iCloud…"
    /// strip below the search field. Distinct from the Mac `syncBanner` above.
    @ObservedObject var cloudSync = CloudSyncMonitor.shared
    /// Share-imports being copied out of the inbox (A14) — drives the top pill so
    /// a big shared movie doesn't look like nothing happened until the drain ends.
    @ObservedObject var drainState = CaptureDrainState.shared
    @State var search = LaunchFlags.initialSearch ?? ""
    /// Semantic hits for the current search (P8) — empty unless the journal
    /// index is active AND something clears the floor.
    @State var related: [Memo] = []
    /// Debounced semantic lookup, held in @State so view-identity churn (the
    /// ticking mini-player) can't cancel it — only a newer query does.
    @State var searchTask: Task<Void, Never>?
    @State var sort: MemoSort = .added
    @State var filter = MemoFilter()
    /// The Mac's triage chip, at regular width only (All / Needs Work / Done /
    /// Unrated — shared `QueueFilter`). Compact keeps the phone's funnel sheet.
    @State var listChip: QueueFilter = .all
    @State var editMode: EditMode = .inactive
    @State var selected: Set<UUID> = []
    @State var syncBanner: String?
    @State var bannerToken = 0
    /// iPad wave 1: layout branches on the horizontal size class (NEVER device
    /// idiom — Split View/Stage Manager can make the iPad compact, and compact
    /// must stay the phone layout, pixel-untouched).
    @Environment(\.horizontalSizeClass) var hSize
    /// The note shown in the workbench pane at regular width. nil on the
    /// phone (compact pushes onto `path` instead), so the whole pane path is a
    /// no-op there. Carries its own draft/memo kind (`NoteRoute`, Q47) so
    /// routing can never desync from a separate id.
    @State var selectedRoute: NoteRoute?
    /// Read-only convenience for row-highlight compares, which only ever
    /// care about the raw id.
    var selectedMemoID: UUID? { selectedRoute?.id }
    /// The two panel toggles (iPad regular width, Tuur 2026-07-23): hide the notes
    /// list, hide Connections, or both — "sometimes I just want to focus on writing
    /// and I don't want any distractions". Remembered between launches. This is
    /// the single source of truth for the list column's width — the ONE pinned
    /// ◧ overlay drives it (no split-view `columnVisibility` shadow state — that
    /// binding was the 129 unreliability). Connections is no longer a bound
    /// column: it's MemoDetailView's own per-note visitor sheet (signed
    /// 2026-07-24), so `ipadConnectionsVisible` is retired.
    @AppStorage("ipadListVisible") var listVisible = true
    /// ⌘F focuses the Notes search field. The shared `SearchField` component
    /// can't carry a focus binding, so the field is inlined below (`searchField`)
    /// with this state; `SearchFocusBridge` posts the request from `.commands`.
    @FocusState var searchFocused: Bool
    @ObservedObject var searchFocusBridge = SearchFocusBridge.shared

    var isRegular: Bool { hSize == .regular }

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
                if selectedRoute == nil {
                    selectedRoute = memos.first.map { .existing($0.id) }
                }
            }
        } else {
            // Phone (and iPad compact / Split View): today's stack, byte-for-byte.
            NavigationStack(path: $path) {
                notesRoot
                    .navigationDestination(for: NoteRoute.self) { route in
                        switch route {
                        case .draft(let id):
                            QuickNoteView(draftID: id) {
                                if !path.isEmpty { path.removeLast() }
                            }
                        case .memo(let id):
                            MemoDetailView(initialID: id)
                        }
                    }
            }
        }
    }

    /// The Notes surface — header + list + bottom chrome + every sheet / cover /
    /// handler that hangs off it. Hosted directly in the `NavigationStack` on
    /// compact, and as the sliding list column at regular width.
    /// The ONLY per-branch difference is `.navigationDestination` (compact only),
    /// kept out here.
    var notesRoot: some View {
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
            .onChange(of: quickNoteBridge.requestID) { handleQuickNoteRequest() }
            // Also catch a request that fired during a COLD launch (App Intent /
            // widget / deep link / shared video) BEFORE this view subscribed —
            // onChange alone misses it, which left Siri/widget "opens but doesn't
            // record" and a shared video not opening on a cold launch.
            .onAppear {
                handleStartRequest(); handleOpenRequest(); handleQuickNoteRequest()
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
                DevLog.log("search '\(query)' → \(derived.groups.reduce(0) { $0 + $1.memos.count })/\(memos.count) hits, \(photoHits) via photoText")
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
    var noteStack: some View {
        NavigationStack {
            if let route = selectedRoute {
                switch route {
                case .draft(let id):
                    QuickNoteView(draftID: id) {
                        selectedRoute = nil
                    }
                    .id(id)
                case .memo(let id):
                    MemoDetailView(initialID: id, listVisible: $listVisible)
                        .id(id)
                }
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
    func openMemo(_ id: UUID) {
        openRoute(.existing(id))
    }

    /// Route a navigation token to the active navigation model: the
    /// workbench pane at regular width, a reset push on the stack at
    /// compact. A single write of ONE value, never a pair of independently
    /// settable ones (Q47).
    func openRoute(_ route: NoteRoute) {
        if isRegular { selectedRoute = route } else { path = [route] }
    }

    /// Open the quick-note screen (Q7/C112/C114) — the app's own ✎, same
    /// entry point Lock Screen / Control Center / Siri route to via
    /// `QuickNoteBridge`. Unlike the Mac's ✎/⌘N (`Memo.newTyped` on the tap),
    /// nothing is created here: the pushed id is a navigation token only, and
    /// `QuickNoteDraft` authors the actual `Memo` on the first keystroke, so
    /// an untouched note never exists to sync anywhere (D91/C43). Always a
    /// FRESH `.draft` route (`NoteRoute.newDraft()`) — never reused, never
    /// compared against a second piece of state, so it can't be mistaken for
    /// whatever memo the launch recovery sweep may just have created
    /// (BUGS §3: the "Recovered recording…" note).
    func newTypedNote() {
        openRoute(.newDraft())
    }

    // MARK: - Content

    /// The Notes search field. A faithful inline copy of the shared `SearchField`
    /// (same tokens, same `memo-search` id) — reproduced here ONLY because that
    /// component (DesignSystem/Components.swift, read-only this wave) exposes no
    /// focus binding, and ⌘F needs `.focused($searchFocused)` on the TextField.
    var searchField: some View {
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

    var listContent: some View {
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
            // Same backlink scan `derived` already ran (never a second one per
            // render) — feeds the Mac-parity clock line on unrated rows.
            let backlinked = d.backlinked
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
                            MemoRow(memo: memo, enhancedTitle: d.enhancedTitleByMemoID[memo.id],
                                    fading: d.searchFadingIDs.contains(memo.id),
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
                                if isRegular { selectedRoute = .existing(memo.id) }
                                else { path.append(.existing(memo.id)) }
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
                            MemoRow(memo: memo, enhancedTitle: d.enhancedTitleByMemoID[memo.id],
                                    selected: memo.id == selectedMemoID) {
                                if isRegular { selectedRoute = .existing(memo.id) }
                                else { path.append(.existing(memo.id)) }
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

    var emptyState: some View {
        VStack(spacing: 0) {
            ContentUnavailableView(
                "No notes yet",
                systemImage: "waveform",
                description: Text("Tap the mic to record your first note.")
            )
            .accessibilityIdentifier("memos-empty")
        }
    }
}
