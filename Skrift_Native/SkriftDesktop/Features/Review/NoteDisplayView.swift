import SwiftUI

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
    @Environment(\.modelContext) private var ctx
    @State private var audio = AudioController()
    @State private var author = SettingsStore.shared.load().authorName
    /// Pre-unlink snapshot backing the inline undo toast (mocks/name-unlink.html).
    /// Stays until dismissed/undone; cleared on note switch.
    @State private var unlinkUndo: UnlinkUndo?
    /// Drives the shared person editor sheet (mocks/opt-in-naming.html) — opened by the
    /// body's right-click "A new person…" (pre-filled) or the chip bar's "Someone else…".
    @State private var editorRequest: PersonEditorRequest?

    /// What "Undo" restores after an unlink: the exact pre-unlink body + the note's
    /// persisted no-relink list as it was.
    struct UnlinkUndo {
        var message: String
        var body: String
        var unlinkedNames: [String]
    }

    var body: some View {
        Group {
            if let file {
                content(file)
                    .task(id: file.id) { audio.load(path: file.path) }
                    .onChange(of: file.id, initial: true) { _, _ in unlinkUndo = nil }
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
    }

    /// The centered reading column: properties → capture banner (if any) → summary →
    /// body. (OPT-OUT naming lives in the prose — names auto-link and you prune by
    /// clicking; the in-prose three-tier rendering + which-person popover land in chunk 4.)
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
            if let undo = unlinkUndo, scrollable {
                unlinkUndoToast(undo, file)
            }
            NoteBody(file: file, audio: audio, interactive: scrollable, onAddName: addName, onAddAlias: addAlias,
                     onUnlink: scrollable ? unlinkHandler(file) : nil)
        }
    }

    // ── Unlink a [[Name]] (mocks/name-unlink.html) ──────────────────────────────

    /// The body's unlink callback, bound to the active note.
    private func unlinkHandler(_ file: PipelineFile) -> (String, String, BodyTextView.UnlinkScope) -> Void {
        { canonical, alias, scope in
            applyUnlink(file, canonical: canonical, alias: alias, scope: scope)
        }
    }

    /// Apply a scope picked in the body's unlink popover. ONE mention → the i-th
    /// `[[link]]` of that person becomes the plain alias as spoken (a body edit,
    /// like any hand edit). ALL mentions → every link of theirs goes plain AND the
    /// canonical is persisted on the file so re-processing won't re-link it here.
    /// Either way the pre-unlink state is kept for the undo toast.
    private func applyUnlink(_ file: PipelineFile, canonical: String, alias: String,
                             scope: BodyTextView.UnlinkScope) {
        let before = file.bestBodyText
        let beforeUnlinked = file.unlinkedNames
        let text: String
        let message: String
        switch scope {
        case let .mention(index):
            text = Sanitiser.unlinkOccurrence(text: before, canonical: canonical, index: index, alias: alias)
            message = "Unlinked — “\(alias)” is plain text in this note"
        case let .change(index, newPerson):
            text = Sanitiser.relinkOccurrence(text: before, canonical: canonical, index: index, newCanonical: newPerson)
            message = "Changed — this mention now links to \(newPerson)"
        case .all:
            text = Sanitiser.unlinkAll(text: before, canonical: canonical, alias: alias)
            if !file.unlinkedNames.contains(where: { $0.caseInsensitiveCompare(canonical) == .orderedSame }) {
                file.unlinkedNames.append(canonical)
            }
            message = "Unlinked \(canonical) everywhere in this note — won’t re-link on reprocess"
        }
        guard text != before || file.unlinkedNames != beforeUnlinked else { return }
        setBody(text, on: file)
        file.compiledText = Compiler.compile(file: file, author: author, knownPeople: NamesStore.shared.livePeople())
        file.lastActivityAt = Date()
        try? ctx.save()
        unlinkUndo = UnlinkUndo(message: message, body: before, unlinkedNames: beforeUnlinked)
    }

    /// Undo the last unlink: restore the exact pre-unlink body + no-relink list.
    private func undoUnlink(_ file: PipelineFile) {
        guard let undo = unlinkUndo else { return }
        setBody(undo.body, on: file)
        file.unlinkedNames = undo.unlinkedNames
        file.compiledText = Compiler.compile(file: file, author: author, knownPeople: NamesStore.shared.livePeople())
        file.lastActivityAt = Date()
        try? ctx.save()
        unlinkUndo = nil
    }

    /// Write the body back through the SAME precedence the editor binding uses
    /// (sanitised → copy-edit → transcript), so unlink/undo edit what's shown.
    private func setBody(_ text: String, on file: PipelineFile) {
        if file.sanitised != nil { file.sanitised = text }
        else if file.enhancedCopyedit != nil { file.enhancedCopyedit = text }
        else { file.transcript = text }
    }

    /// The inline undo toast — sits above the body (per the mock) and STAYS until
    /// undone or dismissed (an unlink shouldn't quietly become permanent).
    private func unlinkUndoToast(_ undo: UnlinkUndo, _ file: PipelineFile) -> some View {
        HStack(spacing: 10) {
            Text(undo.message)
                .font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button { undoUnlink(file) } label: {
                Text("Undo").font(.system(size: 11.5)).foregroundStyle(Theme.accent)
                    .padding(.horizontal, 10).padding(.vertical, 3)
                    .overlay(Capsule().stroke(Theme.accent.opacity(0.35), lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            Button { unlinkUndo = nil } label: {
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

    /// Persist a person from the editor and RE-SCAN the open note (no global re-scan) so a
    /// newly-added person appears as a chip in the People bar (mocks/opt-in-naming.html).
    private func savePerson(_ original: String?, _ person: Person, for file: PipelineFile) {
        NamesStore.shared.upsert(person, replacing: original)
        coordinator.resanitiseForNames(file, context: ctx)
        coordinator.flash("Saved “\(NamesMerge.keyName(person.canonical))” — it’ll show as a chip if mentioned")
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
