import SwiftUI
import SwiftData
import AppKit
import os

/// The ingest queue / worklist. Organized around the daily loop:
/// memos arrive → Process the pile → review what's Ready → Export.
struct SidebarView: View {
    @Bindable var model: AppModel
    let files: [PipelineFile]
    @Bindable var coordinator: ProcessingCoordinator
    /// The Mac's ONE live take (RootView owns it). The header's Record/stop buttons and the
    /// synthetic queue row read/drive it; the pane (RootView) renders the same session's draft.
    @Bindable var session: LiveRecordingSession
    var onOpenSettings: () -> Void = {}
    /// Snapshot mode renders the queue without a ScrollView (ImageRenderer can't
    /// lay out scroll contents). The live app keeps `true` for real scrolling.
    var scrollable = true
    /// Snapshot fixtures: when set, the quiet-row source is this array and the
    /// live CloudKit store is never opened — renders stay deterministic (and can
    /// never leak the dev machine's real memos into a committed harness image).
    var fixtureCloudMemos: [Memo]? = nil
    @Environment(\.modelContext) private var ctx
    @State private var pulse = false
    /// Why a take couldn't start — drives the alert. nil = nothing to say.
    @State private var micProblem: MacRecorder.Refusal?
    /// Files waiting on the "One note / N notes" chooser (Q74). nil = nothing pending.
    @State private var pendingAudioImport: PendingAudioImport?
    /// Locking a note this machine already exported (Q100 / C161): the plaintext file stays.
    @State private var lockVaultNotice = false

    private var filtered: [PipelineFile] { model.visible(files) }
    /// `filtered` minus a quiet local take (unrated, error-free Mac recording — the
    /// unrated-take doctrine, 2026-07-28): it never renders as a lit `QueueRowView`,
    /// so it must not sit in the ordered/selectable row list either. Its twin `Memo`
    /// renders instead via `quietMemoRow` (see `unpipelinedMemos`/`WayOutRules`).
    private var queueRowFiles: [PipelineFile] { filtered.filter { !WayOutRules.isQuietLocalTake($0) } }
    private var orderedIDs: [String] { queueRowFiles.map(\.id) }
    /// Every row as drawn, quiet unrated notes included — the span a ⇧-click range runs over.
    private var displayedIDs: [String] {
        entries.map { entry in
            switch entry {
            case .file(let f): return f.id
            case .memo(let m): return m.id.uuidString
            }
        }
    }
    /// D135: "Each chip counts its own notes" — Needs Work / Done / Unrated, over
    /// ALL live items (not the filtered view), like the old triage line's counts.
    ///
    /// Q37 fix: Needs Work used to count ONLY `files` (PipelineFile rows), so a
    /// rated memo waiting on its OWN row — `strandedMemos`, WayOutRules.stranded —
    /// was invisible to the chip (the "Needs Work 6 vs the iPad's 99" gap over the
    /// same corpus: the iPad's `ProcessPile.matches(.needsWork,…)` scans every rated
    /// memo directly, with no pipeline-row prerequisite). Unrated switched from the
    /// band's `unpipelinedMemos` (which also excludes a fading note — right for the
    /// row list, since the conveyor owns that row, but wrong for the doctrine above:
    /// "ALL live items") to `ProcessPile.unrated`, the SAME shared call the iPad's
    /// chip makes — one definition, not two.
    private var chipCounts: [QueueFilter: Int] {
        NotesListModel.chipCounts(
            needsWork: files.filter { !model.isComplete($0) }.count + strandedMemos.count,
            done: files.filter { model.isComplete($0) }.count,
            notRated: ProcessPile.unrated(memos: effectiveCloudMemos).count)
    }
    /// Files still waiting on the Process button — gated through
    /// `coordinator.needsProcessing` too (not just `queueStatus`), so an unrated
    /// local recording is never counted into "Process N" / `canProcess`, matching
    /// the phone's "the rating is what pipelines a memo" doctrine.
    private var pendingFiles: [PipelineFile] {
        files.filter { ($0.queueStatus == .queued || $0.queueStatus == .transcribed) && coordinator.needsProcessing($0) }
    }
    private var pendingCount: Int { pendingFiles.count }
    @State private var dragOver = false
    @State private var showDateStrip = false

    // ── the Queue band (mocks/lifecycle-ia-explorations.html #m2) ───────────
    /// Cloud memos, refreshed on appear / when `files` changes / after any band
    /// Process action — the source for both the band's membership and (once
    /// step ③ lands) the one-trash footer count.
    @State private var cloudMemos: [Memo] = []
    /// Owns `cloudMemos`' context (Q241 bug 5): changes to those rows save through it.
    @State private var cloudSnapshot: CloudMemoSnapshot?
    /// Search by meaning (Q82 group 13): note ids similar in MEANING to the query, best first —
    /// the phone's RELATED section. Filled async under the exact matches.
    @State private var relatedIDs: [UUID] = []
    /// Row-tap peek (read-only + Flag) — same sheet the Review river uses.
    private var effectiveCloudMemos: [Memo] { fixtureCloudMemos ?? cloudMemos }
    private var unpipelinedMemos: [Memo] { WayOutRules.unpipelined(memos: effectiveCloudMemos, files: files) }
    /// Rated memos with no pipeline row — see `WayOutRules.stranded`. Kept apart from
    /// `unpipelinedMemos` on purpose: these are RATED, so they must not swell the "N not
    /// rated" count or the Process-all set. They only need to be SEEN.
    private var strandedMemos: [Memo] { WayOutRules.stranded(memos: effectiveCloudMemos, files: files) }
    /// Q56/R90: was a computed property re-run by EVERY quiet row's `quietMemoRow`
    /// call — O(quietRows × cloudMemos) per render. Cached instead, refreshed
    /// alongside `cloudMemos` (the only thing it derives from) — one scan per
    /// render, not one per row.
    @State private var backlinkedIDs: Set<UUID> = []

