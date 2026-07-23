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
    var onOpenSettings: () -> Void = {}
    /// Snapshot mode renders the queue without a ScrollView (ImageRenderer can't
    /// lay out scroll contents). The live app keeps `true` for real scrolling.
    var scrollable = true
    @Environment(\.modelContext) private var ctx

    private var filtered: [PipelineFile] { model.visible(files) }
    private var orderedIDs: [String] { filtered.map(\.id) }
    private var readyCount: Int { files.filter { $0.queueStatus == .ready }.count }
    private var queuedCount: Int { files.filter { $0.queueStatus == .queued }.count }
    private var pendingFiles: [PipelineFile] {
        files.filter { $0.queueStatus == .queued || $0.queueStatus == .transcribed }
    }
    private var pendingCount: Int { pendingFiles.count }
    @State private var dragOver = false

    // ── the Queue band (mocks/lifecycle-ia-explorations.html #m2) ───────────
    /// Cloud memos, refreshed on appear / when `files` changes / after any band
    /// Process action — the source for both the band's membership and (once
    /// step ③ lands) the one-trash footer count.
    @State private var cloudMemos: [Memo] = []
    /// Row-tap peek (read-only + Flag) — same sheet the Review river uses.
    @State private var bandPeek: WayOutPeek?
    private var unpipelinedMemos: [Memo] { WayOutRules.unpipelined(memos: cloudMemos, files: files) }
    private var backlinkedIDs: Set<UUID> { MemoLifecycle.backlinkedIDs(in: cloudMemos) }

    var body: some View {
        VStack(spacing: 0) {
            SurfaceSwitch(model: model)
                .padding(.horizontal, 10).padding(.top, 10)
            header
            triageLine
            queue
            bottomBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.sidebar)
        .task { refreshCloudMemos() }
        .onChange(of: files.count) { _, _ in refreshCloudMemos() }
        .onChange(of: model.filter) { _, _ in refreshCloudMemos() }
        .overlay(alignment: .trailing) {
            Rectangle().fill(Theme.hairline.opacity(0.07)).frame(width: 0.5)
        }
        .sheet(item: $bandPeek) { target in
            UnpipelinedMemoSheet(memoID: target.id,
                                 backlinked: backlinkedIDs,
                                 onClose: { bandPeek = nil },
                                 onProcessed: { _ in bandPeek = nil; refreshCloudMemos() },
                                 onDeleted: { _ in bandPeek = nil; refreshCloudMemos() })
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

    private func ingest(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        // Async: the heavy file work (copies, video-audio export) runs off-main
        // inside IngestService — dropping a video used to beachball the whole
        // UI for the duration of the export.
        Task { @MainActor in
            do {
                let created = try await IngestService().ingest(localURLs: urls, into: ctx)
                if let first = created.first {
                    model.activeID = first.id
                    model.selection = [first.id]
                }
                // Backfill the real RECORDING date from the audio's embedded metadata —
                // the filesystem date is the import/copy date, not when it was recorded.
                // (Async; survives copies because the date lives inside the m4a.)
                let audio = created.filter { $0.sourceType == .audio }
                for pf in audio {
                    if let d = await AudioMetadata.recordingDate(of: URL(fileURLWithPath: pf.path)) {
                        pf.uploadedAt = d
                    }
                }
                if !audio.isEmpty { try? ctx.save() }
                // A Mac capture becomes a synced Memo NOW, not on the next sweep
                // trigger — reconcile runs MacMemoAuthor.backfill for the new rows.
                MemoCloudReconciler.reconcileSoon()
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

            HStack(spacing: 7) {
                actionButton(title: "Upload", system: "plus", filled: false) { openUploadPanel() }
                processButton
            }

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

    private var canProcess: Bool { pendingCount > 0 && !coordinator.isRunning }

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
            TextField("Search memos", text: $model.searchText)
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
                Text(f.rawValue)
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
            }
            Spacer(minLength: 0)
        }
    }

    /// Queue ordering, trailing the filter chips. A compact cycle button (Newest →
    /// Oldest → Title) rather than a Menu: a Menu can't render in `ImageRenderer`
    /// (the snapshot harness) and poisoned the whole sidebar render — a plain
    /// Button+Text renders cleanly and is the same chip idiom as the filters.
    private var sortControl: some View {
        Button { model.sort = model.sort.next } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.up.arrow.down").font(.system(size: 9, weight: .semibold))
                Text(model.sort.short).font(.system(size: 10.5, weight: .medium))
            }
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Theme.hairline.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .help("Sort: \(model.sort.rawValue) — tap to change")
        .accessibilityIdentifier("sidebar.sort")
    }

    // ── Triage line — what needs ME right now ───────────────
    @ViewBuilder private var triageLine: some View {
        HStack(spacing: 0) {
            if model.filter == .notRated {
                Text("\(unpipelinedMemos.count) not rated")
                    .foregroundStyle(Theme.textSecondary).fontWeight(.semibold)
                Spacer(minLength: 6)
                if !unpipelinedMemos.isEmpty {
                    capsuleButton("Flag all", prominent: false) {
                        processAll(unpipelinedMemos)
                    }
                    .accessibilityIdentifier("sidebar.flag-all")
                }
                sortControl.padding(.leading, 6).fixedSize()
            } else {
                // Two counts + sort ONLY — a third count wrapped the line
                // (Tuur's screenshot; the Unrated chip carries that number now).
                Text("\(readyCount) ready to review")
                    .foregroundStyle(Theme.accent).fontWeight(.semibold)
                if pendingCount > 0 {
                    Text(" · \(pendingCount) to process").foregroundStyle(Theme.textMuted)
                }
                Spacer(minLength: 0)
                sortControl.fixedSize()
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.85)
        .font(.system(size: 11))
        .contentShape(Rectangle())   // whole-line hover target — the tooltip was unreachable between texts
        .help("""
        Ready to review — the Mac finished these: transcript cleaned, title + summary written. Open one to check it; export sends it to Obsidian.
        To process — waiting for the Process button (transcribe + enhance).
        Unrated — synced from your phone without a rating; the Mac skips them until you flag one.
        """)
        .padding(.horizontal, 14)
        .padding(.top, 9)
        .padding(.bottom, 4)
    }

    // ── Queue ───────────────────────────────────────────────
    @ViewBuilder private var queue: some View {
        let rows = entries
        if files.isEmpty && unpipelinedMemos.isEmpty {
            emptyQueue
        } else if rows.isEmpty {
            noMatches
        } else {
            // Plain VStack (not Lazy) is fine for a personal-scale vault; revisit
            // windowing (List / lazy) only if a very large queue shows scroll jank.
            let content = VStack(spacing: 2) {
                ForEach(rows) { entry in
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
        guard model.filter == .all || model.filter == .notRated else { return [] }
        var rows = unpipelinedMemos
        // Search honesty (no-bad-info, 2026-07-21): while SEARCHING, fading
        // notes are findable here too — their one-liner ("moves to Recently
        // Deleted in Nd") is the marker. Browse mode keeps the one-home law
        // (fading's surface is the conveyor).
        if !model.searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            let ingested = Set(files.compactMap { UUID(uuidString: $0.id) })
            rows += MemoLifecycle.partition(cloudMemos).fading.filter {
                $0.significance == 0 && !ingested.contains($0.id)
            }
        }
        return rows.filter { WayOutRules.matchesSearch($0, query: model.searchText) }
    }

    /// One list, two row kinds, interleaved by the active sort.
    private var entries: [SidebarEntry] {
        var out: [SidebarEntry] = filtered.map { .file($0) }
        out.append(contentsOf: visibleMemoRows.map { .memo($0) })
        switch model.sort {
        case .newest: out.sort { $0.date > $1.date }
        case .oldest: out.sort { $0.date < $1.date }
        case .title:  out.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        }
        return out
    }

    private func quietMemoRow(_ memo: Memo) -> some View {
        HStack(spacing: 8) {
            Image(systemName: WayOutRules.sourceGlyph(for: memo))
                .font(.system(size: 10.5)).foregroundStyle(Theme.textMuted).frame(width: 14)
            VStack(alignment: .leading, spacing: 1) {
                Text(WayOutRules.displayTitle(memo))
                    .font(.system(size: 12.5)).foregroundStyle(Theme.textSecondary).lineLimit(1)
                Text(quietMeta(memo)).font(.system(size: 10)).foregroundStyle(Theme.textMuted).lineLimit(1)
            }
            Spacer(minLength: 6)
            // The hollow circle = the unfilled significance circles' own idiom.
            Image(systemName: "circle")
                .font(.system(size: 8)).foregroundStyle(Theme.textMuted.opacity(0.7))
        }
        .padding(.horizontal, 9).padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture { bandPeek = WayOutPeek(id: memo.id.uuidString) }
        // The quiet row's fast verbs (m6/m3, 2026-07-22) — pipeline rows have
        // had a menu forever; these close the "can't right-click them" gap.
        // NO "Flag" verb (Tuur 2026-07-23, the iPad-wave correction): rating
        // IS the flag — the peek's SignificanceCircles are the one surface,
        // same reason the m6 peek dropped its silent-0.1 button. Lock = the
        // background keep-don't-polish verb's only Mac surface; Delete = the
        // Mac's first way to delete a synced note.
        .contextMenu {
            Button(memo.locked ? "Unlock" : "Lock") { toggleLock(memo) }
            Button("Open") { bandPeek = WayOutPeek(id: memo.id.uuidString) }
            Divider()
            Button("Delete", role: .destructive) { deleteQuiet(memo) }
        }
        .accessibilityIdentifier("quiet-memo-row")
    }

    private func toggleLock(_ memo: Memo) {
        memo.locked.toggle()
        try? MemoCloudStore.container?.mainContext.save()
        refreshCloudMemos()
    }

    /// Soft delete into the shared Recently Deleted (14 days, both devices).
    private func deleteQuiet(_ memo: Memo) {
        memo.deletedAt = Date()
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
        guard let cloudCtx = MemoCloudStore.container?.mainContext else { cloudMemos = []; return }
        cloudMemos = (try? cloudCtx.fetch(FetchDescriptor<Memo>())) ?? []
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

    private func processAll(_ memos: [Memo]) {
        guard !memos.isEmpty else { return }
        for memo in memos { memo.significance = 0.1 }
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
                    Text("Processing \(min(rs.done + 1, rs.total)) of \(rs.total)")
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

    var body: some View {
        let st = file.queueStatus
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 7) {
                Image(systemName: file.sourceSymbol)
                    .font(.system(size: 12))
                    .foregroundStyle(selected ? Theme.accent : Theme.textMuted)
                    .frame(width: 14)
                Text(file.queueTitle)
                    .font(.system(size: 13, weight: st == .exported ? .medium : .semibold))
                    .foregroundStyle(st == .exported ? Theme.textSecondary : Theme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                StatusPill(status: st)
            }
            Text(file.queueMeta)
                .font(.system(size: 11))
                .foregroundStyle(Theme.textMuted)
                .padding(.leading, 21)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(rowBackground, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8)
            .stroke(selected ? Theme.accent.opacity(0.2) : .clear, lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .onHover { hovering = $0 }
        .animation(.easeInOut(duration: 0.12), value: hovering)
        .animation(.easeOut(duration: 0.12), value: selected)
    }

    private var rowBackground: Color {
        if selected { return Theme.accent.opacity(0.13) }
        if hovering { return Theme.hairline.opacity(0.04) }
        return .clear
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
