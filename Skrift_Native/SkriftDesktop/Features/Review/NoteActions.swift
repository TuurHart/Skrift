import SwiftUI
import AppKit
import SwiftData

/// Contextual primary action (Process → Export to Obsidian → Re-export) plus a ⋯
/// overflow (re-transcribe, redo per-step). Ported from `NoteActions.tsx`.
struct NoteActions: View {
    let file: PipelineFile
    var coordinator: ProcessingCoordinator
    /// UNRATED note (`MemoNoteProjection`): drop the primary Process/Export button and
    /// every pipeline verb, keep the ⋯ with the verbs that need no pipeline row.
    /// Copying text that's already on your screen is not something a rating should
    /// gate (Tuur, 2026-07-26: "this is not one of those differences").
    var copyOnly = false
    /// The note was moved to Recently Deleted from its own ⋯ (an unrated note's Delete): the
    /// shell drops the selection so the pane doesn't keep showing a trashed note.
    var onRemoved: (() -> Void)? = nil
    @Environment(\.modelContext) private var ctx

    /// Polished — by ANY device, and exported — to the folder THIS note goes to. Both come
    /// from `NoteWorkState.Inputs`, the one derivation the iPad uses too (Q117): the synced
    /// `MemoEnhancement.isProcessed` (plus this row's own pass, OR-ed in until the write-back
    /// lands) and the export ledger, not the Mac-local `steps.export` flag. Processed is
    /// processed, whoever ran it (Tuur, 2026-08-14), and ALL THREE parts count — never any
    /// one, since `enhancedTitle` is also written from the user's CHOSEN title.
    private var workInputs: NoteWorkState.Inputs {
        // Read for observation: finishing an export flips this row's status, which re-renders
        // the button; the ledger read inside `workInputs` is a disk fact SwiftUI can't see.
        _ = file.exportStatus
        return VaultExporter.workInputs(for: file, cloud: cloudContext, settings: SettingsStore.shared.load())
    }
    private var enhanceDone: Bool { workInputs.hasPolish }
    private var isAppleNote: Bool { file.sourceType == .note }
    private var transcribeDone: Bool { file.steps.transcribe == .done }
    /// A speaker-attributed (conversation) transcript — its `**Name:**` turns are the
    /// ONLY copy of the diarization (the phone never uploads segments/word-timings).
    /// Only an audio memo can be a conversation (a note with bold headings is not).
    private var isConversation: Bool { file.sourceType == .audio && SpeakerTranscript.isAttributed(file.transcript) }

    /// One shared rule, so the Mac and the iPad can never describe the same note
    /// differently (`NoteWorkState`).
    private var workState: NoteWorkState { workInputs.state }
    private var primaryLabel: String { workState.label(for: file.destination) }

    private var hasParts: Bool {
        !(file.enhancedTitle ?? "").isEmpty
            && !(file.enhancedCopyedit ?? "").isEmpty
            && !(file.enhancedSummary ?? "").isEmpty
    }
    // Re-transcribe re-runs ASR and would destroy a conversation's speaker turns
    // (only copy lives in the transcript text) — disabled for diarized memos.
    private var canRetranscribe: Bool { transcribeDone && !isAppleNote && !isConversation }
    // The ⋯ used to be conditional (`canRetranscribe || hasParts`) because it
    // only held pipeline verbs. It now always carries Copy/Reveal, so it's
    // always there — a control that vanishes is worse than one that's short.

    /// The cloud store the tidy-up ledger lives behind; nil when Mac sync is off.
    private var cloudContext: ModelContext? {
        SettingsStore.shared.load().cloudKitMacSyncEnabled ? MemoCloudStore.container?.mainContext : nil
    }

    /// Q14/Q40: the one-time body tidy-up of an old note keeps its pre-tidy copy in a local
    /// ledger; the item shows while that copy exists and the text is still the tidied one.
    @ViewBuilder private var undoTidyUpItem: some View {
        if file.canUndoBodyNormalise(cloud: cloudContext) {
            Button(NoteMenuItem.undoTidyUp.label) { file.undoBodyNormalise(cloud: cloudContext) }
        }
    }

    /// Copying a locked note leaks the gated content — the note view's own
    /// unlock gate is the way in (same rule as the notes-list menu).
    @ViewBuilder private var copyItems: some View {
        let locked = LockGate.shared.isLocked(file)
        Button(NoteMenuItem.copyTranscript.label) { copy(file.transcript ?? "") }
            .disabled(locked)
        Button(NoteMenuItem.copyMarkdown.label) { copy(compiledMarkdown()) }
            .disabled(locked)
    }