    var body: some View {
        VStack(spacing: 0) {
            SurfaceSwitch(model: model)
                .padding(.horizontal, 10).padding(.top, 10)
            header
            queue
            bottomBar
        }
        // Q95: a SwiftUI `.frame(maxWidth: .infinity)` with the default CENTER alignment
        // centres any child wider than the column, so a column dragged below the content's
        // own floor lost BOTH edges (Tuur 2026-10-02: "it just clips off weirdly"). Leading
        // alignment + clip: whatever cannot fit is cut on the RIGHT, the logo / verbs / chips /
        // day headers / cards always keep their left edge.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipped()
        // D135/D136 (one-notes-list): the sidebar ground turns from white to the
        // phone's grey — rows become white cards, matching the phone/iPad.
        .background(Theme.sidebarGround)
        // Why a take couldn't start (no mic, refused permission, engine wouldn't come up).
        // An alert rather than a dimmed button: the check that decides this is a synchronous
        // CoreAudio call, and running it while DRAWING made the button visibly slow to
        // enable/disable. Pressed-time is both the honest moment to ask and the free one.
        //
        // A denied mic gets a BUTTON, not just an instruction. Once TCC holds a denial macOS
        // never prompts again, so "grant it in System Settings" is a scavenger hunt at the
        // exact moment the app looks broken — and this is not hypothetical: it is what took
        // Record out on 2026-07-28 (`-miccheck` read DENIED long after capture had worked).
        .alert("Can't record", isPresented: Binding(
            get: { micProblem != nil },
            set: { if !$0 { micProblem = nil } }
        )) {
            if micProblem?.fixedInPrivacySettings == true {
                Button("Open Settings") {
                    if let url = URL(string: MacRecorder.Refusal.privacySettingsURL) {
                        NSWorkspace.shared.open(url)
                    }
                    micProblem = nil
                }
            }
            Button("OK", role: .cancel) { micProblem = nil }
        } message: {
            Text(micProblem?.message ?? "")
        }
        .alert("Already in your vault", isPresented: $lockVaultNotice) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(LockVaultNotice.message)
        }
        .sheet(item: $pendingAudioImport) { pending in
            AudioImportChoiceSheet(
                clipCount: pending.clipCount,
                onConfirm: { choice in
                    pendingAudioImport = nil
                    runIngest(pending.urls, combineAudio: choice.combines,
                              cleanup: pending.cleanup)
                },
                onCancel: {
                    pendingAudioImport = nil
                    pending.cleanup?()
                })
        }
        .task { refreshCloudMemos() }
        // A synced UNRATED memo changes nothing about `files` (it never becomes a
        // PipelineFile), so `files.count` below can't see it — that's why one stayed
        // invisible until the app was relaunched. Every sweep now announces itself.
        .onReceive(NotificationCenter.default.publisher(for: .cloudMemosDidChangeFromSync)) { _ in
            refreshCloudMemos()
        }
        .onChange(of: files.count) { _, _ in refreshCloudMemos() }
        .onChange(of: model.filter) { _, _ in refreshCloudMemos() }
        .overlay(alignment: .trailing) {
            Rectangle().fill(Theme.hairline.opacity(0.07)).frame(width: 0.5)
        }
        .dropDestination(for: URL.self) { urls, _ in ingest(urls); return true } isTargeted: { dragOver = $0 }
        // Photos (and Mail/Safari) drag PROMISED files, not real URLs — the URL
        // dropDestination above never fires for those, so dragging straight from the
        // Photos app silently did nothing. This AppKit catcher registers ONLY for
        // file-promise types (Finder's plain-URL drags keep taking the SwiftUI path),
        // receives the promised files into a temp folder, and ingests the real URLs.
        .overlay { FilePromiseDropCatcher(isTargeted: $dragOver) { urls, cleanup in ingest(urls, cleanup: cleanup) } }
        .overlay {
            if dragOver {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Theme.accent.opacity(0.6), style: StrokeStyle(lineWidth: 2, dash: [6]))
                    .background(Theme.accent.opacity(0.06))
                    .overlay(Text("Drop to add").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.accent))
                    .padding(6)
                    .allowsHitTesting(false)
            }
        }
    }

    // ── Ingest ──────────────────────────────────────────────
    private func openUploadPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.prompt = "Add"
        panel.message = "Add voice memos, audio files, or an Apple Notes folder"
        guard panel.runModal() == .OK else { return }
        ingest(panel.urls)
    }

    /// Hand files to the shared arrival path (`ArrivalPath`) and select what landed. The
    /// pipeline steps — date backfill, the unrated Memo, the immediate transcribe — live there
    /// so the Record button and the `-recordingest` harness cannot drift apart.
    /// `cleanup` (Photos promise drops) removes the temp folder the promised files were
    /// written to; it runs once the files are copied, or when the chooser is cancelled.
    private func ingest(_ urls: [URL], cleanup: (() -> Void)? = nil) {
        guard !urls.isEmpty else { cleanup?(); return }
        // The ONE decision point (Q74 / C68 / C145): the Import panel, the Finder drop and the
        // Photos file-promise drop all land here, so a bundle of 2+ voice notes is asked
        // "One note or N notes?" exactly once, before anything is copied. (A recording never
        // comes through here: `LiveRecordingSession` calls `ArrivalPath.run` itself.)
        Task { @MainActor in
            // Probing containers for a video track is file I/O — off the main actor.
            let clipCount = await Task.detached { IngestService.audioClips(in: urls).count }.value
            if AudioImportChoice.needsChoice(clipCount: clipCount) {
                pendingAudioImport = PendingAudioImport(urls: urls, clipCount: clipCount, cleanup: cleanup)
            } else {
                runIngest(urls, combineAudio: false, cleanup: cleanup)
            }
        }
    }

    private func runIngest(_ urls: [URL], combineAudio: Bool, cleanup: (() -> Void)?) {
        // Async: the heavy file work (copies, video-audio export) runs off-main
        // inside IngestService — dropping a video used to beachball the whole
        // UI for the duration of the export.
        Task { @MainActor in
            defer { cleanup?() }
            do {
                try await ArrivalPath.run(
                    urls: urls, asRecording: false, into: ctx,
                    cloudContext: MemoCloudStore.container?.mainContext,
                    hooks: .live(coordinator: coordinator, context: ctx),
                    combineAudio: combineAudio,
                    // Select as soon as the row exists — not after transcription, which for a
                    // recording runs inside this same call and can take a while.
                    onCreated: { created in
                        if let first = created.first {
                            model.select(first.id)
                        }
                    },
                    onSkipped: { skipped in
                        let names = skipped.prefix(3).map(\.lastPathComponent).joined(separator: ", ")
                        let more = skipped.count > 3 ? " and \(skipped.count - 3) more" : ""
                        coordinator.lastError = "Couldn't import: \(names)\(more) (unsupported or unreadable)"
                    })
            } catch {
                coordinator.lastError = "Import failed: \(error.localizedDescription)"
            }
        }
    }

    /// Delete notes: SOFT-delete into "Recently Deleted" (mirrors the phone +
    /// Apple Voice Memos). The record + working folder stay on disk so Restore is
    /// lossless; the launch purge removes them (and trashes the folder) after the
    /// retention window. Was a hard `ctx.delete` + immediate folder-trash.
    private func deleteFiles(_ targets: [PipelineFile]) {
        // R88/C161: a locked note needs device-owner auth before it can be trashed — the
        // phone's `deleteMemo` rule, via the shared `LockPolicy`. Unlocked-only batches
        // stay synchronous.
        guard targets.contains(where: { LockGate.shared.isLocked($0) }) else {
            performDelete(targets)
            return
        }
        Task {
            var allowed: [PipelineFile] = []
            for t in targets where await LockGate.shared.policy.authorizeDelete(id: t.id, locked: t.locked) {
                allowed.append(t)
            }
            if !allowed.isEmpty { performDelete(allowed) }
        }
    }

    private func performDelete(_ targets: [PipelineFile]) {
        // Don't strand the selection/active note on a now-hidden file.
        let ids = Set(targets.map(\.id))
        DesktopTrash.softDelete(targets, in: ctx)
        MacCloudDeleteSync.mirror(targets)   // push the trash to the phone (delete-sync)
        model.selection.subtract(ids)
        if let active = model.activeID, ids.contains(active) { model.activeID = nil }
        coordinator.flash("Moved to Recently Deleted")
    }

    // ── Header ──────────────────────────────────────────────
    private var header: some View {
        VStack(spacing: 12) {
            HStack {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(LinearGradient(colors: [Theme.rgb(142, 125, 255), Theme.rgb(106, 89, 239)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 22, height: 22)
                        .overlay(Text("S").font(.system(size: 13, weight: .heavy)).foregroundStyle(.white))
                        .shadow(color: Theme.accent.opacity(0.45), radius: 3, y: 1)
                    Text("Skrift").font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                }
                Spacer()
                iconButton("gearshape") { onOpenSettings() }
                    .accessibilityIdentifier("sidebar.settings")
                    .accessibilityLabel("Settings")
            }

            // Signed mock `mocks/mac-record-button.html`, option B: the two verbs that BRING
            // MATERIAL IN pair up, and Process — the one expensive verb, which acts on the
            // pile you already have — gets the full width. Three across was measurably too
            // tight at the 240pt floor (that is the overflow that clipped this header in
            // July). While recording, the pair is replaced by the transport.
            //
            // `.settling` deliberately falls through to the plain pair, NOT the transport
            // (mocks/mac-live-transcription.html m4: "stop just stops" — the transport
            // vanishes the instant Stop is pressed; only the synthetic queue row's
            // "settling…" badge still says anything is in flight).
            if isLive {
                recordingTransport
            } else {
                HStack(spacing: 7) {
                    actionButton(title: SharedCopy.importVerb, system: "plus") { openUploadPanel() }
                    recordButton
                    newNoteButton
                }
            }
            processButton

            searchField

            filterChips
        }
        .padding(.horizontal, 12)
        .padding(.top, 38)   // room for the inset traffic lights (hidden titlebar)
        .padding(.bottom, 11)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.hairline.opacity(0.06)).frame(height: 0.5)
        }
    }

    /// Start a take. Red mic + label, in the same shape as Import — they are the same verb
    /// family, so they must not look like different weights of control.
    /// Always live, never dimmed. Whether this Mac HAS a mic is asked when you press it, not
    /// while drawing it: `MacRecorder.hasInputDevice` is a synchronous CoreAudio call, and
    /// evaluating it in this body ran it on every sidebar re-render — the dim/undim was
    /// visibly slow (Tuur, 2026-07-28). Off the render path it costs nothing, and a button
    /// that answers when pressed beats a greyed one you have to hover to understand.
    private var recordButton: some View {
        Button {
            Task { await startRecording() }
        } label: {
            HStack(spacing: 6) {
                Circle().fill(Theme.destructive).frame(width: 9, height: 9)
                Text("Record").lineLimit(1)
            }
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundStyle(Theme.destructive)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(Theme.hairline.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .help("Record a voice memo on this Mac")
        .accessibilityIdentifier("sidebar.record")
    }

    /// A typed note (mocks/mac-new-note.html m2, Tuur's pick 2026-07-28): the system
    /// compose glyph as a quiet chip beside the pair — Import and Record keep their
    /// labels (they name their sources), typing is the third verb. Same height as its
    /// row-mates, fixed width. ⌘N works wherever the sidebar exists.
    private var newNoteButton: some View {
        Button { newTypedNote() } label: {
            Image(systemName: "square.and.pencil")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 34)
                .padding(.vertical, 7)
                .background(Theme.hairline.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .keyboardShortcut("n", modifiers: .command)
        .help("New note (⌘N)")
        .accessibilityIdentifier("sidebar.new-note")
    }

    /// Open a new typed note — NO `Memo` yet. The pane is the draft (`AppModel.beginTypedNote`);
    /// the first keystroke creates the unrated Memo in the CLOUD store and posts the refresh
    /// that lists it, and leaving it empty creates nothing and discards nothing (C43/D91).
    private func newTypedNote() {
        model.beginTypedNote()
    }

    /// Mid-take: elapsed · live meter · stop. Occupies the row the Record button was in, so
    /// the header doesn't change height when a recording starts (a jumping sidebar while
    /// you're talking is exactly the wrong feedback).
    private var recordingTransport: some View {
        HStack(spacing: 10) {
            Circle().fill(Theme.destructive).frame(width: 9, height: 9)
                .opacity(pulse ? 0.35 : 1)
                .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: pulse)
            Text(session.elapsedLabel)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.destructive)
                .monospacedDigit()
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<session.meter.width, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Theme.destructive.opacity(0.55))
                        .frame(height: 16 * session.meter.height(at: i))
                }
            }
            .frame(height: 16)
            Button { stopRecording() } label: {
                RoundedRectangle(cornerRadius: 1.5).fill(.white).frame(width: 8, height: 8)
                    .frame(width: 22, height: 22)
                    .background(Theme.destructive, in: RoundedRectangle(cornerRadius: 5))
            }
            .buttonStyle(.plain)
            .help("Stop and save")
            .accessibilityIdentifier("sidebar.record.stop")
        }
        .padding(.horizontal, 11).padding(.vertical, 9)
        .background(Theme.destructive.opacity(0.11), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.destructive.opacity(0.3), lineWidth: 1))
        .onAppear { pulse = true }
        .onDisappear { pulse = false }
    }

    /// The transport shows for `.starting`/`.live` only — see the header's comment.
    private var isLive: Bool {
        switch session.phase {
        case .starting, .live: return true
        default: return false
        }
    }

    /// Any take in flight, start to finalize — gates Process (one mic/job at a time) and
    /// the queue's empty/no-matches states (a live take row means the queue isn't empty).
    private var sessionBusy: Bool {
        switch session.phase {
        case .starting, .live, .settling: return true
        default: return false
        }
    }

    /// Start a take, and SAY SO when it can't. A failure used to go to
    /// `coordinator.lastError`, which nothing on screen reads — so a refused or absent mic
    /// looked exactly like a dead button. An alert can't be missed and costs no layout.
    private func startRecording() async {
        await session.start()
        if case .failed(let why) = session.phase {
            micProblem = why
        }
    }

    /// Stop → the session finalizes + hands the take to the SAME arrival path the Import
    /// button uses (LiveRecordingSession.stop()). A dead take raises the same alert a
    /// failed start does — its message used to go to `coordinator.lastError`, which nothing
    /// on screen renders, so a dozing Bluetooth mic produced a transport that counted, a
    /// stop that shrugged, and a user who reasonably concluded the whole feature was broken
    /// (Tuur, twice, 2026-07-28).
    private func stopRecording() {
        Task {
            await session.stop()
            if case .failed(let why) = session.phase {
                micProblem = why
            }
        }
    }

    private var processButton: some View {
        Button {
            let ids = pendingFiles.map(\.id)
            Task { await coordinator.process(fileIDs: ids, context: ctx) }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "play.fill").font(.system(size: 10))
                Text("Process")
                if pendingCount > 0 {
                    Text("\(pendingCount)")
                        .font(.system(size: 11))
                        .padding(.horizontal, 5)
                        .background(Color.white.opacity(0.22), in: RoundedRectangle(cornerRadius: 5))
                }
            }
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(Theme.accent.opacity(canProcess ? 1 : 0.4), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .disabled(!canProcess)
        .accessibilityIdentifier("sidebar.process")
    }

    /// Process greys out WHILE RECORDING: one mic, one job. A pipeline run competing with a
    /// live input tap is where the phone's audio bugs came from, and there is no reason to
    /// invite the same class of problem onto the Mac.
    private var canProcess: Bool { pendingCount > 0 && !coordinator.isRunning && !sessionBusy }

    private func actionButton(title: String, system: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: system).font(.system(size: 11, weight: .semibold))
                Text(title).lineLimit(1)
            }
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundStyle(Theme.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(Theme.hairline.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    private func iconButton(_ system: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 24, height: 24)
                .background(Theme.hairline.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    /// Free-text search over the queue (title / transcript / summary). Mirrors the
    /// phone's search field — the Mac is the triage hub, so finding a memo by content
    /// matters most here.
    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11)).foregroundStyle(Theme.textMuted)
            TextField(SharedCopy.searchPlaceholder, text: $model.searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textPrimary)
                .accessibilityIdentifier("sidebar.search")
            if !model.searchText.isEmpty {
                Button { model.searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11)).foregroundStyle(Theme.textMuted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(Theme.hairline.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.hairline.opacity(0.08), lineWidth: 0.5))
    }

    /// Q66/D148 (option A, `mocks/Q49-one-filter.html`): the chip row carries
    /// everything -- the four status chips, then Date (a strip under the row,
    /// not a popover), and the sort word pinned at the row's end
    /// (`SidebarSort.short`/`.next`, one tap = next sort). The icon-only Filter
    /// button and its Sort & Date popover are gone. Same construction as the
    /// phone's chip row (C115: `ChipRowStyle` / `ExtraFilterChip` /
    /// `SortCycleWord` / `DateRangeStrip` live in Shared/UI); no Unsynced chip
    /// here (the mock: "Mac has no Unsynced today"). Scrolls sideways at the
    /// sidebar's 292pt floor.
    private var filterChips: some View {
        let style = ChipRowStyle(accent: Theme.accent, dim: Theme.textSecondary)
        return VStack(spacing: 6) {
            HStack(spacing: 8) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 5) {
                        ForEach(QueueFilter.allCases, id: \.self) { f in
                            let on = model.filter == f
                            HStack(spacing: 3) {
                                Text(f.rawValue)
                                // D135: "All carries no number" -- the other three show the
                                // count `chipCounts` computed, over every live item.
                                if let n = chipCounts[f] {
                                    Text("\(n)").fontWeight(.semibold)
                                }
                            }
                            .font(.system(size: 11))
                            .lineLimit(1).fixedSize()
                            .foregroundStyle(on ? Theme.accent : Theme.textSecondary)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(on ? Theme.accent.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6)
                                .stroke(on ? Theme.accent.opacity(0.22) : .clear, lineWidth: 1))
                            .contentShape(Rectangle())
                            .onTapGesture { model.filter = f }
                            .accessibilityIdentifier("sidebar.chip.\(f.rawValue)")
                        }
                        ExtraFilterChip(label: model.dateFilterActive ? "Date \u{00B7} \(dateChipLabel) \u{25BE}" : "Date \u{25BE}",
                                        active: model.dateFilterActive || showDateStrip, style: style)
                            .onTapGesture { showDateStrip.toggle() }
                            .accessibilityIdentifier("sidebar.chip.Date")
                    }
                    // Q48: same quick, consistent pill motion as the phone/iPad chip row
                    // (`SkMotion.snappy`) -- scoped to this row, never reaching `queue`
                    // below (a sibling), so the list swap stays instant, not section-animated.
                    .animation(SkMotion.snappy, value: model.filter)
                }
                .chipRowFade()
                SortCycleWord(word: model.sort.short, style: style) { model.sort = model.sort.next }
                    .accessibilityIdentifier("sidebar.sort-word")
            }
            if showDateStrip {
                DateRangeStrip(style: style,
                               from: $model.dateFrom, to: $model.dateTo,
                               fixedLabel: "Uploaded")
            }
        }
    }

    /// "22\u{2013}25 Sep" / "from 22 Sep" / "to 25 Sep" -- the Date chip's own label
    /// once a range is live (mirrors the phone's `dateChipLabel`).
    private var dateChipLabel: String {
        let f = DateFormatter()
        f.dateFormat = "d MMM"
        switch (model.dateFrom, model.dateTo) {
        case let (from?, to?): return "\(f.string(from: from))\u{2013}\(f.string(from: to))"
        case let (from?, nil): return "from \(f.string(from: from))"
        case let (nil, to?):   return "to \(f.string(from: to))"
        default:               return ""
        }
    }

    // ── Queue ───────────────────────────────────────────────
    @ViewBuilder private var queue: some View {
        let rows = entries
        // A live take pins its own synthetic row (below) whether or not there's anything
        // else to show — an empty vault mid-first-recording is not the "No memos yet" state.
        let related = relatedEntries(excluding: rows)
        if files.isEmpty && unpipelinedMemos.isEmpty && !sessionBusy {
            emptyQueue
        } else if rows.isEmpty && related.isEmpty && !sessionBusy {
            noMatches
                .task(id: model.searchText) { await refreshRelated() }
        } else {
            // Plain VStack (not Lazy) is fine for a personal-scale vault; revisit
            // windowing (List / lazy) only if a very large queue shows scroll jank.
            // D136: day groups, new on the Mac — the SAME `MemoDate.group` key the
            // phone/iPad use, via the shared `NotesListModel.dayGroups`, so a day
            // header reads the same word everywhere.
            let inner = Group {
                // Synthetic "Recording…"/"settling…" row (m1/m2/m4) — NOT a `PipelineFile`,
                // pinned above every real row, purely presentational from `session`.
                if sessionBusy {
                    LiveTakeRow(phase: session.phase, elapsedLabel: session.elapsedLabel,
                                settledText: session.settledText)
                }
                // Title sort scrambles chronological order, so day headers would
                // repeat non-contiguously (the phone's `.longest` bypass, mirrored):
                // one flat "All" bucket instead.
                ForEach(model.sort == .title
                        ? [(title: "", items: rows)]
                        : NotesListModel.dayGroups(rows, dayLabel: { MemoDate.group($0.date) }),
                        id: \.title) { group in
                    // Q95: the day header PINS at the top of the scroll like the phone's
                    // (`pinnedViews: [.sectionHeaders]` on the LazyVStack below). The header
                    // carries the sidebar's own ground so cards scroll UNDER it, not through it.
                    Section {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(group.items) { entry in
                                switch entry {
                                case .file(let f):
                                    QueueRowView(file: f, selected: model.selection.contains(f.id)) {
                                        model.handleClick(f.id, displayOrder: displayedIDs, selectable: Set(orderedIDs))
                                    }
                                    .contextMenu { rowMenu(f) }
                                case .memo(let m):
                                    quietMemoRow(m)
                                }
                            }
                        }
                        .padding(.bottom, 10)
                    } header: {
                        if !group.title.isEmpty {
                            Text(group.title.uppercased())
                                .font(.system(size: 10.5, weight: .bold))
                                .kerning(0.4)
                                .foregroundStyle(Theme.textMuted)
                                .padding(.horizontal, 4).padding(.top, 2).padding(.bottom, 6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Theme.sidebarGround)
                        }
                    }
                }
                if !related.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Text("RELATED").font(.system(size: 10.5, weight: .bold)).kerning(0.4)
                            Text("similar in meaning").font(.system(size: 10.5))
                        }
                        .foregroundStyle(Theme.textMuted)
                        .padding(.horizontal, 4)
                        .accessibilityIdentifier("sidebar.related-header")
                        ForEach(related) { entry in
                            switch entry {
                            case .file(let f):
                                QueueRowView(file: f, selected: model.selection.contains(f.id)) {
                                    model.handleClick(f.id, displayOrder: displayedIDs, selectable: Set(orderedIDs))
                                }
                                .contextMenu { rowMenu(f) }
                            case .memo(let m):
                                quietMemoRow(m)
                            }
                        }
                    }
                }
            }
            // Lazy + pinned headers in the live (hosted) list; the ImageRenderer fixtures
            // (`scrollable: false`) keep the plain VStack they always drew.
            let content = Group {
                if scrollable {
                    LazyVStack(alignment: .leading, spacing: 10, pinnedViews: [.sectionHeaders]) { inner }
                } else {
                    VStack(alignment: .leading, spacing: 10) { inner }
                }
            }
            .padding(8)
            .task(id: model.searchText) { await refreshRelated() }

            if scrollable {
                ScrollView { content }
            } else {
                VStack(spacing: 0) { content; Spacer(minLength: 0) }
            }
        }
    }

    /// The Related rows: the semantic hits that the exact search did not already show.
    /// Through the shared Related rule (Q104): the same chip + date range as the list, so a
    /// filtered list never grows unfiltered Related rows underneath it.
    private func relatedEntries(excluding shown: [SidebarEntry]) -> [SidebarEntry] {
        let exact = Set(shown.map { entry -> String in
            switch entry {
            case .file(let f): return f.id
            case .memo(let m): return m.id.uuidString
            }
        })
        // Q101 (C91/C161): a semantic hit is the note's words too — a locked, not-yet-unlocked
        // note never surfaces through Related.
        return model.listFilter.relatedRows(
            hits: relatedIDs, files: files, memos: effectiveCloudMemos, shown: exact,
            isLockedFile: { LockGate.shared.isLocked($0) }, isLockedMemo: { LockGate.shared.isLocked($0) }
        ).map { row in
            switch row {
            case .file(let f): return .file(f)
            case .memo(let m): return .memo(m)
            }
        }
    }

    /// Debounced semantic lookup for the current query — the phone's `refreshRelated`, on the
    /// same shared floor. Exact matches never wait on it.
    private func refreshRelated() async {
        let q = model.searchText.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty, ConnectionsIndexService.shared.isActive else {
            if !relatedIDs.isEmpty { relatedIDs = [] }
            return
        }
        try? await Task.sleep(nanoseconds: 250_000_000)
        guard !Task.isCancelled else { return }
        let scores = await ConnectionsIndexService.shared.searchScores(q)
        guard !Task.isCancelled else { return }
        relatedIDs = SemanticSearch.results(scores: scores, excluding: [])
    }

    // ── Quiet rows — unrated notes IN the list (Tuur, 2026-07-21 round 3:
    // the separate band container confused even the owner; the phone's Notes
    // list shows everything, so this one does too). Membership stays
    // WayOutRules.unpipelined (quiet clock-run notes; fading lives on the
    // conveyor, locked notes are resolved and don't nag — m6 2026-07-22).
    // No selection semantics — a quiet row taps open the peek, where the
    // circles live. Right-click carries the fast verbs (Flag/Lock/Delete).
    // Rated rows keep the full click/selection machinery.

    /// Stranded, quiet, locked-quiet and (while searching) fading rows, each through the
    /// shared list rule (Q104, `MacListFilter.memoRows`): search AND chip AND the date range,
    /// the same three tests a pipeline row and every phone row pass. Stranded notes (rated,
    /// no pipeline row) ride every chip except Not rated; unrated kinds sit under All and
    /// Not rated. Fading notes join only while searching (no-bad-info, 2026-07-21) — their
    /// one-liner ("moves to Recently Deleted in Nd") is the marker.
    private var visibleMemoRows: [Memo] {
        model.listFilter.memoRows(memos: effectiveCloudMemos, files: files)
    }

    /// One list, two row kinds, interleaved by the active sort.
    private var entries: [SidebarEntry] {
        var out: [SidebarEntry] = queueRowFiles.map { .file($0) }
        out.append(contentsOf: visibleMemoRows.map { .memo($0) })
        switch model.sort {
        case .newest: out.sort { $0.date > $1.date }
        case .oldest: out.sort { $0.date < $1.date }
        case .title:  out.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        }
        return out
    }

    private func quietMemoRow(_ memo: Memo) -> some View {
        let selected = model.selection.contains(memo.id.uuidString)
        return NoteCardView(model: quietCardModel(memo, selected: selected), style: .mac)
            .contentShape(Rectangle())
            .onTapGesture { openInPane(memo) }
            .contextMenu {
                Button(memo.locked ? "Unlock" : "Lock") { toggleLock(memo) }
                Button("Open") { openInPane(memo) }
                Divider()
                Button("Delete", role: .destructive) { deleteQuiet(memo) }
            }
            .accessibilityIdentifier("quiet-memo-row")
    }

    private func quietCardModel(_ memo: Memo, selected: Bool) -> NoteCardModel {
        // Quiet rows render the SAME shared card, dimmed (m2): quiet ≠ urgent,
        // the spine one-liner rides the stamp slot, no pill, no verbs.
        // Locked ⇒ title + 🔒 and nothing else (C91/C161, R88) — still IN the list, dimmed.
        if memo.locked {
            return LockedRow.card(stamp: MemoDate.label(memo.recordedAt), title: LockedRow.title(for: memo),
                                  selected: selected, quiet: true)
        }
        var m = NoteCardModel(stamp: MemoDate.label(memo.recordedAt))
        m.quiet = true
        // Unrated memos ARE 0 — three hollow balls, same readout as the phone's
        // quiet rows (D135's "display-only balls on rows" applies here too).
        m.balls = memo.locked ? nil : 0
        // The card's stamp already prints the date — hand the quiet line WITHOUT
        // its leading date (Tuur's first m2 eyeball catch, 2026-08-19), and WITHOUT
        // duration (Q35: mocks/one-notes-list.html's "One list" tab — the shared
        // `oneModel` — puts duration in the chip row for EVERY card, rated or not;
        // it never lives in the line text).
        // A RATED memo among the quiet rows is a stranded one (`WayOutRules.stranded`) —
        // the ordinary quiet rows are all unrated. It gets the honest waiting line rather
        // than the spine's "processes on next run", which it can't do without a row.
        m.quietLine = NoteConsent.isRated(memo) ? WayOutRules.strandedLine(for: memo)
                                                : WayOutRules.oneLiner(for: memo, backlinked: backlinkedIDs)
        m.selected = selected
        m.locked = memo.locked
        // Q106 (C115): the same shared builder the rated rows and the phone call — title,
        // quote, snippet, source / book / duration / place / tag chips (an unrated typed note
        // wears its "Note" chip, a video its "Video" chip).
        m.apply(NoteCardBuilder.content(for: memo.cardFacts()))
        return m
    }

    /// Open an unrated memo in the DETAIL PANE, the way the iPad opens any note
    /// (Tuur 2026-07-25: "when i click an unrated note on mac it shows me this popup.
    /// where instead it should copy the ipad where it just opens it"). Ordinary
    /// selection — the pane resolves which kind of note the id names. It does NOT
    /// become a `PipelineFile` first: the RATING is what pipelines a memo, so ingesting
    /// on a mere click would quietly process notes you only looked at.
    private func openInPane(_ memo: Memo) {
        model.select(memo.id.uuidString)
    }

    /// Lock (instant) / remove lock (device-owner auth) — the phone's `toggleLock` policy,
    /// via the shared `LockPolicy` (Q100, C161/C213). Locking a note this machine already
    /// exported says the plaintext file still exists.
    private func toggleLock(_ memo: Memo) {
        if memo.locked {
            Task {
                guard await LockGate.shared.policy.removeLock(memo) else { return }
                saveLockChange()
            }
        } else {
            guard LockGate.shared.policy.lock(memo) else {
                coordinator.flash("Set a device passcode to lock notes")
                return
            }
            saveLockChange()
            if LockVaultNotice.hasPublished(memo.id, settings: SettingsStore.shared.load()) { lockVaultNotice = true }
        }
    }

    private func saveLockChange() {
        saveCloudMemoChange()
        refreshCloudMemos()
    }

    /// Soft delete into the shared Recently Deleted (14 days, both devices). A locked
    /// note needs device-owner auth first (R88/C161).
    private func deleteQuiet(_ memo: Memo) {
        Task {
            guard await LockGate.shared.policy.authorizeDelete(id: memo.id.uuidString, locked: memo.locked) else { return }
            memo.deletedAt = Date()
            memo.trashSeenAt = memo.deletedAt   // deleted in-session — purge clock starts now (v3)
            saveCloudMemoChange()
            refreshCloudMemos()
        }
    }

    /// The rows in `cloudMemos` belong to the snapshot's own context (Q241 bug 5), so a change to
    /// them is saved THERE; saving `mainContext` wrote nothing.
    private func saveCloudMemoChange() {
        if let snap = cloudSnapshot { snap.save() } else { try? MemoCloudStore.container?.mainContext.save() }
    }


    private func refreshCloudMemos() {
        defer { backlinkedIDs = MemoLifecycle.backlinkedIDs(in: effectiveCloudMemos) }
        guard fixtureCloudMemos == nil else { return }   // snapshot fixtures: never open the real store
        guard let cloud = MemoCloudStore.container else { cloudMemos = []; return }
        // FRESH CONTEXT, not `mainContext` — the same trap `MemoCloudReconciler.reconcile`
        // documents and fixed for itself (2026-07-15): a CloudKit import writes to the
        // persistent STORE but does NOT refresh objects already registered with
        // `mainContext`, so it hands back STALE memos and a just-synced one is missing.
        // A brand-new context has an empty row cache, so every fetch hits the store.
        let snap = CloudMemoSnapshot(container: cloud)
        cloudSnapshot = snap
        cloudMemos = snap.memos
    }

    /// Search/filter excluded every memo (the queue itself isn't empty). Mirrors
    /// the phone's "No matches" so a too-narrow query never reads as "no memos".
    private var noMatches: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 22)).foregroundStyle(Theme.textMuted.opacity(0.5))
            Text("No matches").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Theme.textSecondary)
            if !model.searchText.isEmpty {
                Text("Nothing matches “\(model.searchText)”.")
                    .font(.system(size: 11.5)).foregroundStyle(Theme.textMuted)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 24)
        .accessibilityIdentifier("sidebar.no-matches")
    }

    /// First-run guidance when there are no notes yet (P2a).
    private var emptyQueue: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 26)).foregroundStyle(Theme.textMuted.opacity(0.5))
            Text("No memos yet").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.textSecondary)
            Text("Drop a voice memo here, click + \(SharedCopy.importVerb) above, or sync from your phone.")
                .font(.system(size: 11.5)).foregroundStyle(Theme.textMuted)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 24)
    }

    // ── Bottom bar — footer / selection action bar ──────────
    @ViewBuilder private var bottomBar: some View {
        if let rs = coordinator.runState {
            runBar(rs)
        } else if model.selection.count > 1 {
            selectionBar
        } else {
            footer
        }
    }

    @ViewBuilder private func runBar(_ rs: ProcessingCoordinator.RunState) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let label = rs.loadingLabel {
                HStack {
                    Text("Loading " + label)
                        .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Theme.accent)
                    Spacer()
                    if let f = rs.loadingFraction {
                        Text("\(Int(f * 100))%")
                            .font(.system(size: 11).monospacedDigit()).foregroundStyle(Theme.textSecondary)
                    }
                }
                progressTrack(rs.loadingFraction)
            } else {
                let pct = rs.total > 0 ? Double(rs.done) / Double(rs.total) : 0
                HStack {
                    Text(SharedCopy.processingCount(min(rs.done + 1, rs.total), of: rs.total))
                        .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Theme.accent)
                    Spacer()
                    Text("\(Int(pct * 100))%")
                        .font(.system(size: 11).monospacedDigit()).foregroundStyle(Theme.textSecondary)
                }
                if let title = rs.currentTitle {
                    Text(title).font(.system(size: 11)).foregroundStyle(Theme.textMuted).lineLimit(1)
                }
                progressTrack(pct)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .background(Theme.accent.opacity(0.10))
        .overlay(alignment: .top) { Rectangle().fill(Theme.hairline.opacity(0.07)).frame(height: 0.5) }
    }

    private func progressTrack(_ fraction: Double?) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.hairline.opacity(0.14)).frame(height: 5)
                Capsule().fill(Theme.accent)
                    .frame(width: geo.size.width * (fraction ?? 0.12), height: 5)
                    .opacity(fraction == nil ? 0.5 : 1)
            }
        }
        .frame(height: 5)
    }

    private var footer: some View {
        VStack(spacing: 0) {
            // No Recently Deleted entry here: it has ONE home, the Review conveyor row.
            HStack(spacing: 14) {
                engineDot("Parakeet")
                engineDot("Gemma 4")
                Spacer(minLength: 0)
            }
            .help(coordinator.modelsLoaded ? "Models loaded in memory" : "Models load on Process, freed after a minute idle")
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .overlay(alignment: .top) {
                Rectangle().fill(Theme.hairline.opacity(0.06)).frame(height: 0.5)
            }
        }
    }

    private func engineDot(_ name: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(coordinator.modelsLoaded ? Theme.green : Theme.textMuted.opacity(0.6))
                .frame(width: 6, height: 6)
            Text(name).font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
        }
    }

    private var selectionBar: some View {
        HStack(spacing: 7) {
            Text("\(model.selection.count) selected")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(maxWidth: .infinity, alignment: .leading)
            pillButton("Process", fg: .white, bg: Theme.accent) {
                let ids = Array(model.selection)
                model.selection.removeAll()
                Task { await coordinator.process(fileIDs: ids, context: ctx) }
            }
            pillButton("Delete", fg: Theme.destructive, bg: Theme.destructive.opacity(0.15)) { deleteSelected() }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(Theme.accent.opacity(0.09))
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.hairline.opacity(0.07)).frame(height: 0.5)
        }
    }

    private func pillButton(_ title: String, fg: Color, bg: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(fg)
                .padding(.horizontal, 11)
                .padding(.vertical, 4)
                .background(bg, in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    private func deleteSelected() {
        let ids = model.selection
        deleteFiles(files.filter { ids.contains($0.id) })
        model.selection.removeAll()
    }

    // ── Right-click context menu (multi-select aware) ───────
    /// Acts on the whole multi-selection when the clicked row is part of it, else
    /// just the clicked row.
    private func contextTargets(_ f: PipelineFile) -> [PipelineFile] {
        if model.selection.contains(f.id) && model.selection.count > 1 {
            return files.filter { model.selection.contains($0.id) }
        }
        return [f]
    }

    @ViewBuilder private func rowMenu(_ f: PipelineFile) -> some View {
        let targets = contextTargets(f)
        if targets.count > 1 {
            let pending = targets.filter { coordinator.needsProcessing($0) }
            if !pending.isEmpty {
                Button("Process \(pending.count)") { Task { await coordinator.process(fileIDs: pending.map(\.id), context: ctx) } }
            }
            let exportable = targets.filter { $0.steps.enhance == .done }
            if !exportable.isEmpty {
                Button("Export \(exportable.count) to Obsidian") {
                    Task { for t in exportable { await coordinator.export(t, context: ctx) } }
                }
            }
            Divider()
            Button("Delete \(targets.count)", role: .destructive) {
                deleteFiles(targets); model.selection.removeAll()
            }
        } else {
            if coordinator.needsProcessing(f) {
                Button("Process") { Task { await coordinator.process(fileIDs: [f.id], context: ctx) } }
            }
            // Re-transcribe re-runs ASR from the audio, which would DESTROY a
            // speaker-attributed transcript's turns (the phone never uploads the
            // diarization segments/word-timings — the `**Name:**` text is the only
            // copy). Hidden for diarized conversations (user decision); they re-enhance
            // via Redo instead, which keeps the transcript verbatim.
            if f.steps.transcribe == .done && f.sourceType != .note
                && !SpeakerTranscript.isAttributed(f.transcript) {
                Button("Re-transcribe") { Task { await coordinator.retranscribe(f, context: ctx) } }
            }
            // A wrongly-split monologue (Sortformer over-split) → flatten the `**Speaker N:**`
            // turns back to prose and re-enhance as a monologue (no re-ASR). Only for an
            // attributed AUDIO memo (a hand-formatted note with bold headings isn't one).
            if f.sourceType == .audio && SpeakerTranscript.isAttributed(f.transcript) {
                Button("Flatten to monologue") { Task { await coordinator.flattenToMonologue(f, context: ctx) } }
            }
            if f.steps.enhance == .done {
                let isConversation = f.sourceType == .audio && SpeakerTranscript.isAttributed(f.transcript)
                Menu("Redo") {
                    Button("Title") { Task { await coordinator.redo(.title, for: f, context: ctx) } }
                    // Copy-edit strips the `**Name:**` turn prefixes from a conversation
                    // — hidden for diarized memos (they stay verbatim, like the phone).
                    if !isConversation {
                        Button("Copy-edit") { Task { await coordinator.redo(.copyEdit, for: f, context: ctx) } }
                    }
                    Button("Summary") { Task { await coordinator.redo(.summary, for: f, context: ctx) } }
                }
                Button(f.steps.export == .done ? "Re-export to Obsidian" : "Export to Obsidian") {
                    Task { await coordinator.export(f, context: ctx) }
                }
            }
            Divider()
            Button("Reveal in Finder") { revealInFinder(f) }
            if f.steps.export == .done, let p = f.exported, !p.isEmpty {
                Button("Open in Obsidian") { openInObsidian(p) }
            }
            Menu("Copy") {
                Button("Transcript") { copyText(f.transcript ?? "") }
                Button("Markdown") { copyText(f.compiledText ?? Compiler.compile(file: f, author: SettingsStore.shared.load().authorName, knownPeople: NamesStore.shared.livePeople())) }
            }
            // Locked note: copying leaks the gated content — unlock in the note view first.
            .disabled(LockGate.shared.isLocked(f))
            Divider()
            Button("Delete", role: .destructive) { deleteFiles([f]) }
        }
    }

    private func revealInFinder(_ f: PipelineFile) {
        let path = (f.exported?.isEmpty == false) ? f.exported! : f.path
        guard !path.isEmpty, FileManager.default.fileExists(atPath: path) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    private func openInObsidian(_ mdPath: String) {
        if let enc = mdPath.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
           let url = URL(string: "obsidian://open?path=\(enc)"), NSWorkspace.shared.open(url) { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: mdPath))   // fallback: default md app
    }

    private func copyText(_ s: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
    }
}

// ── Promised-file drop (drag from Photos / Mail / Safari) ───
/// Bridges AppKit file-promise drags into the SwiftUI sidebar. Registered ONLY for
/// `NSFilePromiseReceiver` types, so plain Finder URL drags fall through to the
/// SwiftUI `.dropDestination` underneath (this view would win the drag-destination
/// search otherwise, being the deeper registered view). Click-through for normal
/// mouse events: `hitTest` returns nil — drag routing matches on registered dragged
/// types, not on `hitTest`.
private struct FilePromiseDropCatcher: NSViewRepresentable {
    @Binding var isTargeted: Bool
    var onDrop: ([URL], (() -> Void)?) -> Void

    func makeNSView(context: Context) -> PromiseDropView {
        let view = PromiseDropView()
        update(view)
        return view
    }

    func updateNSView(_ view: PromiseDropView, context: Context) { update(view) }

    private func update(_ view: PromiseDropView) {
        view.onTargeted = { isTargeted = $0 }
        view.onDrop = onDrop
    }
}

final class PromiseDropView: NSView {
    var onTargeted: (Bool) -> Void = { _ in }
    var onDrop: ([URL], (() -> Void)?) -> Void = { _, _ in }

    private static let log = Logger(subsystem: "com.skrift.desktop", category: "ingest")
    /// Serial queue the promises write their files on (Apple's recommended shape).
    private static let promiseQueue: OperationQueue = {
        let q = OperationQueue()
        q.maxConcurrentOperationCount = 1
        return q
    }()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerPromiseTypes()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerPromiseTypes()
    }

    private func registerPromiseTypes() {
        registerForDraggedTypes(NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) })
    }

    /// Click-through: normal mouse events pass to the SwiftUI content below.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        onTargeted(true)
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) { onTargeted(false) }
    override func draggingEnded(_ sender: NSDraggingInfo) { onTargeted(false) }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pb = sender.draggingPasteboard
        let promises = (pb.readObjects(forClasses: [NSFilePromiseReceiver.self]) as? [NSFilePromiseReceiver]) ?? []
        if !promises.isEmpty {
            receive(promises)
            return true
        }
        // Promise types matched but no receiver materialized — fall back to any real
        // file URLs on the pasteboard rather than dropping the drag on the floor.
        let urls = (pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        guard !urls.isEmpty else {
            Self.log.warning("promise drop had no receivers and no file URLs")
            return false
        }
        onDrop(urls, nil)
        return true
    }

    /// Ask each promise to write its file(s) into a fresh temp folder, then hand the
    /// resolved URLs to `onDrop` on main. `IngestService` COPIES into its own working
    /// folders, so the temp folder is removed right after.
    private func receive(_ promises: [NSFilePromiseReceiver]) {
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("skrift-drop-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        } catch {
            Self.log.error("promise drop temp dir failed: \(String(describing: error), privacy: .public)")
            return
        }
        let group = DispatchGroup()
        let lock = NSLock()
        var received: [URL] = []
        for promise in promises {
            // A receiver can carry several files; the reader runs once per file. Track
            // a clamped per-promise count so an extra callback can't over-leave.
            var remaining = max(1, promise.fileNames.count)
            for _ in 0..<remaining { group.enter() }
            promise.receivePromisedFiles(atDestination: dest, options: [:], operationQueue: Self.promiseQueue) { url, error in
                lock.lock()
                let counted = remaining > 0
                if counted { remaining -= 1 }
                if let error {
                    Self.log.error("promised file failed: \(String(describing: error), privacy: .public)")
                } else {
                    received.append(url)
                }
                lock.unlock()
                if counted { group.leave() }
            }
        }
        let deliver = onDrop   // capture the handler as of drop time
        group.notify(queue: .main) {
            let urls = received.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            // The temp folder must outlive the C68 chooser (Q74): the sidebar asks "One note
            // or N notes?" BEFORE it ingests, so it owns the cleanup and calls it once the
            // files are copied (or the sheet is cancelled).
            let cleanup = { try? FileManager.default.removeItem(at: dest) }
            if urls.isEmpty { cleanup() } else { deliver(urls, { cleanup() }) }
        }
    }
}

