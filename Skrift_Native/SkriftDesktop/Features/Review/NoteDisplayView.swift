import SwiftUI
import AppKit
import SwiftData

/// The review surface (right pane): breadcrumb → pinned toolbar bar (transport +
/// actions) → scrollable note content. The properties block, resolver, and the
/// rich body/karaoke land in chunks 3–4; for now the scroll area shows the summary
/// and body text so the toolbar reads in context.
struct NoteDisplayView: View {
    let file: PipelineFile?
    var coordinator: ProcessingCoordinator
    /// Snapshot mode renders the body without a ScrollView (ImageRenderer can't lay
    /// out scroll contents). The live app keeps `true` for real scrolling.
    var scrollable = true
    /// Navigate to another memo's row (memo-link chip / LINKED FROM) — wired by
    /// RootView to the AppModel selection; nil on snapshot hosts → inert.
    var onOpenMemo: ((String) -> Void)? = nil
    @Environment(\.modelContext) private var ctx
    @State private var audio = AudioController()
    @State private var author = SettingsStore.shared.load().authorName
    /// Pre-action snapshot backing the inline undo toast. The OPT-OUT body is a pure function
    /// of the note's override sets, so undo just restores them + re-derives. Stays until
    /// dismissed/undone; cleared on note switch.
    @State private var namingUndo: NamingUndo?
    /// Drives the shared person editor sheet (mocks/opt-in-naming.html) — opened by the
    /// body's right-click "A new person…" / the suggestion popover's "New person…".
    @State private var editorRequest: PersonEditorRequest?
    /// Locked-note session gate (synced `locked` flag; Touch ID/password unlocks per session).
    @ObservedObject private var lockGate = LockGate.shared
    /// The Connections panel's per-note data (rows + backlinks + gate state). Lives
    /// here — not in the panel — so the toolbar badge has the count while collapsed.
    @State private var connections = ConnectionsModel()
    /// Panel visibility — app-wide + persisted (mock #m5 decision), ⌥⌘C toggles.
    @AppStorage("connectionsPanelVisible") private var connectionsVisible = true

    /// What "Undo" restores after a naming action: the note's override sets as they were.
    struct NamingUndo {
        var message: String
        var unlinkedNames: [String]
        var namePicks: [String: String]
    }