    /// The note's ⋯ menu, in the shared order (`NoteMenuItem` — one vocabulary,
    /// two renderers). It used to hold Re-transcribe + three Redos and nothing
    /// else, while everything you'd actually reach for lived in the notes-list
    /// right-click — Tuur, 2026-07-25: the iPad's ⋯ "has way more stuff". The Mac
    /// now renders every note-scoped verb it can genuinely perform, here, where
    /// the note is. Absent on purpose (no Mac implementation, not an oversight):
    /// Remind me / Share note / Split speakers, and Lock — the Mac's lock lives
    /// only on the Review side's unrated `Memo` rows, and reaching it for an open
    /// `PipelineFile` needs a cloud write-back (its own chunk, see backlog).
    @ViewBuilder private var overflowItems: some View {
        if copyOnly {
            unratedOverflowItems
        } else {
            fullOverflowItems
        }
    }

    /// An unrated note's ⋯ (Q127): Process (floors the rating), Lock, Copy, Delete — the iPad's set
    /// (`MacUnratedMenu`). Reveal in Finder / Open in Obsidian are absent by FACT, not by policy:
    /// an unrated note has no working folder and has never been exported.
    @ViewBuilder private var unratedOverflowItems: some View {
        let entries = MacUnratedMenu.entries(rated: NoteConsent.isRated(file),
                                             locked: LockGate.shared.isLocked(file),
                                             canUndoTidyUp: file.canUndoBodyNormalise(cloud: cloudContext))
        ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
            if entry == .item(.delete) { Divider() }
            switch entry {
            case .process:
                Button(MacUnratedMenu.label(entry)) { processUnrated() }
            case .item(.undoTidyUp):
                Button(MacUnratedMenu.label(entry)) { file.undoBodyNormalise(cloud: cloudContext) }
            case .item(.lock), .item(.unlock):
                Button(MacUnratedMenu.label(entry)) { toggleUnratedLock() }
            case .item(.copyTranscript):
                Button(MacUnratedMenu.label(entry)) { copy(file.transcript ?? "") }
                    .disabled(LockGate.shared.isLocked(file))
            case .item(.copyMarkdown):
                Button(MacUnratedMenu.label(entry)) { copy(compiledMarkdown()) }
                    .disabled(LockGate.shared.isLocked(file))
            case .item(.delete):
                Button(MacUnratedMenu.label(entry), role: .destructive) { deleteUnrated() }
            case .item:
                EmptyView()
            }
        }
    }

    /// The synced `Memo` behind this unrated note's projection (same id, `MemoNoteProjection`).
    private var unratedMemo: Memo? {
        guard let uuid = UUID(uuidString: file.id),
              let cloud = MemoCloudStore.container?.mainContext else { return nil }
        return MemoCloudStore.memo(id: uuid, context: cloud)
    }

    /// Process on an unrated note IS a judgment (C40/D159): floor the rating. The pane
    /// (`UnratedNotePane`) mirrors a projection's rating onto the memo and kicks the reconcile
    /// sweep, so this writes the ONE place the circles write — no second door out of unrated.
    private func processUnrated() {
        file.significance = NoteConsent.flooredByProcess(file.significance)
    }

    /// Lock (instant) / remove lock (device-owner auth) through the shared `LockPolicy`, the
    /// same as the notes-list row menu.
    private func toggleUnratedLock() {
        guard let memo = unratedMemo else { return }
        Task {
            if memo.locked {
                guard await LockGate.shared.policy.removeLock(memo) else { return }
            } else if !LockGate.shared.policy.lock(memo) {
                coordinator.flash("Set a device passcode to lock notes")
                return
            }
            file.locked = memo.locked
            try? MemoCloudStore.container?.mainContext.save()
            NotificationCenter.default.post(name: .cloudMemosDidChangeFromSync, object: nil)
        }
    }

    /// Soft delete into the shared Recently Deleted (14 days, both devices); a locked note needs
    /// device-owner auth first (R88/C161) — the notes-list row's `deleteQuiet`.
    private func deleteUnrated() {
        guard let memo = unratedMemo else { return }
        Task {
            guard await LockGate.shared.policy.authorizeDelete(id: memo.id.uuidString, locked: memo.locked) else { return }
            memo.deletedAt = Date()
            memo.trashSeenAt = memo.deletedAt   // deleted in-session: the purge clock starts now (v3)
            MemoNoteProjection.discardMedia(for: memo.id)
            try? MemoCloudStore.container?.mainContext.save()
            NotificationCenter.default.post(name: .cloudMemosDidChangeFromSync, object: nil)
            coordinator.flash("Moved to Recently Deleted")
            onRemoved?()
        }
    }

    @ViewBuilder private var fullOverflowItems: some View {
        if isConversation {
            Button(NoteMenuItem.flattenToMonologue.label) {
                Task { await coordinator.flattenToMonologue(file, context: ctx) }
            }
        }
        if canRetranscribe {
            Button(NoteMenuItem.retranscribe.label) { Task { await coordinator.retranscribe(file, context: ctx) } }
        }
        if hasParts {
            Menu(NoteMenuItem.redo.label) {
                Button(NoteRedoItem.title.label) { Task { await coordinator.redo(.title, for: file, context: ctx) } }
                // Copy-edit strips a conversation's `**Name:**` turn prefixes —
                // hidden for diarized memos (they stay verbatim, like the phone).
                if !isConversation {
                    Button(NoteRedoItem.copyEdit.label) { Task { await coordinator.redo(.copyEdit, for: file, context: ctx) } }
                }
                Button(NoteRedoItem.summary.label) { Task { await coordinator.redo(.summary, for: file, context: ctx) } }
            }
        }
        undoTidyUpItem
        Divider()
        copyItems
        Button(NoteMenuItem.revealInFinder.label) { revealInFinder() }
            .disabled(file.path.isEmpty)
        if file.steps.export == .done, let p = file.exported, !p.isEmpty {
            Button(NoteMenuItem.openInObsidian.label) { NSWorkspace.shared.open(URL(fileURLWithPath: p)) }
        }
    }

    private func copy(_ text: String) {
        guard !text.isEmpty else { coordinator.flash("Nothing to copy yet"); return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func compiledMarkdown() -> String {
        file.compiledText ?? Compiler.compile(file: file,
                                              author: SettingsStore.shared.load().authorName,
                                              knownPeople: NamesStore.shared.livePeople())
    }

    private func revealInFinder() {
        guard !file.path.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: file.path)])
    }

    /// THIS note's run state (Q118): the coordinator's live run mapped onto this note, plus the
    /// note's own failure. The Mac's `PolishCenter.Phase`.
    private var runState: MacNoteRunState {
        MacNoteRunState.of(noteID: file.id, run: coordinator.runState?.snapshot,
                           transcribe: file.transcribeStatus, enhance: file.enhanceStatus,
                           error: file.error, needsProcessing: workState.wantsProcessing)
    }

    private func primaryAction() {
        // The verb is replaced while a run is on this note; this guards a stray key-equivalent.
        guard !runState.isBusy else { return }
        if !enhanceDone {
            Task { await coordinator.process(fileIDs: [file.id], context: ctx) }
        } else {
            Task { await coordinator.export(file, context: ctx) }
        }
    }

    /// The verb, or while a pass runs on this note a bar + step line in its place (the iPad's
    /// `processControl`), or after a failed pass "Couldn't process — Retry".
    @ViewBuilder private var primaryControl: some View {
        switch runState {
        case .idle:
            Button(action: primaryAction) {
                Text(primaryLabel)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
        case .queued:
            runCapsule(line: MacNoteRunState.queuedLine, fraction: nil)
        case .loading(let line, let fraction):
            runCapsule(line: line, fraction: fraction)
        case .running(let line, let fraction):
            runCapsule(line: line, fraction: fraction)
        case .failed(let reason):
            Button(action: primaryAction) {
                HStack(spacing: 5) {
                    Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 10.5))
                    Text("\(MacNoteRunState.failedLine) — Retry").font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(Theme.destructive)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Theme.destructive.opacity(0.12), in: Capsule())
            }
            .buttonStyle(.plain)
            .help(reason.isEmpty ? MacNoteRunState.failedLine : reason)
            .accessibilityIdentifier("note-process-retry")
        }
    }

    private func runCapsule(line: String, fraction: Double?) -> some View {
        HStack(spacing: 8) {
            if let fraction {
                ProgressView(value: fraction)
                    .progressViewStyle(.linear)
                    .frame(width: 74)
                    .tint(Theme.accentText)
            }
            Text(line)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(Theme.accentText)
                .lineLimit(1)
        }
        .padding(.horizontal, 11).padding(.vertical, 7)
        .background(Theme.accent.opacity(0.14), in: Capsule())
        .accessibilityIdentifier("note-process-progress")
    }

    var body: some View {
        HStack(spacing: 8) {
            if !copyOnly {
                primaryControl
            }

            // Native Menu: auto-dismisses on outside click (N3) and the items
            // run real actions (N4). Default-closed, so it snapshots fine.
            Menu { overflowItems } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.textSecondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
                // Glass chip, like every other control in the note toolbar —
                // nothing hangs bare (mirrors the iPad's ⋯, signed mock
                // ipad-note-chrome-belongs.html). Process keeps its tinted capsule.
                // GOTCHA: on macOS the chip must wrap the MENU, not its label — a
                // `Menu` label's own background never draws (caught by the hosted
                // `-snapshot-inspector` render; ImageRenderer draws a Menu as a
                // placeholder, so the plain-ImageRenderer path can't see this).
            .frame(width: 30, height: 30)
            .barGlass()
        }
    }

}