// ── Row ─────────────────────────────────────────────────────
private struct QueueRowView: View {
    let file: PipelineFile
    let selected: Bool
    let onTap: () -> Void
    @State private var hovering = false

    /// m2 adapter (chunk 3 of the un-twinning): the row's derivations feed the
    /// SHARED NoteCardView — the same card the iPad draws ("make sure the ipad
    /// also follows that one to the T"). Thumbnails are chunk 3b (need a cached
    /// loader; an uncached per-row decode would drag the whole sidebar).
    var body: some View {
        NoteCardView(model: cardModel, style: .mac)
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)
            .onHover { hovering = $0 }
            .opacity(hovering && !selected ? 0.92 : 1)
            .animation(.easeInOut(duration: 0.12), value: hovering)
    }

    private var cardModel: NoteCardModel {
        // D135: the Mac's stamp gains the time + day word ("Today · 14:32"),
        // matching the phone/iPad instead of the old lowercase "today".
        var m = NoteCardModel(stamp: MemoDate.label(file.uploadedAt))
        m.selected = selected
        m.balls = ThreeBallScale.step(for: file.significance)
        let st = file.queueStatus
        let kind: NoteCardModel.Pill.Kind = switch st {
        case .error: .error
        case .queued, .transcribing, .enhancing: .progress
        case .exported: .done
        case .transcribed, .ready: .done
        }
        m.statusPill = .init(label: st.label, kind: kind, pulses: st.pulses)
        // D139: two versions replace Enhancing (and every other state) in the pill slot.
        if let id = UUID(uuidString: file.id), EditConflictWatch.shared.ids.contains(id) {
            m.statusPill = .twoVersions
        }
        // Locked ⇒ title + 🔒 (+ the status pill, as on the phone) and NOTHING else —
        // no words, balls or chips (C91/C161, R88; the phone's `cardModel` rule).
        if file.locked {
            var l = LockedRow.card(stamp: m.stamp, title: LockedRow.title(for: file),
                                   selected: selected, quiet: false)
            l.statusPill = m.statusPill
            return l
        }
        // Q106 (C115/C78/C172): title, quote, snippet and chips come from the ONE shared
        // builder the phone's `MemoCard` and the quiet rows call — a book capture's quote +
        // "Book · ch. N" chip, a video's source chip, a capture's title + domain chip all
        // arrive through `file.cardFacts` (a book capture and a video are both `.audio`
        // rows, so the old `sourceType != .audio` chip test never saw them).
        m.apply(NoteCardBuilder.content(for: file.cardFacts))
        return m
    }
}