    var body: some View {
        Group {
            if let file {
                content(file)
                    .task(id: file.id) { audio.load(path: file.path) }
                    .onChange(of: file.id, initial: true) { _, _ in namingUndo = nil }
                    .sheet(item: $editorRequest) { req in
                        PersonEditor(request: req,
                                     onSave: { original, person in savePerson(original, person, for: file) },
                                     onClose: { editorRequest = nil })
                    }
            } else {
                emptyState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg)
    }

    @ViewBuilder private func content(_ file: PipelineFile) -> some View {
        if lockGate.isLocked(file) {
            // Locked note (synced flag): everything below the breadcrumb — toolbar
            // actions included (copy/export leak content) — waits for device-owner auth.
            VStack(spacing: 0) {
                breadcrumb(file)
                lockedPanel(file)
            }
        } else {
            unlockedContent(file)
        }
    }

    private func lockedPanel(_ file: PipelineFile) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "lock.fill")
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(Theme.textMuted)
            Text("This note is locked")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("Locked notes stay inside Skrift and are excluded from vault export.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
            Button("Unlock…") {
                Task { _ = await lockGate.unlock(file.id) }
            }
            .buttonStyle(.borderedProminent).tint(Theme.accent).controlSize(.regular)
            .accessibilityLabel("Unlock this note")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder private func unlockedContent(_ file: PipelineFile) -> some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                breadcrumb(file)
                toolbarBar(file)
                GeometryReader { geo in
                    let colW = min(820, max(320, geo.size.width - 72))
                    let body = column(file)
                        .frame(width: colW, alignment: .leading)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 30)
                    if scrollable {
                        ScrollView { body }
                    } else {
                        body
                    }
                }
            }
            // The Connections panel (mocks/related-panel.html) — live app only
            // (snapshot hosts render the body via their own fixture mode).
            if scrollable, connectionsVisible {
                ConnectionsPanel(file: file, model: connections,
                                 onOpenMemo: { onOpenMemo?($0) },
                                 onCollapse: { connectionsVisible = false })
            }
        }
        .task(id: file.id) { await connections.refresh(for: file, context: ctx) }
        // A sweep just finished → fresh rows may exist for this note; re-query.
        .onChange(of: ConnectionsIndexService.shared.sweeping) { _, sweeping in
            if !sweeping { Task { await connections.refresh(for: file, context: ctx) } }
        }
    }

    /// The centered reading column: properties → capture banner (if any) → summary →
    /// body. OPT-OUT naming lives in the prose (mocks/naming-review.html) — names auto-link,
    /// dotted suggestions + linked names are clicked to decide; every decision mutates the
    /// note's override sets and re-derives the body deterministically (no LLM).
    private func column(_ file: PipelineFile) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            NoteProperties(file: file, author: author, interactive: scrollable)
            if file.sourceType == .capture {
                CaptureBanner(file: file)
                // The shared thing itself, pinned above the annotation body —
                // mirrors what the export pins above the body in markdown.
                CaptureSharedContentBlock(file: file)
            }
            if scrollable, file.enhancedSummary != nil {
                summaryEditor(file)
            } else if let summary = file.enhancedSummary, !summary.isEmpty {
                summaryAside(summary)
            }
            if let undo = namingUndo, scrollable {
                namingUndoToast(undo, file)
            }
            NoteBody(file: file, audio: audio, interactive: scrollable, onAddName: addName, onAddAlias: addAlias,
                     onSuggestionPick: scrollable ? { a, c in pickName(file, alias: a, canonical: c) } : nil,
                     onSuggestionPlain: scrollable ? { a in plainName(file, alias: a) } : nil,
                     onLinkedUnlink: scrollable ? { c in unlinkName(file, canonical: c) } : nil,
                     onLinkedChange: scrollable ? { a, c in changeName(file, alias: a, newCanonical: c) } : nil,
                     onOpenNote: scrollable ? { c in openNote(c) } : nil,
                     onOpenMemoLink: onOpenMemo.map { open in { id in open(id.uuidString) } },
                     linkCandidates: scrollable ? { linkCandidates(excluding: file) } : { [] },
                     linkTitle: { id in liveTitle(of: id) })
            // The bottom LINKED FROM strip is GONE — backlinks live in the
            // Connections panel now (mock decision, 2026-07-16).
        }
    }

    // ── In-prose naming decisions (mocks/naming-review.html) ─────────────────────
    // Every action mutates the note's override sets (`unlinkedNames` prune + `namePicks`
    // which-person/silence), then re-derives the body via the deterministic Sanitiser.

    /// Snapshot the override sets, run `mutate`, re-derive + save, and arm the undo toast.
    /// The `[[` picker's link targets: every other live memo (id must be a memo UUID; trashed
    /// excluded), most-recent first, with a date subtitle. Built lazily when the picker opens.
    private func linkCandidates(excluding file: PipelineFile) -> [MemoLinkCandidate] {
        let all: [PipelineFile] = (try? ctx.fetch(FetchDescriptor<PipelineFile>())) ?? []
        let df = DateFormatter(); df.dateStyle = .medium; df.timeStyle = .none
        return all
            .filter { $0.id != file.id && $0.deletedAt == nil }
            .sorted { $0.uploadedAt > $1.uploadedAt }
            .compactMap { f in
                guard let id = UUID(uuidString: f.id) else { return nil }   // memo-links key on the memo UUID
                return MemoLinkCandidate(id: id, title: f.queueTitle, subtitle: df.string(from: f.uploadedAt))
            }
    }

    /// A memo-link target's CURRENT title (so chips show the live title, not the frozen
    /// snapshot). nil when the target isn't in this library → the chip keeps its snapshot.
    private func liveTitle(of id: UUID) -> String? {
        let key = id.uuidString
        var d = FetchDescriptor<PipelineFile>(predicate: #Predicate { $0.id == key })
        d.fetchLimit = 1
        // `queueTitle` = displayTitle (enhanced title → first body line → filename), so the chip
        // reads as the target's opening words for a title-less note — matching the phone.
        return (try? ctx.fetch(d))?.first?.queueTitle
    }

    private func applyNaming(_ file: PipelineFile, _ message: String, _ mutate: () -> Void) {
        let undo = NamingUndo(message: message, unlinkedNames: file.unlinkedNames, namePicks: file.namePicks)
        mutate()
        coordinator.resanitiseForNames(file, context: ctx)
        namingUndo = undo
    }

    /// Suggestion popover → "which person?" / common-word confirm: FORCE-LINK the alias.
    private func pickName(_ file: PipelineFile, alias: String, canonical: String) {
        let key = alias.lowercased()
        let canon = NamesMerge.normaliseCanonical(canonical)
        applyNaming(file, "Linked “\(alias)” → \(NamesMerge.keyName(canon))") {
            var picks = file.namePicks; picks[key] = canon; file.namePicks = picks
            // Re-promote: clear any prune of the chosen person so it links.
            file.unlinkedNames.removeAll { $0.caseInsensitiveCompare(canon) == .orderedSame
                || NamesMerge.keyName($0).caseInsensitiveCompare(NamesMerge.keyName(canon)) == .orderedSame }
        }
    }

    /// Suggestion popover → "Leave as plain text": SILENCE the alias (renders plain).
    private func plainName(_ file: PipelineFile, alias: String) {
        let key = alias.lowercased()
        applyNaming(file, "“\(alias)” left as plain text") {
            var picks = file.namePicks; picks[key] = ""; file.namePicks = picks
        }
    }

    /// Linked popover → "Unlink — side-mention": PRUNE the person (→ dotted suggestion).
    private func unlinkName(_ file: PipelineFile, canonical: String) {
        let canon = NamesMerge.normaliseCanonical(canonical)
        let key = NamesMerge.keyName(canon).lowercased()
        applyNaming(file, "Unlinked \(NamesMerge.keyName(canon)) — now a side-mention") {
            if !file.unlinkedNames.contains(where: { NamesMerge.keyName($0).lowercased() == key }) {
                file.unlinkedNames.append(canon)
            }
            // Drop any pick that re-promoted them (so the prune takes effect).
            file.namePicks = file.namePicks.filter { NamesMerge.keyName($0.value).lowercased() != key }
        }
    }

    /// Linked popover → "Change person…": FORCE-LINK the alias to a different person.
    private func changeName(_ file: PipelineFile, alias: String, newCanonical: String) {
        let key = alias.lowercased()
        let canon = NamesMerge.normaliseCanonical(newCanonical)
        applyNaming(file, "Changed “\(alias)” → \(NamesMerge.keyName(canon))") {
            var picks = file.namePicks; picks[key] = canon; file.namePicks = picks
        }
    }

    /// Linked popover → "Open their note": open the `People/<name>.md` file in the user's
    /// default Markdown handler (Obsidian, for most). Flashes when there's no vault or no
    /// such note yet (e.g. a freshly-invented person hasn't got a People/ note).
    private func openNote(_ canonical: String) {
        let name = NamesMerge.keyName(canonical)
        let vault = SettingsStore.shared.load().noteFolder
        guard !vault.isEmpty else { coordinator.flash("Set a vault in Settings to open notes"); return }
        let url = URL(fileURLWithPath: vault).appendingPathComponent("People").appendingPathComponent("\(name).md")
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.open(url)
        } else {
            coordinator.flash("No People/\(name).md note in your vault yet")
        }
    }

    /// Undo the last naming action: restore the override sets + re-derive.
    private func undoNaming(_ file: PipelineFile) {
        guard let undo = namingUndo else { return }
        file.unlinkedNames = undo.unlinkedNames
        file.namePicks = undo.namePicks
        coordinator.resanitiseForNames(file, context: ctx)
        namingUndo = nil
    }

    /// The inline undo toast — sits above the body and STAYS until undone or dismissed.
    private func namingUndoToast(_ undo: NamingUndo, _ file: PipelineFile) -> some View {
        HStack(spacing: 10) {
            Text(undo.message)
                .font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button { undoNaming(file) } label: {
                Text("Undo").font(.system(size: 11.5)).foregroundStyle(Theme.accent)
                    .padding(.horizontal, 10).padding(.vertical, 3)
                    .overlay(Capsule().stroke(Theme.accent.opacity(0.35), lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            Button { namingUndo = nil } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.textMuted)
            }
            .buttonStyle(.plain)
            .help("Dismiss")
        }
        .padding(.horizontal, 13).padding(.vertical, 8)
        .background(Theme.hairline.opacity(0.04), in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.hairline.opacity(0.10), lineWidth: 0.5))
    }

    /// Right-click "A new person…" → open the shared editor (mocks/opt-in-naming.html panel 3)
    /// pre-filled with the selected words as both the full name and the first alias, so you
    /// can fill in the rest before saving — instead of silently creating a bare name.
    private func addName(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // Already a known person? Just confirm it; no need to re-add.
        if NamesStore.shared.livePeople().contains(where: {
            NamesMerge.keyName($0.canonical).localizedCaseInsensitiveCompare(trimmed) == .orderedSame
                || $0.aliases.contains { $0.localizedCaseInsensitiveCompare(trimmed) == .orderedSame }
        }) {
            coordinator.flash("“\(trimmed)” is already in your names")
            return
        }
        editorRequest = PersonEditorRequest(prefillName: trimmed, prefillAlias: trimmed)
    }

    /// Persist a person from the editor, re-derive the OPEN note (so a newly-added person
    /// auto-links / surfaces), and re-scan EVERY processed memo for a fresh same-name
    /// collision the add may have introduced (NAMING_MODEL.md build-guard).
    private func savePerson(_ original: String?, _ person: Person, for file: PipelineFile) {
        let before = NamesStore.shared.livePeople()
        NamesStore.shared.upsert(person, replacing: original)
        coordinator.resanitiseForNames(file, context: ctx)
        coordinator.rescanRoster(previousPeople: before, context: ctx)
        coordinator.flash("Saved “\(NamesMerge.keyName(person.canonical))”")
    }

    /// Add a body selection as an ALIAS of an existing person (right-click → "Add … as
    /// → alias of <person>"). Lets the names graph grow without inventing duplicates —
    /// e.g. mark "Tuur" as another alias of [[Tiuri Hartog]]. (Cross-person duplicate
    /// aliases are allowed on purpose — that's exactly the two-Jacks ambiguity.)
    private func addAlias(_ word: String, to canonical: String) {
        let alias = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !alias.isEmpty else { return }
        var people = NamesStore.shared.livePeople()
        guard let i = people.firstIndex(where: { $0.canonical == canonical }) else {
            coordinator.flash("That name isn’t in your list anymore"); return
        }
        let name = NamesMerge.keyName(canonical)
        if people[i].aliases.contains(where: { $0.localizedCaseInsensitiveCompare(alias) == .orderedSame }) {
            coordinator.flash("“\(alias)” is already an alias of \(name)"); return
        }
        people[i].aliases.append(alias)
        people[i].lastModifiedAt = ISO8601.now()
        _ = NamesStore.shared.writeWithSmartBumps(people)
        coordinator.flash("Added “\(alias)” as an alias of \(name)")
    }

    /// The LLM summary, editable in place like the title/body (it was the one
    /// read-only field on the review screen). Edits write straight to
    /// `enhancedSummary` (SwiftData autosaves), and export picks them up because
    /// `VaultExporter` recompiles from the file at export time. Gated on `!= nil`
    /// (not non-empty) so clearing the text mid-edit doesn't dismiss the field.
    private func summaryEditor(_ file: PipelineFile) -> some View {
        TextField("", text: Binding(
            get: { file.enhancedSummary ?? "" },
            set: { file.enhancedSummary = $0 }
        ), prompt: Text("Summary").foregroundStyle(Theme.textMuted), axis: .vertical)
            .textFieldStyle(.plain)
            .font(.system(size: 13.5))
            .italic()
            .lineSpacing(3)
            .foregroundStyle(Theme.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 14)
            .overlay(alignment: .leading) {
                Rectangle().fill(Theme.accent.opacity(0.4)).frame(width: 2)
            }
    }

    /// Read-only summary for the snapshot path (ImageRenderer can't draw
    /// AppKit-backed TextFields — same split as NoteProperties).
    private func summaryAside(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13.5))
            .italic()
            .lineSpacing(3)
            .foregroundStyle(Theme.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 14)
            .overlay(alignment: .leading) {
                Rectangle().fill(Theme.accent.opacity(0.4)).frame(width: 2)
            }
    }

    /// Context line — what you're looking at + when. (Was a "Queue ›" breadcrumb, but
    /// that implied navigation that doesn't exist; the note list is always in the
    /// sidebar, so this just names the source + date.)
    private func breadcrumb(_ file: PipelineFile) -> some View {
        HStack(spacing: 7) {
            Text(sourceLabel(file)).foregroundStyle(Theme.textSecondary)
            Text("·").foregroundStyle(Theme.textMuted)
            Text(SkriftFormat.breadcrumbDate(file.uploadedAt)).foregroundStyle(Theme.textMuted)
            Spacer()
        }
        .font(.system(size: 12))
        .padding(.leading, 28)
        .frame(height: 48)
    }

    private func sourceLabel(_ file: PipelineFile) -> String {
        // Unified source taxonomy (mic / video / book / link / image / text / file /
        // Apple Note) — shares `sourceTypeLabel` with the sidebar glyph so they match.
        file.sourceTypeLabel
    }

    /// The pinned transport + actions bar, given a Liquid Glass treatment so it reads
    /// as a floating surface over the scrolling note (visual parity with the mobile
    /// playback bar's `glassEffect`). On macOS < 26 it falls back to `.ultraThinMaterial`
    /// with a hairline + shadow. Inset horizontally so the glass capsule floats rather
    /// than spanning edge-to-edge.
    private func toolbarBar(_ file: PipelineFile) -> some View {
        let inner = HStack(spacing: 16) {
            if file.sourceType == .capture {
                // Captures have no audio to play — show the source strip instead
                // (glyph + "Shared link · domain" + Open ↗ button).
                CaptureSourceStrip(file: file)
                Spacer()
            } else if showsTransport(file) {
                NoteToolbar(audio: audio, durationSeconds: file.durationSeconds)
            } else {
                Spacer()
            }
            NoteActions(file: file, coordinator: coordinator)
            connectionsToggle
        }
        .padding(.horizontal, 18)
        .frame(height: 44)

        return Group {
            if #available(macOS 26.0, *) {
                // Real Liquid Glass: the note text/properties refract through the bar
                // as they scroll under it. The specular-highlight stroke keeps it
                // reading as an EDGE over the near-flat dark surface (Liquid Glass is
                // subtle over flat backgrounds by design).
                inner
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(
                                LinearGradient(colors: [Theme.hairline.opacity(0.22), Theme.hairline.opacity(0.03)],
                                               startPoint: .top, endPoint: .bottom),
                                lineWidth: 0.8)
                    )
            } else {
                inner
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Theme.hairline.opacity(0.10), lineWidth: 0.5)
                    )
                    .shadow(color: .black.opacity(0.22), radius: 14, y: 5)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }

    /// Panel toggle (⌥⌘C) — collapsed keeps a count badge so a folded panel still
    /// whispers that this note connects somewhere (mock #m5).
    private var connectionsToggle: some View {
        Button { connectionsVisible.toggle() } label: {
            Image(systemName: "sidebar.right")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(connectionsVisible ? Theme.accent : Theme.textSecondary)
                .overlay(alignment: .topTrailing) {
                    if !connectionsVisible, connections.count > 0 {
                        Text("\(connections.count)")
                            .font(.system(size: 8, weight: .heavy).monospacedDigit())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 3.5).padding(.vertical, 1)
                            .background(Theme.accent, in: Capsule())
                            .offset(x: 8, y: -7)
                    }
                }
        }
        .buttonStyle(.plain)
        .keyboardShortcut("c", modifiers: [.command, .option])
        .help(connectionsVisible ? "Hide Connections (⌥⌘C)" : "Show Connections (⌥⌘C)")
        .accessibilityIdentifier("connections-toggle")
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(.system(size: 30))
                .foregroundStyle(Theme.textMuted.opacity(0.4))
            Text("Select a note to get started")
                .font(.system(size: 14))
                .foregroundStyle(Theme.textMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Audio transport for any non-note source with playable audio — a real file on
    /// disk (locally-ingested memos have no phone-metadata duration; the player reads
    /// the real one) OR a metadata duration (demo notes without a backing file).
    private func showsTransport(_ file: PipelineFile) -> Bool {
        guard file.sourceType != .note else { return false }
        if file.durationSeconds > 0 { return true }
        return !file.path.isEmpty && FileManager.default.fileExists(atPath: file.path)
    }
}
