import SwiftUI
import SwiftData
import UIKit
import QuickLook
import PhotosUI
import FluidAudio

/// The "note" screen (mockup2). Swipe left/right between memos (a SwiftUI-native
/// horizontal paging `ScrollView` — NOT `TabView(.page)`, whose UIKit page host
/// broke `.glassEffect` refraction, the significance drag, and word tap-to-seek on
/// device), each page = editable title + RAW transcript (with inline `[[img_NNN]]`
/// embeds) + context/tags. A single playback bar is pinned at the bottom and
/// re-targets as you swipe. Title, tags, and the transcript are hand-editable
/// (save-now post-record flow); copy + delete live in the ⋯ menu.
struct MemoDetailView: View {
    let initialID: UUID

    // Trashed memos (deletedAt != nil) are excluded so a soft-deleted memo
    // drops out of the pager immediately (same filter as MemosListView).
    @Query(filter: #Predicate<Memo> { $0.deletedAt == nil },
           sort: \Memo.recordedAt, order: .reverse) var memos: [Memo]
    @Environment(\.dismiss) var dismiss
    /// iPad wave: the note becomes list|detail at regular width — the Connections
    /// panel stands beside the page, the reading measure + player bar cap the note
    /// column. Compact (phone / iPad multitasking-compact) stays the phone layout.
    @Environment(\.horizontalSizeClass) var hSize
    @State var selection: UUID?   // bound to .scrollPosition(id:) — optional per the API
    @State var showActions = false
    @State var showSplitOptions = false
    @State var showAppendRecorder = false
    @State var showShare = false
    /// ⋯ → "Remind me…" for the current page (chunk 7).
    @State var reminderMemo: Memo?
    /// Transient "n / total" that ghosts in while swiping between memos —
    /// replaces the permanent page-dots row (compact-player spec).
    @State var pageFlash = false
    @StateObject var player = AudioPlayerModel()
    @ObservedObject var lockGate = LockGate.shared
    @State var lockVaultNotice = false
    let repository = NotesRepository.shared

    /// iPad workbench: the ONE pinned ◧ list toggle lives in `MemosListView`'s
    /// screen overlay now (signed mock ipad-note-chrome-belongs.html); this
    /// binding is still how the note column reads the list's open state (the
    /// anchoring + focus-measure rules). Connections is no longer a bound
    /// standing column — it's this view's own transient visitor sheet
    /// (`showConnections`), per note, never remembered.
    var listVisible: Binding<Bool>? = nil

    /// Connections = an on-demand sheet OVER the note, per note (Tuur, signed
    /// 2026-07-24: a 13" screen can't afford a standing 300pt column). Transient
    /// @State, auto-closed when the pager settles on a different memo.
    @State var showConnections = false
    /// Bumped on each chrome-bar export so `processControl` re-reads the export
    /// ledger (`hasPublished` is a disk fact, not a model field — without this
    /// the label would stay "Export to Obsidian" until the next page turn).
    @State var exportedBump = 0
    /// Why the export didn't happen — shown as an alert. A primary button that
    /// silently does nothing is how the no-vault iPad read as broken (2026-08-18).
    @State var exportNotice: String?
    /// Transient "Exported ✓" shown in the button's place for ~2s after a write.
    @State var exportFlash: String?

    init(initialID: UUID, listVisible: Binding<Bool>? = nil) {
        self.initialID = initialID
        self.listVisible = listVisible
        _selection = State(initialValue: initialID)
    }

    var currentMemo: Memo? { memos.first { $0.id == selection } }

    /// List hidden = focus mode — the note takes the freed width. (Connections
    /// no longer occupies a column, so only the list gates focus now.)
    var listHidden: Bool { listVisible?.wrappedValue == false }

    /// The note bar's ⋯ — Split speakers leads it (moved off the bar: a
    /// once-per-note act, not a daily verb), then the same verbs the compact
    /// sheet offers, so nothing is reachable on one width only.
    /// One shared item → one `Label`, so a wording or glyph change lands on both
    /// apps at once.
    func menuLabel(_ item: NoteMenuItem) -> some View {
        Label(item.label, systemImage: item.systemImage)
    }

