import SwiftUI
import AppKit
import SwiftData

/// The review surface (right pane): chrome band (verbs) → scrollable note, with the
/// Connections inspector floating over its trailing edge and the player docked along
/// the bottom. There is no breadcrumb — source and date are chips in the note header
/// (2026-07-25) — EXCEPT on the locked path, where the header never renders and the
/// breadcrumb is the only thing naming the note you're being asked to unlock.
struct NoteDisplayView: View {
    let file: PipelineFile?
    var coordinator: ProcessingCoordinator
    /// What this note can actually DO — DERIVED from the note itself, never chosen by
    /// the caller. It used to be a parameter, and the capability was whatever pane
    /// happened to open the note: `RootView` routes any id that resolves to a FILE
    /// into this view with the old `.full` default, so an unrated Mac take (a real
    /// `PipelineFile`) walked straight past the `.unrated` gate that only the
    /// no-file `UnratedNotePane` path applied — Connections showed for a note
    /// nobody had judged (ROUND 9 item 4, 2026-07-28). Now the note answers:
    /// unrated → `.unrated` (both channels, via `NoteConsent`); a rated PROJECTION
    /// (just rated in the pane, the sweep's real row not swept in yet) stays
    /// `.unrated` because the pipeline verbs still have no row to act on — the pane
    /// swaps to the real row by itself moments later.
    private var capabilities: NoteCapabilities {
        guard let file else { return .full }
        guard NoteConsent.isRated(file) else { return .unrated }
        return file.modelContext == nil ? .unrated : .full
    }
    /// Snapshot mode renders the body without a ScrollView (ImageRenderer can't lay
    /// out scroll contents). The live app keeps `true` for real scrolling.
    var scrollable = true
    /// Navigate to another memo's row (memo-link chip / LINKED FROM) — wired by
    /// RootView to the AppModel selection; nil on snapshot hosts → inert.
    var onOpenMemo: ((String) -> Void)? = nil
    /// The sidebar's live search text — a note opened while it's non-empty scrolls
    /// to the first match and flashes it (phone parity). "" on snapshot hosts.
    var searchQuery: String = ""
    @Environment(\.modelContext) private var ctx
    @State private var audio = AudioController()
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
    /// here — not in the panel — so the query survives collapsing the column. (It
    /// used to feed a count badge on the toggle; the badge is gone — see
    /// `connectionsToggle`.)
    @State private var connections = ConnectionsModel()
    /// Panel visibility — app-wide + persisted (mock #m5 decision), ⌥⌘C toggles.
    @AppStorage("connectionsPanelVisible") private var connectionsVisible = true
    /// Notes-list (sidebar) visibility — the iPad's arrangement brought back here,
    /// same persistence idiom as the panel above. RootView reads it to drop the
    /// column out of the HSplitView.
    @AppStorage("macSidebarVisible") private var sidebarVisible = true

    /// What a note in this pane can DO — the honest difference between a pipelined
    /// note and an unrated one. Everything that makes a note LOOK like a note (header,
    /// chips, importance, body) is unconditional; only the verbs that act on a
    /// pipeline row are switchable, because an unrated memo hasn't got one.
    struct NoteCapabilities: Equatable {
        /// Process / Export / re-transcribe / redo — and the per-note
        /// include-audio-in-export switch, which governs an export that can't happen.
        var pipeline = true
        /// The Connections inspector. Unrated notes are OUT of the idea graph in both
        /// directions — no panel here, and they never appear as candidates in another
        /// note's Related either (Tuur, 2026-07-26: "unrated notes should not join in
        /// other notes' connections"). Being in the graph is Skrift claiming a note
        /// belongs to your thinking; that claim waits for your rating.
        var connections = true

