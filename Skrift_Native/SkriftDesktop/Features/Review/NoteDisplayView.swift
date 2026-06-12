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
    /// Inline name-disambiguation state (R3). Created when the active note has
    /// ambiguous names; preserved across re-renders (holds in-progress choices);
    /// cleared on note switch or once resolution is applied.
    @State private var resolver: InlineResolverModel?
    /// Pre-unlink snapshot backing the inline undo toast (mocks/name-unlink.html).
    /// Stays until dismissed/undone; cleared on note switch.
    @State private var unlinkUndo: UnlinkUndo?

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
                    .onChange(of: file.id, initial: true) { _, _ in syncResolver(file); unlinkUndo = nil }
                    .onChange(of: file.ambiguousNames?.count ?? 0, initial: true) { _, _ in syncResolver(file) }
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

    /// The centered reading column: resolver banner → properties → capture banner (if any)
    /// → summary → body. The resolver banner asks "Who is X?" per alias (auto-applies);
    /// the capture banner explains what was skipped and what still ran.
    private func column(_ file: PipelineFile) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            if let resolver, scrollable, !resolver.isEmpty {
                InlineResolverBanner(model: resolver)
            }
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
                     resolver: scrollable ? resolver : nil,
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
        case .all:
            text = Sanitiser.unlinkAll(text: before, canonical: canonical, alias: alias)
            if !file.unlinkedNames.contains(where: { $0.caseInsensitiveCompare(canonical) == .orderedSame }) {
                file.unlinkedNames.append(canonical)
            }
            message = "Unlinked \(canonical) everywhere in this note — won’t re-link on reprocess"
        }
        guard text != before || file.unlinkedNames != beforeUnlinked else { return }
        setBody(text, on: file)
        file.compiledText = Compiler.compile(file: file, author: author)
        file.lastActivityAt = Date()
        try? ctx.save()
        unlinkUndo = UnlinkUndo(message: message, body: before, unlinkedNames: beforeUnlinked)
    }

    /// Undo the last unlink: restore the exact pre-unlink body + no-relink list.
    private func undoUnlink(_ file: PipelineFile) {
        guard let undo = unlinkUndo else { return }
        setBody(undo.body, on: file)
        file.unlinkedNames = undo.unlinkedNames
        file.compiledText = Compiler.compile(file: file, author: author)
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

    /// (Re)create the inline resolver model for the active note + wire its actions.
    /// Kept while the same note still has ambiguous names (in-progress choices survive
    /// re-renders); recreated on note switch; cleared once all names are resolved.
    /// Leaving a note mid per-occurrence resolution ABANDONS the in-flight picks:
    /// the pristine snapshot is restored (guarded — only while the body is still the
    /// resolver's own render), so `ambiguousNames` and the body stay consistent.
    private func syncResolver(_ file: PipelineFile) {
        let amb = file.ambiguousNames ?? []
        if amb.isEmpty {
            if let old = resolver {
                old.onAbandonPartial?()   // switched away, or ambiguity cleared externally
                resolver = nil
            }
        } else if resolver?.fileID != file.id {
            resolver?.onAbandonPartial?()  // leaving a partially-resolved note
            let m = InlineResolverModel(fileID: file.id, ambiguous: amb)
            wireResolver(m, file)
            resolver = m
        }
    }

    private func wireResolver(_ m: InlineResolverModel, _ file: PipelineFile) {
        m.onResolveAlias = { [weak m] alias, choice in
            guard let m else { return }
            resolveAlias(file, m, alias: alias, choice: choice)
        }
        m.onEscalate = { [weak m] alias in
            guard let m else { return }
            let k = alias.lowercased()
            m.escalated.insert(k)
            // Count against the baseline the choices will key on (the pristine
            // snapshot while another alias is mid-flight, else the body as shown).
            let base = (m.lastRendered == file.bestBodyText ? m.snapshot : nil) ?? file.bestBodyText
            m.setOccurrenceTotal(Sanitiser.plainOccurrences(of: m.display(k), in: base).count, for: k)
            m.styleVersion += 1
        }
        m.onDeescalate = { [weak m] alias in
            guard let m else { return }
            let k = alias.lowercased()
            m.escalated.remove(k)
            m.clearDecisions(for: k)
            if m.snapshot != nil {
                if m.lastRendered != file.bestBodyText {
                    m.clearPartial()   // stale (hand edit) — leave the body as the user left it
                } else if m.hasPartialDecisions {
                    rerenderPartial(file, m)   // other aliases keep their in-flight render
                } else if let snap = m.snapshot {
                    setBody(snap, on: file)    // nothing left in flight → pristine body back
                    m.clearPartial()
                }
            }
            m.styleVersion += 1
        }
        m.onDecideOccurrence = { [weak m] alias, plainIndex, choice in
            guard let m else { return }
            decideOccurrence(file, m, alias: alias, plainIndex: plainIndex, choice: choice)
        }
        // Restore the pristine body when an in-flight partial render is abandoned
        // (note switch / external clear) — only while the body is still OUR render,
        // so a reprocess/hand-edit is never clobbered.
        m.onAbandonPartial = { [weak m] in
            guard let m, let snap = m.snapshot, let rendered = m.lastRendered,
                  snap != rendered, file.bestBodyText == rendered else { return }
            setBody(snap, on: file)
            try? ctx.save()
        }
    }

    /// "Who is X?" answered with one person (or plain) → apply to EVERY mention at
    /// once (first → `[[Canonical]]`, rest → the alias) and clear the alias. Applies
    /// against the pristine snapshot while another alias is mid per-occurrence
    /// resolution (the displayed body carries that alias's uncommitted render).
    private func resolveAlias(_ file: PipelineFile, _ m: InlineResolverModel, alias: String, choice: ResolverChoice) {
        let body = (m.lastRendered == file.bestBodyText ? m.snapshot : nil) ?? file.bestBodyText
        let text: String
        switch choice {
        case let .person(c):
            text = Sanitiser.applyResolvedNames(text: body, decisions: [(alias: m.display(alias), canonical: c.canonical, short: c.short)])
        case .plain:
            text = body   // leave every mention plain
        }
        commitResolution(file, m, alias: alias, text: text)
    }

    /// Escalated ("different people"): ONE per-occurrence pick. Applies instantly —
    /// the body re-renders from the pristine snapshot + every choice so far (the
    /// chosen mention links/shortens on the spot, undecided ones stay highlighted,
    /// document-order first-mention wins even when assigned out of order) — and the
    /// alias commits once all its mentions are decided.
    private func decideOccurrence(_ file: PipelineFile, _ m: InlineResolverModel,
                                  alias: String, plainIndex: Int, choice: ResolverChoice) {
        let body = file.bestBodyText
        if m.lastRendered != body {
            // First pick — or a hand edit invalidated the in-flight render: re-base
            // on the body as it stands (previous picks are already part of it).
            m.beginPartial(body: body)
        }
        guard let snapIdx = m.snapshotIndex(alias: alias, plainIndex: plainIndex) else { return }
        m.setChoice(alias: alias, snapshotIndex: snapIdx, choice: choice)
        rerenderPartial(file, m)
        maybeCompleteAlias(file, m, alias: alias)
    }

    /// Recompute the displayed body from the pristine snapshot + ALL in-flight
    /// choices (every escalated alias composes over the one snapshot). View-owned:
    /// no `ambiguousNames` trim, no recompile, no explicit save — that's the
    /// commit's job once an alias completes.
    private func rerenderPartial(_ file: PipelineFile, _ m: InlineResolverModel) {
        guard let snapshot = m.snapshot else { return }
        var byAlias: [String: [Sanitiser.PartialChoice]] = [:]
        for key in m.aliasOrder where m.isEscalated(key) {
            let total = m.occTotals[key] ?? 0
            guard total > 0 else { continue }
            let d = m.decisions(for: key)
            byAlias[key] = (0..<total).map { i in
                switch d[i] {
                case .none: return .undecided
                case .some(.plain): return .plain
                case let .some(.person(c)): return .person(canonical: c.canonical, short: c.short)
                }
            }
        }
        let render = Sanitiser.applyPartialOccurrences(text: snapshot, byAlias: byAlias)
        if render.text != file.bestBodyText { setBody(render.text, on: file) }
        m.setRender(text: render.text, ranges: render.ranges)
        m.styleVersion += 1
    }

    /// Once every mention of an escalated alias has a choice, commit it: apply the
    /// per-occurrence choices to the SNAPSHOT (distinct people stay distinct) and
    /// clear the alias — exactly the pre-instant-apply completion.
    private func maybeCompleteAlias(_ file: PipelineFile, _ m: InlineResolverModel, alias: String) {
        guard let snapshot = m.snapshot else { return }
        let key = alias.lowercased()
        let total = m.occTotals[key] ?? 0
        let d = m.decisions(for: key)
        guard total > 0, (0..<total).allSatisfy({ d[$0] != nil }) else { return }
        let ordered: [(canonical: String?, short: String?)] = (0..<total).map { i in
            if case let .person(c) = d[i] { return (c.canonical, c.short) }
            return (nil, nil)
        }
        let text = Sanitiser.applyResolvedOccurrences(text: snapshot, byAlias: [m.display(key): ordered])
        commitResolution(file, m, alias: alias, text: text)
    }

    /// Persist a resolved alias: update the body, trim it from `ambiguousNames`, drop
    /// it from the live model, recompile. When none remain, dismiss the resolver.
    /// Another alias's in-flight picks are RE-BASED onto the committed text (their
    /// index-keyed choices survive the position shifts) and re-rendered on top.
    private func commitResolution(_ file: PipelineFile, _ m: InlineResolverModel, alias: String, text: String) {
        let inFlightValid = m.lastRendered == nil || m.lastRendered == file.bestBodyText
        file.sanitised = text
        let remaining = (file.ambiguousNames ?? []).filter { $0.alias.lowercased() != alias.lowercased() }
        file.ambiguousNames = remaining.isEmpty ? nil : remaining
        file.sanitiseStatus = .done
        file.compiledText = Compiler.compile(file: file, author: author)
        file.lastActivityAt = Date()
        try? ctx.save()
        m.removeAlias(alias)
        if m.isEmpty {
            resolver = nil
        } else if inFlightValid && m.hasPartialDecisions {
            m.rebase(snapshot: text)
            rerenderPartial(file, m)   // remaining in-flight picks ride on the committed text
        } else {
            m.clearPartial()
            m.styleVersion += 1
        }
    }

    /// Add a body text selection to the names DB — the reliable, user-driven way to
    /// grow the names graph (you pick the exact words; no flaky auto-detection).
    private func addName(_ text: String) {
        let canon = NamesMerge.normaliseCanonical(text)
        let key = NamesMerge.keyName(canon)
        guard !key.isEmpty else { return }
        var people = NamesStore.shared.livePeople()
        if people.contains(where: { NamesMerge.keyName($0.canonical).localizedCaseInsensitiveCompare(key) == .orderedSame }) {
            coordinator.flash("“\(key)” is already in your names")
            return
        }
        people.append(Person(canonical: canon, aliases: [text], short: nil, lastModifiedAt: ISO8601.now()))
        _ = NamesStore.shared.writeWithSmartBumps(people)
        coordinator.flash("Added “\(key)” to names")
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
        switch file.sourceType {
        case .audio: return "Voice memo"
        case .note: return "Apple Note"
        case .capture: return "Capture"
        }
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
