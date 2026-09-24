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
    /// The Mac's ONE live take (RootView owns it — LANES-2026-07-28/BRIEF_LIVEUI.md §7).
    /// The header's Record/stop buttons and the synthetic queue row read/drive it; the
    /// direct `MacRecorder` this view used to own is gone — the session owns the
    /// recorder now, and the pane (RootView) renders the same session's draft.
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

    private var filtered: [PipelineFile] { model.visible(files) }
    /// `filtered` minus a quiet local take (unrated, error-free Mac recording — the
    /// unrated-take doctrine, 2026-07-28): it never renders as a lit `QueueRowView`,
    /// so it must not sit in the ordered/selectable row list either. Its twin `Memo`
    /// renders instead via `quietMemoRow` (see `unpipelinedMemos`/`WayOutRules`).
    private var queueRowFiles: [PipelineFile] { filtered.filter { !WayOutRules.isQuietLocalTake($0) } }
    private var orderedIDs: [String] { queueRowFiles.map(\.id) }
    private var queuedCount: Int { files.filter { $0.queueStatus == .queued }.count }
    /// D135: "Each chip counts its own notes" — Needs Work / Done / Unrated, over
    /// ALL live items (not the filtered view), like the old triage line's counts.
    private var chipCounts: [QueueFilter: Int] {
        NotesListModel.chipCounts(
            needsWork: files.filter { !model.isComplete($0) }.count,
            done: files.filter { model.isComplete($0) }.count,
            notRated: unpipelinedMemos.count)
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
    @State private var showFilterPopover = false

    // ── the Queue band (mocks/lifecycle-ia-explorations.html #m2) ───────────
    /// Cloud memos, refreshed on appear / when `files` changes / after any band
    /// Process action — the source for both the band's membership and (once
    /// step ③ lands) the one-trash footer count.
    @State private var cloudMemos: [Memo] = []
    /// Row-tap peek (read-only + Flag) — same sheet the Review river uses.
    private var effectiveCloudMemos: [Memo] { fixtureCloudMemos ?? cloudMemos }
    private var unpipelinedMemos: [Memo] { WayOutRules.unpipelined(memos: effectiveCloudMemos, files: files) }
    /// Rated memos with no pipeline row — see `WayOutRules.stranded`. Kept apart from
    /// `unpipelinedMemos` on purpose: these are RATED, so they must not swell the "N not
    /// rated" count or the Process-all set. They only need to be SEEN.
    private var strandedMemos: [Memo] { WayOutRules.stranded(memos: effectiveCloudMemos, files: files) }
    private var backlinkedIDs: Set<UUID> { MemoLifecycle.backlinkedIDs(in: effectiveCloudMemos) }

    var body: some View {
        VStack(spacing: 0) {
            SurfaceSwitch(model: model)
                .padding(.horizontal, 10).padding(.top, 10)
            header
            queue
            bottomBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        .overlay { FilePromiseDropCatcher(isTargeted: $dragOver) { ingest($0) } }
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
    private func ingest(_ urls: [URL], asRecording: Bool = false) {
        guard !urls.isEmpty else { return }
        // Async: the heavy file work (copies, video-audio export) runs off-main
        // inside IngestService — dropping a video used to beachball the whole
        // UI for the duration of the export.
        Task { @MainActor in
            do {
                try await ArrivalPath.run(
                    urls: urls, asRecording: asRecording, into: ctx,
                    cloudContext: MemoCloudStore.container?.mainContext,
                    hooks: .live(coordinator: coordinator, context: ctx),
                    // Select as soon as the row exists — not after transcription, which for a
                    // recording runs inside this same call and can take a while.
                    onCreated: { created in
                        if let first = created.first {
                            model.activeID = first.id
                            model.selection = [first.id]
                        }
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
                    actionButton(title: SharedCopy.importVerb, system: "plus", filled: false) { openUploadPanel() }
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
                Text("Record")
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

    /// Create the typed note and open it — a fresh unrated Memo in the CLOUD store
    /// (`MacMemoAuthor.typedNote`), selected by id: no pipeline row exists, so RootView
    /// resolves the id to the unrated pane, which is the editor. The quiet row appears
    /// via the same refresh the sweeps use.
    private func newTypedNote() {
        guard let cloud = MemoCloudStore.container,
              let memo = try? MacMemoAuthor.typedNote(into: cloud.mainContext) else { return }
        refreshCloudMemos()
        model.select(memo.id.uuidString)
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

    private func actionButton(title: String, system: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: system).font(.system(size: 11, weight: .semibold))
                Text(title)
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

    private var filterChips: some View {
        HStack(spacing: 5) {
            ForEach(QueueFilter.allCases, id: \.self) { f in
                let on = model.filter == f
                HStack(spacing: 3) {
                    Text(f.rawValue)
                    // D135: "All carries no number" — the other three show the
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
            Spacer(minLength: 0)
            filterControl
        }
    }

    /// ONE Filter control (Tuur 2026-07-23: "that filter button should also be
    /// on the Mac… similar between them") — icon-only now (D136: "Filter" the
    /// word doesn't fit next to four counted chips), ending the chip bar like
    /// the phone/iPad. A Button (not a Menu — a Menu can't render in
    /// `ImageRenderer`, the snapshot harness) that toggles a popover; the
    /// popover is unpresented at render time, so snapshots stay clean.
    private var filterControl: some View {
        Button { showFilterPopover.toggle() } label: {
            Image(systemName: "line.3.horizontal.decrease")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(model.dateFilterActive ? Theme.accent : Theme.textSecondary)
                .padding(6)
                .background(Theme.hairline.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .help("Sort & filter")
        .accessibilityIdentifier("sidebar.filter")
        .popover(isPresented: $showFilterPopover, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Sort & Filter").font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 6)
                Text("SORT").font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.textMuted).padding(.horizontal, 16).padding(.top, 4)
                ForEach(SidebarSort.allCases, id: \.self) { s in
                    Button { model.sort = s } label: {
                        HStack {
                            Text(s.rawValue).font(.system(size: 13))
                            Spacer()
                            if model.sort == s {
                                Image(systemName: "checkmark").font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Theme.accent)
                            }
                        }
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                Divider().padding(.horizontal, 16).padding(.vertical, 6)
                Text("FILTER BY DATE (UPLOADED)").font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.textMuted).padding(.horizontal, 16)
                datePickerRow(label: "From", isOn: fromEnabled, date: fromBinding)
                datePickerRow(label: "To", isOn: toEnabled, date: toBinding)
                if model.dateFilterActive {
                    Button { model.dateFrom = nil; model.dateTo = nil } label: {
                        Text("Clear dates").font(.system(size: 12))
                            .foregroundStyle(Theme.accent)
                            .padding(.horizontal, 16).padding(.top, 4)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(width: 260)
            .padding(.bottom, 12)
        }
    }

    /// One "From/To" row: a toggle that arms the bound (today by default) + a
    /// DatePicker shown once armed. Mirrors the iPad sheet's date rows.
    @ViewBuilder private func datePickerRow(label: String, isOn: Binding<Bool>, date: Binding<Date>) -> some View {
        HStack {
            Toggle(label, isOn: isOn).toggleStyle(.checkbox).font(.system(size: 12.5))
            Spacer()
            if isOn.wrappedValue {
                DatePicker("", selection: date, displayedComponents: .date)
                    .labelsHidden().datePickerStyle(.field).controlSize(.small)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 3)
    }

    private var fromEnabled: Binding<Bool> {
        Binding(get: { model.dateFrom != nil },
                set: { model.dateFrom = $0 ? Calendar.current.startOfDay(for: Date()) : nil })
    }
    private var toEnabled: Binding<Bool> {
        Binding(get: { model.dateTo != nil }, set: { model.dateTo = $0 ? Date() : nil })
    }
    private var fromBinding: Binding<Date> {
        Binding(get: { model.dateFrom ?? Date() }, set: { model.dateFrom = $0 })
    }
    private var toBinding: Binding<Date> {
        Binding(get: { model.dateTo ?? Date() }, set: { model.dateTo = $0 })
    }

    // D136/D137: the triage line ("N ready to review · N to process") and its
    // "Mark all as Passing" bulk-rate button are GONE — "rating a note should be
    // an intentional choice". The chips now carry the counts (`chipCounts`
    // below); Process is unaffected, it already showed its own pile size.

    // ── Queue ───────────────────────────────────────────────
    @ViewBuilder private var queue: some View {
        let rows = entries
        // A live take pins its own synthetic row (below) whether or not there's anything
        // else to show — an empty vault mid-first-recording is not the "No memos yet" state.
        if files.isEmpty && unpipelinedMemos.isEmpty && !sessionBusy {
            emptyQueue
        } else if rows.isEmpty && !sessionBusy {
            noMatches
        } else {
            // Plain VStack (not Lazy) is fine for a personal-scale vault; revisit
            // windowing (List / lazy) only if a very large queue shows scroll jank.
            // D136: day groups, new on the Mac — the SAME `MemoDate.group` key the
            // phone/iPad use, via the shared `NotesListModel.dayGroups`, so a day
            // header reads the same word everywhere.
            let content = VStack(alignment: .leading, spacing: 10) {
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
                    VStack(alignment: .leading, spacing: 6) {
                        if !group.title.isEmpty {
                            Text(group.title.uppercased())
                                .font(.system(size: 10.5, weight: .bold))
                                .kerning(0.4)
                                .foregroundStyle(Theme.textMuted)
                                .padding(.horizontal, 4)
                        }
                        ForEach(group.items) { entry in
                            switch entry {
                            case .file(let f):
                                QueueRowView(file: f, selected: model.selection.contains(f.id)) {
                                    model.handleClick(f.id, in: orderedIDs)
                                }
                                .contextMenu { rowMenu(f) }
                            case .memo(let m):
                                quietMemoRow(m)
                            }
                        }
                    }
                }
            }
            .padding(8)

            if scrollable {
                ScrollView { content }
            } else {
                VStack(spacing: 0) { content; Spacer(minLength: 0) }
            }
        }
    }

    // ── Quiet rows — unrated notes IN the list (Tuur, 2026-07-21 round 3:
    // the separate band container confused even the owner; the phone's Notes
    // list shows everything, so this one does too). Membership stays
    // WayOutRules.unpipelined (quiet clock-run notes; fading lives on the
    // conveyor, locked notes are resolved and don't nag — m6 2026-07-22).
    // No selection semantics — a quiet row taps open the peek, where the
    // circles live. Right-click carries the fast verbs (Flag/Lock/Delete).
    // Rated rows keep the full click/selection machinery.

    private var visibleMemoRows: [Memo] {
        // Stranded notes ride every filter chip except Not-rated: a rated note with no row
        // can't answer "needs work" or "done" (both read a `PipelineFile` it doesn't have),
        // and being unfindable is the exact bug they exist to prevent. Not-rated excludes
        // them because they ARE rated.
        var rows = model.filter == .notRated ? [] : strandedMemos
        if model.filter == .all || model.filter == .notRated {
            rows += unpipelinedMemos
            // Search honesty (no-bad-info, 2026-07-21): while SEARCHING, fading
            // notes are findable here too — their one-liner ("moves to Recently
            // Deleted in Nd") is the marker. Browse mode keeps the one-home law
            // (fading's surface is the conveyor).
            if !model.searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                let ingested = Set(files.compactMap { UUID(uuidString: $0.id) })
                rows += MemoLifecycle.partition(effectiveCloudMemos).fading.filter {
                    !NoteConsent.isRated($0) && !ingested.contains($0.id)
                }
            }
        }
        return rows.filter { WayOutRules.matchesSearch($0, query: model.searchText) }
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
        // Quiet rows render the SAME shared card, dimmed (m2): quiet ≠ urgent,
        // the spine one-liner rides the stamp slot, no pill, no verbs.
        let selected = model.selection.contains(memo.id.uuidString)
        var m = NoteCardModel(stamp: MemoDate.label(memo.recordedAt))
        m.quiet = true
        // Unrated memos ARE 0 — three hollow balls, same readout as the phone's
        // quiet rows (D135's "display-only balls on rows" applies here too).
        m.balls = memo.locked ? nil : 0
        // The card's stamp already prints the date — hand the quiet line WITHOUT
        // its leading date or the row reads "07 Aug · 7 Aug · …" (Tuur's first
        // m2 eyeball catch, 2026-08-19).
        // A RATED memo among the quiet rows is a stranded one (`WayOutRules.stranded`) —
        // the ordinary quiet rows are all unrated. It gets the honest waiting line rather
        // than the spine's "processes on next run", which it can't do without a row.
        var line = NoteConsent.isRated(memo) ? WayOutRules.strandedLine(for: memo)
                                             : WayOutRules.oneLiner(for: memo, backlinked: backlinkedIDs)
        if memo.duration > 0 { line = "\(SkriftFormat.clock(memo.duration)) · \(line)" }
        m.quietLine = line
        m.selected = selected
        m.locked = memo.locked
        m.title = WayOutRules.displayTitle(memo)
        return NoteCardView(model: m, style: .mac)
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

    /// Open an unrated memo in the DETAIL PANE, the way the iPad opens any note
    /// (Tuur 2026-07-25: "when i click an unrated note on mac it shows me this popup.
    /// where instead it should copy the ipad where it just opens it"). Ordinary
    /// selection — the pane resolves which kind of note the id names. It does NOT
    /// become a `PipelineFile` first: the RATING is what pipelines a memo, so ingesting
    /// on a mere click would quietly process notes you only looked at.
    private func openInPane(_ memo: Memo) {
        model.select(memo.id.uuidString)
    }

    private func toggleLock(_ memo: Memo) {
        memo.locked.toggle()
        try? MemoCloudStore.container?.mainContext.save()
        refreshCloudMemos()
    }

    /// Soft delete into the shared Recently Deleted (14 days, both devices).
    private func deleteQuiet(_ memo: Memo) {
        memo.deletedAt = Date()
        memo.trashSeenAt = memo.deletedAt   // deleted in-session — purge clock starts now (v3)
        try? MemoCloudStore.container?.mainContext.save()
        refreshCloudMemos()
    }


    private func quietMeta(_ memo: Memo) -> String {
        let date = memo.recordedAt.formatted(.dateTime.day().month(.abbreviated))
        let one = WayOutRules.oneLiner(for: memo, backlinked: backlinkedIDs)
        guard memo.duration > 0 else { return "\(date) · \(one)" }
        return "\(date) · \(SkriftFormat.clock(memo.duration)) · \(one)"
    }

    private func refreshCloudMemos() {
        guard fixtureCloudMemos == nil else { return }   // snapshot fixtures: never open the real store
        guard let cloud = MemoCloudStore.container else { cloudMemos = []; return }
        // FRESH CONTEXT, not `mainContext` — the same trap `MemoCloudReconciler.reconcile`
        // documents and fixed for itself (2026-07-15): a CloudKit import writes to the
        // persistent STORE but does NOT refresh objects already registered with
        // `mainContext`, so it hands back STALE memos and a just-synced one is missing.
        // A brand-new context has an empty row cache, so every fetch hits the store.
        cloudMemos = (try? ModelContext(cloud).fetch(FetchDescriptor<Memo>())) ?? []
    }

    /// Q2: the one-click minimum flag — same cloud write lane as Keep/Restore
    /// (FadingShelfColumn's `keptAt` precedent), just a different field. Then
    /// kick the reconcile sweep (read-only call into `MemoCloudReconciler`,
    /// which LANE_AUTHOR owns) so the new queue row appears promptly.
    private func process(_ memo: Memo) {
        memo.significance = 0.1
        try? MemoCloudStore.container?.mainContext.save()
        MemoCloudReconciler.reconcileSoon()
        refreshCloudMemos()
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
            Text("Drop a voice memo here, click + Upload above, or sync from your phone.")
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
            // (The "Recently Deleted · in Review" footer row lived here 2026-07-21
            // for a few hours — Tuur's eyeball round cut it: Recently Deleted has
            // ONE home, the Review conveyor row, and a second entry point from the
            // notes list read as a second place.)
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
                Button("Export \(exportable.count) to Obsidian") { for t in exportable { coordinator.export(t, context: ctx) } }
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
                Button(f.steps.export == .done ? "Re-export to Obsidian" : "Export to Obsidian") { coordinator.export(f, context: ctx) }
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
    var onDrop: ([URL]) -> Void

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
    var onDrop: ([URL]) -> Void = { _ in }

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
        onDrop(urls)
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
            if !urls.isEmpty { deliver(urls) }
            try? FileManager.default.removeItem(at: dest)   // ingest copied; temp done
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
        let body = (file.sanitised ?? file.enhancedCopyedit ?? file.transcript ?? "")
            .replacingOccurrences(of: #"\[\[img_\d+\]\]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\n{2,}"#, with: "\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // The raw filename leak (Tuur's 11:26 screenshot): the filename arm of
        // displayTitle never belongs on a CARD — a row with neither a title nor a word of
        // body falls to the shared taxonomy word instead. Tested by the filename SHAPE
        // before ("memo_…"), which missed every other shape a filename can take — the
        // typed-note rows ingested since 2026-08-20 are named `<uuid>.md`.
        let named = !(file.enhancedTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "").isEmpty
        if named {
            m.title = file.queueTitle
            m.snippet = body.isEmpty ? nil : body
        } else if file.firstBodyLine != nil {
            // Q26 fix (BUGS §4 untitled-row repeat): an untitled row used to fall
            // back to `queueTitle` (= the opening line) for the title AND show the
            // full body — starting with that SAME line — as the snippet, so the
            // row read its own first line twice. The phone's `MemoCard` never has
            // this bug because it leaves `title` nil for an untitled note (mirrored
            // here): the body alone carries the row.
            m.snippet = body.isEmpty ? file.firstBodyLine : body
        } else {
            m.title = file.sourceDescriptor.label
        }
        if let dur = file.durationString { m.chips.append(.init(text: dur)) }
        if file.sourceType != .audio {
            m.chips.append(.init(text: file.sourceDescriptor.label, systemImage: file.sourceDescriptor.glyph))
        }
        return m
    }
}

extension View {
    /// ONE selected/hover chrome for every sidebar row kind — rated `QueueRowView`
    /// and the quiet unrated rows — so "which note is open" reads identically down
    /// the whole list (Tuur, 2026-07-28: "no way to see what node I have selected";
    /// the old treatment was a 0.13 wash the quiet rows didn't even have). The
    /// accent wash + accent edge is the app's active-state idiom (the filter chips'
    /// tint family), turned up enough to be unmissable on `Theme.surface`.
    func sidebarRowSelection(_ selected: Bool, hovering: Bool = false) -> some View {
        background(selected ? Theme.accent.opacity(0.20)
                   : hovering ? Theme.hairline.opacity(0.04) : .clear,
                   in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8)
            .stroke(selected ? Theme.accent.opacity(0.55) : .clear, lineWidth: 1))
    }
}

private struct StatusPill: View {
    let status: QueueStatus
    var body: some View {
        HStack(spacing: 4) {
            if status.pulses { PulseDot(color: status.color) }
            Text(status.label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(status.color)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(status.tint, in: Capsule())
        .fixedSize()
    }
}

private struct PulseDot: View {
    let color: Color
    @State private var on = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 6, height: 6)
            .opacity(reduceMotion ? 1 : (on ? 1 : 0.35))
            .animation(reduceMotion ? nil : .easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: on)
            .onAppear { if !reduceMotion { on = true } }
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
        case .file(let f): return f.queueTitle
        case .memo(let m): return WayOutRules.displayTitle(m)
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