    @ViewBuilder func noteOverflowItems(_ memo: Memo) -> some View {
        // Wording / glyph / ORDER come from the shared `NoteMenuItem` — the Mac's
        // ⋯ renders the same vocabulary (Tuur 2026-07-25). Which items exist is
        // still per-app: no Finder or Markdown-copy here, no Share on the Mac.
        // Add-recording moved in here from its own ＋ chip (Tuur 2026-08-18:
        // the chrome band should read like the Mac's — primary · ⋯ · Connections).
        if memo.isShareCapture != true {
            Button { showAppendRecorder = true } label: { menuLabel(.addRecording) }
        }
        if !(memo.transcript ?? "").isEmpty, memo.audioURL != nil, !memo.isShareCapture {
            Button { showSplitOptions = true } label: { menuLabel(.splitSpeakers) }
        }
        // Redo ▸ Title / Copy-edit / Summary — the Mac's submenu, same shared
        // vocabulary (`NoteRedoItem`), same gates (Tuur 2026-08-18: the iPad ⋯
        // "should also have the same redo options"): only on an already-polished
        // note, only where this device can run the model, and copy-edit is hidden
        // for conversations — the LLM strips their `**Name:**` turn prefixes and
        // the turn structure is the only copy of the diarization (Mac parity).
        if PolishCenter.shared.isAvailable, !memo.locked,
           repository.enhancement(forMemo: memo.id)?.hasContent == true {
            let isConversation = !memo.audioFilename.isEmpty
                && SpeakerTranscript.isAttributed(memo.transcript)
            Menu {
                Button(NoteRedoItem.title.label) { PolishCenter.shared.redo(.title, for: memo) }
                if !isConversation {
                    Button(NoteRedoItem.copyEdit.label) { PolishCenter.shared.redo(.copyEdit, for: memo) }
                }
                Button(NoteRedoItem.summary.label) { PolishCenter.shared.redo(.summary, for: memo) }
            } label: { menuLabel(.redo) }
        }
        Button { reminderMemo = memo } label: { menuLabel(.remind) }
        if WallPrinter.shared.hasPrinter {
            Button { WallPrinter.shared.printCard(memo, repository: repository) } label: { menuLabel(.printCard) }
        }
        Button { toggleLock(memo) } label: { menuLabel(NoteMenuItem.lockItem(isLocked: memo.locked)) }
        Button { showShare = true } label: { menuLabel(.share) }
        Button(action: copyTranscript) { menuLabel(.copyTranscript) }
        Divider()
        Button(role: .destructive, action: deleteCurrent) { menuLabel(.delete) }
    }

    /// Whether Connections can actually show for the current memo — the summon
    /// capsule hides itself otherwise. One rule (`ConnectionsPanelLogic
    /// .canSummon`): rated and not locked. An unrated note makes no connections
    /// claims in either direction, so it doesn't offer the surface either.
    var connectionsAvailable: Bool {
        guard let memo = currentMemo else { return false }
        return ConnectionsPanelLogic.canSummon(memo, isLocked: lockGate.isLocked(memo))
    }

