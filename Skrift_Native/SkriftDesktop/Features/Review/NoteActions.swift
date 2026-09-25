import SwiftUI
import AppKit

/// Contextual primary action (Process → Export to Obsidian → Re-export) plus a ⋯
/// overflow (re-transcribe, redo per-step). Ported from `NoteActions.tsx`.
/// Actions are stubbed until the export/enhance pipeline is wired to the UI.
struct NoteActions: View {
    let file: PipelineFile
    var coordinator: ProcessingCoordinator
    /// UNRATED note (`MemoNoteProjection`): drop the primary Process/Export button and
    /// every pipeline verb, keep the ⋯ with the verbs that need no pipeline row.
    /// Copying text that's already on your screen is not something a rating should
    /// gate (Tuur, 2026-07-26: "this is not one of those differences").
    var copyOnly = false
    @Environment(\.modelContext) private var ctx

    /// Polished — by ANY device. `steps.enhance` is only ever set by THIS Mac's own run,
    /// so a note the iPad polished came back through `MemoCloudUpdate.apply` with its
    /// content (enhancedTitle/Copyedit/Summary all populated) but its step untouched — and
    /// the button offered "Process" for work already done, which would redo it (Tuur,
    /// 2026-08-14). Processed is processed, whoever ran it: the same rule `ProcessPile`
    /// keys on, and the reason polish is worth syncing at all.
    ///
    /// ALL THREE parts, not any one: `enhancedTitle` is also written from the user's CHOSEN
    /// title (`MemoCloudUpdate`), so an "any part present" test would call a merely-retitled
    /// note processed. A real polish always produces all three.
    private var enhanceDone: Bool { file.steps.enhance == .done || hasParts }
    private var exported: Bool { file.steps.export == .done }
    private var isAppleNote: Bool { file.sourceType == .note }
    private var transcribeDone: Bool { file.steps.transcribe == .done }
    /// A speaker-attributed (conversation) transcript — its `**Name:**` turns are the
    /// ONLY copy of the diarization (the phone never uploads segments/word-timings).
    /// Only an audio memo can be a conversation (a note with bold headings is not).
    private var isConversation: Bool { file.sourceType == .audio && SpeakerTranscript.isAttributed(file.transcript) }

    /// One shared rule, so the Mac and the iPad can never describe the same note
    /// differently (`NoteWorkState`).
    private var workState: NoteWorkState { .of(hasPolish: enhanceDone, isExported: exported) }
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
            // Reveal in Finder / Open in Obsidian are absent by FACT, not by policy:
            // an unrated note has no working folder and has never been exported.
            let locked = LockGate.shared.isLocked(file)
            Button(NoteMenuItem.copyTranscript.label) { copy(file.transcript ?? "") }
                .disabled(locked)
            Button(NoteMenuItem.copyMarkdown.label) { copy(compiledMarkdown()) }
                .disabled(locked)
        } else {
            fullOverflowItems
        }
    }

    @ViewBuilder private var fullOverflowItems: some View {
        if isConversation, file.sourceType == .audio {
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
        Divider()
        // Copying a locked note leaks the gated content — the note view's own
        // unlock gate is the way in (same rule as the notes-list menu).
        let locked = LockGate.shared.isLocked(file)
        Button(NoteMenuItem.copyTranscript.label) { copy(file.transcript ?? "") }
            .disabled(locked)
        Button(NoteMenuItem.copyMarkdown.label) { copy(compiledMarkdown()) }
            .disabled(locked)
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

    private func primaryAction() {
        if !enhanceDone {
            Task { await coordinator.process(fileIDs: [file.id], context: ctx) }
        } else {
            Task { await coordinator.export(file, context: ctx) }
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            if !copyOnly {
                Button(action: primaryAction) {
                    Text(primaryLabel)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
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