        static let full = NoteCapabilities()
        /// An unrated note — EITHER channel: a memo projected in by
        /// `MemoNoteProjection`, or an unrated Mac take's real pipeline row
        /// (`NoteConsent.isRated` answers for both). The model, in one line: **the rating
        /// is CONSENT — until you've judged a note, Skrift spends nothing on it and
        /// shows it nowhere but back to you.** So what's off here is only what SPENDS
        /// (processing, export) or CLAIMS (the connections graph). Everything that is
        /// just reading your own note back — playing it, karaoke, photos, editing,
        /// copying, search — is unconditional, because consent isn't needed to look at
        /// what you already said (Tuur: "this is not one of those differences").
        static let unrated = NoteCapabilities(pipeline: false, connections: false)
    }

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
                    .onChange(of: file.id, initial: true) { _, _ in
                        namingUndo = nil
                        // C10/D4 + Q40: old body + polish (local and the synced row) → v2 once, at first open
                        file.normaliseBodyOnce(cloud: SettingsStore.shared.load().cloudKitMacSyncEnabled
                                                   ? MemoCloudStore.container?.mainContext : nil)
                    }
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
            // Locked note (synced flag): everything below — toolbar actions included
            // (copy/export leak content) — waits for device-owner auth. This path KEEPS
            // the breadcrumb: the note header (and so the date/source chips) isn't
            // rendered here, so without it nothing would say which note is locked.
            VStack(spacing: 0) {
                breadcrumb(file)
                lockedPanel(file)
            }
        } else {
            unlockedContent(file)
                // C98/D139: two versions → prompt on open (Keep Both = Return), banner
                // after "Later", read-only and held from processing/export until picked.
                .editConflictGate(memoID: UUID(uuidString: file.id),
                                  context: MemoCloudStore.container?.mainContext,
                                  look: .mac, style: .mac,
                                  onResolved: { _, _ in
                                      // The pick released the hold; the next sweep reflects
                                      // the kept words into this row and ingests a Keep-both copy.
                                      EditConflictHold.ids.remove(file.id)
                                      MemoCloudReconciler.reconcileSoon()
                                  })
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
        VStack(spacing: 0) {
            // No breadcrumb: it said "<source> · <date>", and BOTH are chips in the
            // note header now (Tuur 2026-07-25 — the mock flagged the date appearing
            // twice). The iPad has never had one, so dropping it is also parity, and
            // the chrome band becomes the note column's top edge exactly as there.
            toolbarBar(file)
            // A pipeline verb that failed says so HERE, where it was invoked —
            // `lastError` used to be written and read by nothing (SidebarView's own
            // comment), so a 2-second Redo failure looked like "nothing happened"
            // (Tuur, 2026-08-19; the iPad Export lesson, third occurrence).
            if let err = coordinator.lastError {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.destructive)
                    Text(err)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.destructive)
                        .lineLimit(2)
                    Spacer()
                    Button { coordinator.lastError = nil } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 18).padding(.vertical, 6)
                .background(Theme.destructive.opacity(0.10))
            }
            GeometryReader { geo in
                // Panel-aware measure (`NoteMeasure`, unit-tested): the inspector
                // floats, so on a wide window the note genuinely doesn't move, and
                // on a narrow one the column steps aside rather than hiding text
                // behind glass.
                let m = NoteMeasure.column(width: geo.size.width,
                                           panelWidth: inspectorOpen ? ConnectionsPanel.width : 0)
                let body = column(file)
                    .frame(width: m.colW, alignment: .leading)
                    .frame(width: m.region, alignment: .center)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 30)
                if scrollable {
                    ScrollView { body }
                } else {
                    body
                }
            }
            // Connections is an INSPECTOR, not a column (Tuur 2026-07-25, after
            // living with the iPad's version: "it does seem better on the iPad,
            // the way the connections pop up"). It SLIDES IN OVER the note's
            // trailing edge, and unlike the iPad's per-note sheet it STAYS where you
            // left it (`@AppStorage`, Mac inspector idiom), re-querying as you click
            // through notes. It starts BELOW the toolbar so the bar + its hairline
            // stay unbroken and transport is never covered. Whether the note holds
            // its position or steps aside is `NoteMeasure`'s call — floating over
            // the reading column hid a quarter of every line at 1180 (caught by the
            // hosted render, not by reasoning). Live app only (snapshot hosts render
            // the panel body via their own fixture mode).
            .overlay(alignment: .trailing) {
                if scrollable, connectionsVisible, capabilities.connections {
                    ConnectionsPanel(file: file, model: connections,
                                     onOpenMemo: { onOpenMemo?($0) },
                                     onCollapse: { setConnections(false) })
                        .frame(maxHeight: .infinity)
                        // It floats now, so it needs to cast: the leading hairline
                        // alone can't separate two near-identical dark surfaces.
                        .shadow(color: .black.opacity(0.28), radius: 16, x: -6)
                        .transition(.move(edge: .trailing))
                }
            }
            // The player DOCKS at the note's bottom edge — iPad parity (Tuur
            // 2026-07-25: "keep the apps looking the same"). Because the inspector
            // overlays only the scroll area above, the dock is never covered and
            // transport stays reachable with Connections up — the same guarantee
            // the signed iPad spec makes.
            if showsTransport(file) {
                playerDock(file)
            }
        }
        .task(id: file.id) {
            guard capabilities.connections else { return }
            await connections.refresh(for: file, context: ctx)
        }
        // A sweep just finished → fresh rows may exist for this note; re-query.
        .onChange(of: ConnectionsIndexService.shared.sweeping) { _, sweeping in
            guard capabilities.connections, !sweeping else { return }
            Task { await connections.refresh(for: file, context: ctx) }
        }
    }

    /// The centered reading column: properties → capture banner (if any) → summary →
    /// body. OPT-OUT naming lives in the prose (mocks/naming-review.html) — names auto-link,
    /// dotted suggestions + linked names are clicked to decide; every decision mutates the
    /// note's override sets and re-derives the body deterministically (no LLM).
    private func column(_ file: PipelineFile) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            NoteProperties(file: file, interactive: scrollable, canExport: capabilities.pipeline)
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
                     linkTitle: { id in liveTitle(of: id) },
                     searchJumpToken: searchQuery.isEmpty ? nil : "\(file.id)\u{1}\(searchQuery)")
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

    /// The docked player — a full-note-width bar on the panel surface with a
    /// hairline along its TOP (mirror of the toolbar's bottom hairline, so the note
    /// reads as paper between two edges). iPad parity; the phone keeps its floating
    /// glass capsule.
    private func playerDock(_ file: PipelineFile) -> some View {
        NoteToolbar(audio: audio, durationSeconds: file.durationSeconds)
            .padding(.horizontal, 18)
            .frame(height: 52)
            .frame(maxWidth: .infinity)
            .background(Theme.surface)
            .overlay(alignment: .top) {
                Rectangle().fill(Theme.hairline.opacity(0.10)).frame(height: 0.5)
            }
    }

    /// The note column's chrome band: a real BAR with a hairline bottom edge,
    /// spanning the note column — NOT a floating glass capsule (Tuur 2026-07-24:
    /// mirror the iPad's signed "chrome that belongs",
    /// `mocks/ipad-note-chrome-belongs.html`). Every control sits in a glass chip
    /// (`barGlass`) so nothing hangs bare. It holds VERBS ONLY — the transport moved
    /// to `playerDock` at the note's bottom edge for iPad parity (Tuur 2026-07-25),
    /// which is also what makes this band read like the iPad's.
    private func toolbarBar(_ file: PipelineFile) -> some View {
        HStack(spacing: 12) {
            // Queue/sidebar toggle — the iPad's arrangement, brought back to the Mac
            // (Tuur 2026-07-23: "we should have that button the same way you have it
            // on iPad").
            sidebarToggle
            if file.sourceType == .capture {
                // Captures have no audio to play (nothing docks below) — the source
                // strip rides here instead: glyph + "Shared link · domain" + Open ↗.
                CaptureSourceStrip(file: file)
            }
            Spacer()
            // An unrated note keeps its ⋯ — copying text that's on screen needs no
            // rating — but the menu holds only the verbs that can act without a
            // pipeline row, and the primary Process/Export button is absent.
            NoteActions(file: file, coordinator: coordinator, copyOnly: !capabilities.pipeline)
            if capabilities.connections { connectionsToggle }
        }
        .padding(.horizontal, 18)
        .frame(height: 48)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.hairline.opacity(0.10)).frame(height: 0.5)
        }
    }

    /// Is the inspector actually floating right now? (The snapshot fixture hosts
    /// render the panel body themselves, so the measure must not reserve for it.)
    private var inspectorOpen: Bool { scrollable && connectionsVisible && capabilities.connections }

    /// Open/close Connections on the house spring (`SkMotion`, shared with the
    /// phone) — the panel used to SNAP in with no animation at all, which is half
    /// of why the iPad's felt better.
    private func setConnections(_ open: Bool) {
        withAnimation(SkMotion.spring) { connectionsVisible = open }
    }

    /// Sidebar (queue) toggle — the left-hand ◧, in a glass chip: accent-soft while
    /// the notes list is open, quiet while it's hidden (same as the iPad's `PanelToggle`).
    private var sidebarToggle: some View {
        Button { sidebarVisible.toggle() } label: {
            Image(systemName: "sidebar.left")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(sidebarVisible ? Theme.accentText : Theme.textSecondary)
                .frame(width: 30, height: 30)
                .barGlass(on: sidebarVisible)
        }
        .buttonStyle(.plain)
        .help(sidebarVisible ? "Hide the notes list" : "Show the notes list")
        .accessibilityIdentifier("sidebar-toggle")
    }

    /// The Connections summon (⌥⌘C) — a plain WORD in a quiet capsule, quiet →
    /// accent while the column stands open. No ◨ glyph and NO count: capped at 7 the
    /// count reads "7" forever ⇒ zero signal (Tuur 2026-07-24, shipped on iPad first).
    /// On the Mac it still toggles the STANDING column — there's room for it here
    /// (the iPad's 13" hasn't, so there it's a per-note visitor sheet instead).
    private var connectionsToggle: some View {
        Button { setConnections(!connectionsVisible) } label: {
            Text(RetrievalGate.Copy.summonLabel)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(connectionsVisible ? Theme.accentText : Theme.textSecondary)
                .padding(.horizontal, 12)
                .frame(height: 30)
                .barGlass(on: connectionsVisible, in: Capsule())
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