    /// The workbench's chrome band (signed mock ipad-note-chrome-belongs.html):
    /// a real toolbar with a hairline edge, so nothing hangs bare. The ◧ list
    /// toggle is GONE from here — it's the screen-pinned button in
    /// `MemosListView`. The note's own actions live here in iPadOS-26 glass
    /// chips, in the MAC's arrangement (Tuur 2026-08-18: "the export button in
    /// the same place that the Mac does"): the primary verb
    /// (Process → Export to Obsidian → Re-export, `NoteWorkState`) · ⋯ — the ＋
    /// chip folded into ⋯ as Add recording — then the Connections summon — a
    /// plain WORD, not a ◨ glyph and not a count (capped at 7 it would read "7"
    /// forever; Tuur, 2026-07-24), quiet → accent while the sheet is up.
    @ViewBuilder var workbenchChrome: some View {
        if let memo = currentMemo {
            HStack(spacing: 8) {
                Spacer(minLength: 0)

                processControl(memo)

                Menu { noteOverflowItems(memo) } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color.skTextDim)
                        .frame(width: 30, height: 30)
                        .barGlass()
                }
                .accessibilityIdentifier("note-overflow-button")

                if connectionsAvailable {
                    Button {
                        withAnimation(Theme.Motion.snappy) { showConnections.toggle() }
                    } label: {
                        Text(RetrievalGate.Copy.summonLabel)
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(showConnections ? Color.skAccentText : Color.skTextDim)
                            .padding(.horizontal, 12)
                            .frame(height: 30)
                            .barGlass(on: showConnections, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("ipad-connections-summon")
                    .accessibilityLabel(showConnections ? "Hide Connections" : "Show Connections")
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 48)
            // A real toolbar has an edge (signed mock): the hairline is what
            // stops the controls reading as floating.
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color.skBorder).frame(height: 0.5)
            }
            .accessibilityIdentifier("ipad-note-chrome")
        }
    }

    /// Connections as a VISITOR sheet (signed mock ipad-note-chrome-belongs.html):
    /// it slides in OVER the note's trailing edge — the note keeps its full
    /// width beneath, nothing reflows — and it stops above the docked player so
    /// transport stays reachable. Per note: auto-closed when the pager settles
    /// on a different memo, never remembered across launches.
    @ViewBuilder var connectionsSheet: some View {
        // Same `canSummon` rule as the capsule — the sheet must not render for a
        // note that can't summon it, even if `showConnections` got stuck true.
        if let memo = currentMemo,
           ConnectionsPanelLogic.canSummon(memo, isLocked: lockGate.isLocked(memo)) {
            ConnectionsPanel(
                memo: memo,
                onOpenMemo: { id in
                    guard memos.contains(where: { $0.id == id }) else { return }
                    withAnimation(Theme.Motion.snappy) { selection = id }
                },
                onClose: { withAnimation(Theme.Motion.snappy) { showConnections = false } })
                .frame(maxHeight: .infinity)
                .background(Color.skSurface)
                .shadow(color: .black.opacity(0.3), radius: 18, x: -8)
                .transition(.move(edge: .trailing))
        }
    }

    /// The primary verb — the Mac's three states (`NoteWorkState`: Process →
    /// Export to Obsidian → Re-export), replaced IN PLACE by a determinate line
    /// while a pass runs (`PolishCenter.Phase.line`/`.fraction`). Before
    /// 2026-08-18 only Process lived here, and at regular width a polished note
    /// had NO per-note export anywhere — the workState verb existed solely in
    /// the compact ⋯ dialog, which the iPad in full-screen never shows (Tuur:
    /// "I don't see the export button on the iPad in the same place that the
    /// Mac does").
    @ViewBuilder func processControl(_ memo: Memo) -> some View {
        let phase = PolishCenter.shared.phase(for: memo.id)
        switch phase {
        case .idle:
            let state = workState(for: memo)
            if state.wantsProcessing {
                // Offered while there's nothing polished yet — the enhancement
                // sidecar is the truth, whichever device wrote it.
                if PolishCenter.shared.canPolish(memo) {
                    // TINTED, not filled — the list header's "Process N" (the pile) is
                    // the one filled Process; this per-note one is secondary so two
                    // Process buttons don't shout at each other (Tuur, 2026-07-24).
                    Button { PolishCenter.shared.polishNow(memo) } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "play.fill").font(.system(size: 9, weight: .bold))
                            Text(SharedCopy.processVerb).font(.system(size: 12.5, weight: .semibold))
                        }
                        .foregroundStyle(Color.skAccentText)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Color.skAccentSoft, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("ipad-process-button")
                }
            } else if PolishCenter.shared.isAvailable {
                // Polished — offer the vault verb, same spot as the Mac's primary.
                // Gate = isAvailable (it can process, so it may export); the label
                // flips to Re-export via the ledger read in `workState`, re-run when
                // `exportedBump` changes after the success flash clears.
                if let flash = exportFlash {
                    Text(flash)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Color.skGreen)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Color.skGreen.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .accessibilityIdentifier("ipad-export-flash")
                } else {
                    Button { exportNow(memo) } label: {
                        Text(state.label(for: memo.destination))
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(Color.skAccentText)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Color.skAccentSoft, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("ipad-export-button")
                }
            }
        case .failed(let message):
            Button { PolishCenter.shared.polishNow(memo) } label: {
                HStack(spacing: 5) {
                    Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 10.5))
                    Text("Retry").font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(Color.skRed)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Color.skRed.opacity(0.12), in: Capsule())
            }
            .buttonStyle(.plain)
            .help(message)
            .accessibilityIdentifier("ipad-process-retry")
        default:
            if let line = phase.line {
                HStack(spacing: 8) {
                    if let f = phase.fraction {
                        ProgressView(value: f)
                            .progressViewStyle(.linear)
                            .frame(width: 74)
                            .tint(Color.skAccentText)
                    }
                    Text(line)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(Color.skAccentText)
                        .lineLimit(1)
                }
                .padding(.horizontal, 11).padding(.vertical, 6)
                .background(Color.skAccentSoft, in: Capsule())
                .accessibilityIdentifier("ipad-process-progress")
            }
        }
    }

    var body: some View {
        Group {
            if hSize == .regular {
                // The WORKBENCH (signed mock ipad-note-chrome-belongs.html): a
                // hairline toolbar, the note (paper), a docked player bar —
                // and Connections is a VISITOR sheet OVER the note, not a
                // standing column. Resting state = list + note only.
                VStack(spacing: 0) {
                    workbenchChrome
                    ZStack(alignment: .trailing) {
                        // Anchoring rule (Tuur, live round b130 — "the note is
                        // pushed to the right"): while the LIST is open the note
                        // sits AGAINST it, Apple-Notes-style; alone on screen
                        // (focus mode) it centers and wins width (640 → 900).
                        notePager
                            .frame(maxWidth: listHidden ? 900 : Adaptive.readingMaxWidth)
                            .frame(maxWidth: .infinity,
                                   alignment: listHidden ? .center : .leading)
                            .padding(.leading, listHidden ? 0 : 12)
                        // The visitor sheet rides over the note's trailing edge;
                        // nothing beneath reflows. It fills the reading area and
                        // stops at the docked player (the sibling below).
                        if showConnections { connectionsSheet }
                    }
                    if currentMemo?.isShareCapture != true {
                        dockedPlayer
                    }
                }
            } else {
                notePager
            }
        }
        // At regular the workbench owns its chrome band (above), so the stack's
        // spanning nav bar stays hidden.
        .toolbar(hSize == .regular ? .hidden : .automatic, for: .navigationBar)
        .background(Color.skBg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // COMPACT (phone) nav bar only — at regular these live in the
            // workbench's chrome band (`workbenchChrome`).
            ToolbarItem(placement: .topBarTrailing) {
                if hSize != .regular, currentMemo?.isShareCapture != true {
                    Button { showAppendRecorder = true } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(width: 34, height: 34)
                            .foregroundStyle(Color.skTextDim)
                    }
                    .accessibilityIdentifier("add-recording-button")
                    .accessibilityLabel("Add recording")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                if hSize != .regular, let memo = currentMemo, !(memo.transcript ?? "").isEmpty,
                   memo.audioURL != nil, !memo.isShareCapture {
                    Button { showSplitOptions = true } label: {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(width: 34, height: 34)
                            .foregroundStyle(Color.skTextDim)
                    }
                    .accessibilityIdentifier("split-speakers-button")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                if hSize != .regular {
                    Button { showActions = true } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(width: 34, height: 34)
                            .foregroundStyle(Color.skTextDim)
                    }
                    .accessibilityIdentifier("detail-menu")
                }
            }
        }
        // "How many speakers?" — Auto trusts the diarizer; a number forces exactly that
        // count by merging the most voice-similar slots (the over-segmentation fix).
        .confirmationDialog("How many speakers?", isPresented: $showSplitOptions, titleVisibility: .visible) {
            Button("Auto") { splitSpeakers(nil) }
            ForEach([2, 3, 4, 5], id: \.self) { n in
                Button("\(n) speakers") { splitSpeakers(n) }
            }
            Button("Cancel", role: .cancel) {}
        }
        // A confirmationDialog is presented by the view controller (not anchored
        // to the toolbar item), so the paged TabView can't swallow it — unlike a
        // toolbar `Menu`, which silently failed to present on device.
        .confirmationDialog(memoStatsLine, isPresented: $showActions, titleVisibility: .visible) {
            // iPad on-demand polish (m5, seam only): offered when the device + engine
            // qualify and the note has a real transcript. The Mac still auto-polishes.
            // The SAME three states the Mac offers (`NoteWorkState`). This menu used to ask
            // only `canPolish`, which stays true after a polish so it offered "Process" on a
            // note it had just processed — while the inline button two hundred lines up
            // hid itself correctly. One rule now, and Export is reachable per note at last:
            // a polished note is exportable wherever it was polished (Tuur, 2026-08-14).
            if let memo = currentMemo, workState(for: memo).wantsProcessing,
               PolishCenter.shared.canPolish(memo) {
                Button(SharedCopy.processVerb, action: { PolishCenter.shared.polishNow(memo) })
            }
            if let memo = currentMemo, !workState(for: memo).wantsProcessing,
               PolishCenter.shared.isAvailable {
                Button(workState(for: memo).label(for: memo.destination), action: { exportNow(memo) })
            }
            Button(NoteMenuItem.addRecording.label, action: { showAppendRecorder = true })
            Button(NoteMenuItem.remind.label, action: { reminderMemo = currentMemo })
            if WallPrinter.shared.hasPrinter, let memo = currentMemo {
                Button(NoteMenuItem.printCard.label, action: {
                    WallPrinter.shared.printCard(memo, repository: repository)
                })
            }
            if let memo = currentMemo {
                Button(memo.locked ? "Remove Lock" : "Lock Note", action: { toggleLock(memo) })
            }
            Button("Share note…", action: { showShare = true })
            Button("Copy transcript", action: copyTranscript)
            Button("Delete", role: .destructive, action: deleteCurrent)
            Button("Cancel", role: .cancel) {}
        }
        .sheet(item: $reminderMemo) { memo in
            ReminderSheet(memo: memo) { repository.save() }
        }
        // The chrome Export button's refusals/back-offs — every tap answers
        // (the no-vault iPad silence, 2026-08-18).
        .alert("Can't export", isPresented: Binding(
            get: { exportNotice != nil },
            set: { if !$0 { exportNotice = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportNotice ?? "")
        }
        .alert("Already in your vault", isPresented: $lockVaultNotice) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("This note was published to Obsidian before you locked it. Skrift never deletes vault files — remove it there if you want it gone. New publishes will skip it.")
        }
        .sheet(isPresented: $showShare) {
            if let memo = currentMemo {
                ActivityShareSheet(items: shareItems(for: memo))
                    .presentationDetents([.medium, .large])
            }
        }
        // Append a follow-up recording to the current memo (records → transcribes →
        // appends text + merges audio in MemoSaver.appendRecording). Transcript
        // updates in place via @Query when it lands.
        .fullScreenCover(isPresented: $showAppendRecorder) {
            RecordView(appendTo: selection)
        }
        .onAppear {
            normaliseCurrentOnce()   // C10/D4: old body + polish → v2 once, at first open
            loadCurrentAudio()
        }
        .onChange(of: selection) { old, newID in
            // Re-target the bar when paging settles; ignore the transient nil the
            // paging scroll reports between snap points (don't stop audio mid-swipe).
            guard let newID else { return }
            normaliseCurrentOnce()
            loadCurrentAudio()
            if old != nil, old != newID, memos.count > 1 { pageFlash = true }
            // Connections is PER NOTE (signed 2026-07-24): switching notes
            // (a memo-link hop, a related-row tap) dismisses the visitor sheet.
            if old != newID, showConnections {
                withAnimation(Theme.Motion.snappy) { showConnections = false }
            }
        }
        // Unlocking (or re-locking on background) re-derives what the player
        // may touch — a locked memo's audio never loads.
        .onChange(of: lockGate.unlockedIDs) { _, _ in loadCurrentAudio() }
        // A VIDEO import inserts the memo and opens this screen BEFORE its audio
        // has been extracted (extraction is async), so the initial load() hit a
        // file that didn't exist yet and left the player with no audio — tapping
        // Play then did nothing. When extraction lands (the duration fills in, then
        // transcription finishes) reload so Play works. Guarded on !hasAudio so a
        // normal append — which also moves the duration — never interrupts playback.
        .onChange(of: currentMemo?.duration) { _, _ in reloadIfAudioMissing() }
        .onChange(of: currentMemo?.transcriptStatus) { _, _ in reloadIfAudioMissing() }
        .onDisappear { player.stopAndClear(); repository.save() }
    }

    /// The horizontal pager (one page per memo) + the floating glass player bar.
    /// At regular width this is the note COLUMN (reading-measure-capped, beside the
    /// Connections panel); at compact it's the whole screen — byte-for-byte today.
    var notePager: some View {
        ScrollViewReader { proxy in
            // SwiftUI-native horizontal pager. `.scrollPosition(id:)` tracks the page;
            // the ScrollViewReader does the initial jump (the binding's initial value
            // isn't reliably honoured on first layout).
            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ForEach(memos) { memo in
                        MemoPageView(memo: memo, player: player, isCurrent: memo.id == selection,
                                     onOpenMemo: { id in
                                         guard memos.contains(where: { $0.id == id }) else { return }
                                         withAnimation(Theme.Motion.snappy) { selection = id }
                                     })
                            // C98/D139: two versions → prompt on open, banner after
                            // "Later", read-only until picked. Only the CURRENT page
                            // gates, so an adjacent realised page never raises a sheet.
                            .editConflictGate(memoID: memo.id == selection ? memo.id : nil,
                                              context: repository.context, look: .phone, style: .skrift)
                            .containerRelativeFrame(.horizontal)
                            // The LazyHStack realises adjacent pages; hide the
                            // off-screen ones from VoiceOver (and XCUITest) so
                            // their controls/text aren't duplicate matches.
                            .accessibilityHidden(memo.id != selection)
                            .id(memo.id)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $selection)
            .scrollIndicators(.hidden)
            // Swipe-between-notes OFF (Tuur, 2026-07-16): horizontal drags fought
            // text editing (caret drags / selection ate page swipes). The pager
            // structure stays — memo-link hops + the initial jump still drive
            // `selection` programmatically; only the drag gesture is disabled.
            .scrollDisabled(true)
            .onAppear {
                guard let selection else { return }
                DispatchQueue.main.async { proxy.scrollTo(selection, anchor: .center) }
            }
        }
        // The floating glass player bar lives in the bottom safe-area inset, NOT a
        // ZStack overlay. That's the fix for "glass shows nothing": a detached overlay
        // only samples the flat background behind everything, so Liquid Glass had no
        // scroll content to refract. As a safeAreaInset the scroll content renders
        // BEHIND the bar in the same backdrop, so the transcript/photos genuinely
        // refract through the glass as they pass under it (and content insets to clear
        // it at rest).
        // Playback bar is only meaningful when there's audio. Capture items
        // (audioURL == nil) have no audio — hide the bar entirely so the
        // scroll content isn't needlessly padded.
        // COMPACT (phone) only: the floating glass capsule inset. At regular the
        // player DOCKS as a sibling bar in the workbench VStack (signed mock
        // ipad-note-chrome-belongs.html) so the Connections visitor sheet can
        // stop above it — see `dockedPlayer`.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if hSize != .regular, currentMemo?.isShareCapture != true {
                bottomChrome
            }
        }
    }

    /// The regular-width DOCKED player (signed mock ipad-note-chrome-belongs.html):
    /// a full-width bar owned by the workbench's bottom edge (hairline top,
    /// `skSurface`) instead of a capsule hovering mid-air. The phone keeps its
    /// floating glass capsule (`bottomChrome`) byte-for-byte.
    var dockedPlayer: some View {
        playerBarStack
            .padding(.horizontal, 6)
            .background(Color.skSurface)
            .overlay(alignment: .top) {
                Rectangle().fill(Color.skBorder).frame(height: 0.5)
            }
    }

    @ViewBuilder var bottomChrome: some View {
        // REAL iOS-26 Liquid Glass on the floating playback bar (device + SDK are 26):
        // the transcript/photos refract through it as they scroll under (the bar is a
        // safeAreaInset, so the scroll content is in the same backdrop). A
        // GlassEffectContainer gives the glass a proper shared sampling region.
        // `.ultraThinMaterial` is only the fallback for iOS < 26.
        if #available(iOS 26.0, *) {
            GlassEffectContainer {
                playerBarStack
                    // .clear (not .regular) = the lensed, refractive look — .regular
                    // reads as frosted. (Device must have full Liquid Glass on: Reduce
                    // Motion / Reduce Transparency OFF, Liquid Glass = Clear.)
                    .glassEffect(.clear, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                    // A hairline + top specular highlight so the glass reads as an EDGE.
                    .overlay(
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .strokeBorder(
                                LinearGradient(colors: [.white.opacity(0.30), .white.opacity(0.04)],
                                               startPoint: .top, endPoint: .bottom),
                                lineWidth: 0.8)
                    )
            }
            .padding(.horizontal, Theme.Space.margin)
            .padding(.bottom, 6)
        } else {
            playerBarStack
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.28), radius: 18, y: 6)
                .padding(.horizontal, Theme.Space.margin)
                .padding(.bottom, 6)
        }
    }

    var playerBarStack: some View {
        PlayerBar(player: player, clock: player.clock)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .overlay(alignment: .top) {
                if pageFlash, let idx = memos.firstIndex(where: { $0.id == selection }) {
                    Text("\(idx + 1) / \(memos.count)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.skTextDim)
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(Color.skSurface, in: .capsule)
                        .overlay(Capsule().strokeBorder(Color.skBorder, lineWidth: 0.5))
                        .offset(y: -30)
                        .transition(.opacity)
                        .task(id: selection) {
                            try? await Task.sleep(for: .seconds(1.1))
                            withAnimation(.easeOut(duration: 0.3)) { pageFlash = false }
                        }
                }
            }
    }

    /// Feeds all three Copy entry points (⋯-menu `workbenchChrome`, the ⋯
    /// menu's `noteOverflowItems` item, and the compact-sheet "Copy
    /// transcript" — same function, one gate) through `GatedCopy` (R88/C213):
    /// a locked, not-yet-unlocked-this-session note asks for auth before
    /// copying — it does NOT silently no-op.
    func copyTranscript() {
        guard let memo = currentMemo else { return }
        Task { await GatedCopy.copyTranscript(memo, lockGate: lockGate) }
    }

    /// "512 words · 3:07" — the ⋯ sheet's title doubles as the note's stats line.
    var memoStatsLine: String {
        guard let memo = currentMemo else { return "Note" }
        let words = MemoShare.wordCount(of: memo.transcript)
        var parts: [String] = [words == 1 ? "1 word" : "\(words) words"]
        if memo.duration > 0 {
            let total = Int(memo.duration)
            parts.append(String(format: "%d:%02d", total / 60, total % 60))
        }
        return parts.joined(separator: " · ")
    }

    /// Share OUT (survey fold, user-approved): the note as markdown text, plus
    /// the recording file when there is one.
    func shareItems(for memo: Memo) -> [Any] {
        var items: [Any] = [MemoShare.markdown(title: memo.title ?? memo.firstTranscriptLine,
                                               body: memo.transcript ?? "")]
        if let url = memo.audioURL, FileManager.default.fileExists(atPath: url.path) {
            items.append(url)
        }
        return items
    }

    /// C10/D4 + Q40: the current note's body and its polished copy-edit, normalised once each.
    func normaliseCurrentOnce() {
        guard let memo = currentMemo else { return }
        memo.normaliseBodyOnce(enhancement: repository.enhancement(forMemo: memo.id))
    }

    /// Load the CURRENT memo's audio — unless its content is lock-gated
    /// (chunk 8: the bar must not play a locked note around the placeholder).
    func loadCurrentAudio() {
        guard let memo = currentMemo else { return }
        player.load(lockGate.isLocked(memo) ? nil : memo.audioURL)
    }

    /// Lock from ⋯ (instant, + vault notice when already published); removing
    /// the lock requires device-owner auth (Apple Notes idiom).
    func toggleLock(_ memo: Memo) {
        if memo.locked {
            Task {
                guard await LockGate.shared.authorizeRemoveLock() else { return }
                memo.locked = false
                memo.markEdited(stampWords: false)   // lock isn't title/body/tags (C98)
                repository.save()
            }
        } else {
            guard LockGate.shared.canAuthenticate() else { return }
            memo.locked = true
            memo.markEdited(stampWords: false)   // lock isn't title/body/tags (C98)
            repository.save()
            player.stopAndClear()
            if ObsidianVault.hasPublished(memo.id) { lockVaultNotice = true }
        }
    }

    /// Re-point the player at the current memo's audio if an earlier `load()` failed
    /// because the file wasn't on disk yet (the async video-import extraction case).
    /// A no-op once audio is loaded, so it never disturbs active playback.
    func reloadIfAudioMissing() {
        guard !player.hasAudio else { return }
        loadCurrentAudio()
    }

    /// Split the current memo into speakers (Auto, or force `count`). Re-runs diarization
    /// over the saved audio + word-timings; the model loads on first use here (the slow
    /// step now happens only when you ask, not after every recording).
    /// This note's state under the ONE cross-app rule (`NoteWorkState`), asking the ONE
    /// shared predicate (`MemoEnhancement.isProcessed`). The all-three-parts rule that used
    /// to live here in longhand moved into that predicate, where the Mac and the export gate
    /// read it too — and it now also answers YES for a pass that produced nothing, which is
    /// what stopped a wordless note offering "Process" forever (2026-08-26).
    func workState(for memo: Memo) -> NoteWorkState {
        let hasPolish = repository.enhancement(forMemo: memo.id)?.isProcessed == true
        return .of(hasPolish: hasPolish, isExported: PublishCoordinator.hasPublished(memo))
    }

    /// Export ONE note — the verb iOS never had. Settings' "Export now" published the whole
    /// eligible set and there was no way to say "this one, now".
    ///
    /// EVERY path answers (Tuur, 2026-08-18: tapped Export on an iPad with no vault
    /// configured and "nothing happened" — the old body was `_ = try?` around a gate
    /// that returns nil): a refusal names its gate in an alert, a back-off outcome says
    /// what the engine protected, success flashes in the chrome. Author key is
    /// `skrift.publish.author` — the SAME key Settings writes; the original read a
    /// `skrift.author` that nothing ever wrote, so a per-note export compiled with a
    /// blank author and the same note exported by two devices would differ by a
    /// frontmatter line (the edit guard would then treat it as user-edited forever).
    func exportNow(_ memo: Memo) {
        let author = UserDefaults.standard.string(forKey: "skrift.publish.author") ?? ""
        let coordinator = PublishCoordinator.live(author: author)
        if let refusal = coordinator.exportRefusal(memo) {
            exportNotice = refusal
            return
        }
        do {
            // The words are SHARED with the Mac (`ExportOutcomeCopy`) — one verb, one answer,
            // whichever device you pressed it on. `noVault`/nil have no engine outcome behind
            // them (the gate refused before the writer ran), so they stay here.
            switch try coordinator.publishIfEligible(memo) {
            case .written(let rel):
                say(.created(relativePath: rel))
            case .skippedUnchanged:
                say(.unchanged(relativePath: ""))
            case .userEdited(let rel):
                say(.backedOffUserEdited(relativePath: rel))
            case .movedAway(let rel):
                say(.movedAway(relativePath: rel))
            case .blocked(let rel):
                say(.blockedForeign(relativePath: rel))
            case .noVault:
                exportNotice = "The vault folder couldn't be opened — pick it again in Settings → Obsidian."
            case nil:
                exportNotice = "This note isn't eligible to export right now."
            }
        } catch {
            exportNotice = "Export failed: \(error.localizedDescription)"
        }
    }

    /// Say what the engine decided, in the SHARED words, with the shared rule about whether
    /// it may fade: a refusal stays until dismissed, anything else flashes.
    func say(_ outcome: VaultWriteOutcome) {
        let name = (currentMemo.map { MemoExporter.exportTitle(for: $0, people: []) } ?? "")
        let msg = ExportOutcomeCopy.message(for: outcome, noteName: name)
        if msg.isRefusal { exportNotice = msg.text } else { flashExport(msg.text) }
    }

    /// Show a short confirmation in the chrome where the button sits, then let the
    /// button re-render (its label re-reads the ledger, so success comes back as
    /// "Re-export").
    func flashExport(_ line: String) {
        withAnimation(Theme.Motion.snappy) { exportFlash = line }
        Task {
            try? await Task.sleep(for: .seconds(2.2))
            withAnimation(Theme.Motion.snappy) { exportFlash = nil }
            exportedBump += 1
        }
    }

    func splitSpeakers(_ count: Int?) {
        guard let id = currentMemo?.id else { return }
        // Keep the diarization alive if the user backgrounds the app mid-identify
        // (they often do — it can take a while). If iOS suspends/kills it anyway, the
        // launch sweep recoverStuckDiarizations re-runs it (2026-06-21 "I switched out
        // of the app and then I think it stopped").
        Task {
            await BackgroundTask.run(name: "diarize") {
                await MemoSaver().diarizeExisting(id: id, targetSpeakers: count)
            }
        }
    }

    /// Soft-delete: move the memo to Recently Deleted, same as every list delete
    /// path (MemosListView.deleteMemo). Audio, photos, and sidecars stay on disk
    /// so Restore is lossless; the startup purge removes them after the retention
    /// window. The pager's @Query excludes trashed memos, so the page disappears
    /// and we move to the next one (or dismiss when it was the last).
    func deleteCurrent() {
        guard let memo = currentMemo,
              let idx = memos.firstIndex(where: { $0.id == memo.id }) else { return }
        // Land on the ADJACENT page after delete — the next memo, else the previous
        // — not the top of the list. Dismiss when it was the only one.
        let neighbor: UUID?
        if idx + 1 < memos.count { neighbor = memos[idx + 1].id }
        else if idx - 1 >= 0 { neighbor = memos[idx - 1].id }
        else { neighbor = nil }
        player.stopAndClear()
        repository.softDelete(memo)
        if let neighbor { selection = neighbor } else { dismiss() }
    }
}