/// One list, two row kinds (rated pipeline rows + quiet unrated memos).
enum SidebarEntry: Identifiable {
    case file(PipelineFile)
    case memo(Memo)

    var id: String {
        switch self {
        case .file(let f): return "pf-" + f.id
        case .memo(let m): return "memo-" + m.id.uuidString
        }
    }
    var date: Date {
        switch self {
        case .file(let f): return f.uploadedAt
        case .memo(let m): return m.recordedAt
        }
    }
    var title: String {
        switch self {
        // Locked: the sort key is the placeholder-safe title, never the hidden first line.
        case .file(let f): return f.locked ? LockedRow.title(for: f) : f.queueTitle
        case .memo(let m): return m.locked ? LockedRow.title(for: m) : WayOutRules.displayTitle(m)
        }
    }
}

/// The Mac's colors for the shared m2 note card — Theme tokens mapped ONCE
/// (the SignificanceStyle pattern; the iPad's twin lives in MemosListView).
extension NoteCardStyle {
    static let mac = NoteCardStyle(
        accent: Theme.accent, accentSoft: Theme.accent.opacity(0.16),
        accentText: Theme.accentText,
        text: Theme.textPrimary, textDim: Theme.textSecondary, textFaint: Theme.textMuted,
        amber: Theme.amber, green: Theme.green, red: Theme.destructive,
        chipFill: Theme.hairline.opacity(0.07),
        // D136: rows become white cards on the sidebar's new grey ground (was a
        // near-transparent wash meant to blend into the old white sidebar).
        surface: Theme.surface,
        border: Theme.hairline.opacity(0.16))
}
