import SwiftUI

// MARK: - Row

/// A memo row: taps open detail in normal mode; in EditMode the tap is left to the
/// List so its native multi-select (incl. drag-over-rows) and selection circle work.
/// Conditionally attaching the tap (rather than guarding inside it) is what frees the
/// tap for List selection — a no-op gesture would still swallow it. No NavigationLink,
/// so no disclosure chevron over the card.
struct MemoRow: View {
    let memo: Memo
    /// The Mac's generated title, when the user hasn't chosen one (display-only).
    var enhancedTitle: String? = nil
    var fading: Bool = false
    var clockLine: String? = nil
    /// iPad split view (m1): the row backing the detail pane wears `skAccentSoft`.
    /// Always false on the phone (`selectedMemoID` is nil there).
    var selected: Bool = false
    /// Regular width (the tap drives the detail pane instead of pushing). Only here so a row whose
    /// tap closure was built for the other width is not reused after a rotation.
    var regularWidth: Bool = false
    /// Q358: where the row sits in its group's one card (D194).
    var position: NoteCardModel.GroupPosition = .only
    let onTap: () -> Void
    @Environment(\.editMode) var editMode

    /// Q323: everything the parent hands this row besides the closure. Two rows with equal inputs
    /// draw the same card; whatever the note itself changes (title, tags, photos, rating) reaches the
    /// card through Observation inside `MemoCard`, not through the parent re-running.
    struct Inputs: Equatable {
        var memo: ObjectIdentifier
        var enhancedTitle: String?
        var fading: Bool
        var clockLine: String?
        var selected: Bool
        var regularWidth: Bool
        var position: NoteCardModel.GroupPosition
    }
    var inputs: Inputs {
        Inputs(memo: ObjectIdentifier(memo), enhancedTitle: enhancedTitle, fading: fading,
               clockLine: clockLine, selected: selected, regularWidth: regularWidth,
               position: position)
    }

    var body: some View {
        // Multi-select uses the List's own selection chrome — no detail-pane
        // highlight while editing.
        let editing = editMode?.wrappedValue.isEditing == true
        let card = MemoCard(memo: memo, enhancedTitle: enhancedTitle, fading: fading,
                            clockLine: clockLine,
                            selected: editing ? false : selected, position: position)
        if editing {
            card
        } else {
            // A Button, NOT .onTapGesture: a tap gesture on a List row fights
            // the context-menu lift on iOS 26 — a long-press just started the
            // row drifting as if scrolling and the menu never opened (device
            // round 1). The system resolves Button-tap vs long-press-menu vs
            // scroll natively.
            Button(action: onTap) {
                card.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}

/// Q323: the list applies `.equatable()` to each row, so a parent pass that changes nothing about this
/// row (a search keystroke that keeps it, a sync batch, a patch to another note) skips its body, the
/// card-model build and the self-sizing pass. The tap closure is not compared (it only reads state).
extension MemoRow: Equatable {
    static func == (a: MemoRow, b: MemoRow) -> Bool { a.inputs == b.inputs }
}

// MARK: - Card

struct MemoCard: View {
    let memo: Memo
    /// The Mac's generated title, when the user hasn't chosen one (display-only).
    var enhancedTitle: String? = nil
    /// Surfaced by SEARCH while fading — wears the honest amber tag.
    var fading: Bool = false
    /// The urgency-only clock line ("starts fading 28 Jul" / "moves to
    /// Recently Deleted in 3d"), computed once at the list level (backlink
    /// scan is never per-row). Non-nil ⇒ the clock is short ⇒ amber.
    var clockLine: String? = nil
    /// iPad split view (m1): the selected row (its note is in the detail pane)
    /// gets an accent-soft fill. Always false on the phone.
    var selected: Bool = false
    /// Q358: where the row sits in its group's one card.
    var position: NoteCardModel.GroupPosition = .only

    /// m2 adapter (2026-08-19, chunk 2 of the un-twinning): every derivation this
    /// card owned now FEEDS the shared `NoteCardView` instead of a hand-built
    /// layout — the Mac maps its own rows into the same view, so the two lists
    /// cannot drift again ("make sure the ipad also follows that one to the T").
    var body: some View {
        NoteCardView(model: cardModel, style: .skrift)
            .accessibilityIdentifier(memo.isShareCapture ? "capture-row" : "memo-card")
    }

    var cardModel: NoteCardModel {
        // D190: line 2 leads with the list date ("09:41", "Yesterday", "Friday", "27 Sep").
        var m = NoteCardModel(stamp: MemoDate.listDate(memo.recordedAt))
        m.position = position
        m.fadingLine = clockLine ?? (fading ? "fading" : nil)
        m.selected = selected
        m.locked = memo.locked
        m.balls = memo.locked ? nil : ThreeBallScale.step(for: memo.significance)
        if let kind = memo.statusKind {
            let pillKind: NoteCardModel.Pill.Kind = switch kind {
            case .transcribing: .progress
            case .error: .error
            }
            m.statusPill = .init(label: kind.label, kind: pillKind, pulses: kind == .transcribing)
        }
        // D139: two versions outrank every other state in the pill slot.
        if EditConflictWatch.shared.ids.contains(memo.id) { m.statusPill = .twoVersions }
        // C155: a change iCloud has not taken yet.
        m.statusPill = .withSync(m.statusPill, unsynced: SyncHealthMonitor.shared.unsynced.contains(memo.id))
        if memo.locked {
            m.title = memo.title?.isEmpty == false ? memo.title : "Locked note"
            return m   // locked rows show title + 🔒 and NOTHING else
        }
        // Q106 (C115): title, quote and snippet come from the ONE shared builder
        // the Mac's rows call too (`NoteCardBuilder`); only the chrome above is this app's.
        let facts = memo.cardFacts(generatedTitle: enhancedTitle)
        m.apply(NoteCardBuilder.content(for: facts))
        m.media = NoteCardBuilder.media(for: facts)
        m.portfolio = memo.destination.isPortfolio
        if let filename = memo.thumbnailPhotoFilename,
           let img = MemoImageLoader.thumbnail(at: AppPaths.recordingsDirectory.appendingPathComponent(filename), maxWidth: 96) {
            m.thumb = Image(uiImage: img)
        }
        return m
    }
}

// MARK: - Quick copy

extension Memo {
    /// What a quick "Copy" copies: the transcript when there is one, else the
    /// title; nil when the memo has neither (not yet transcribed, untitled)
    /// OR when it's locked and this session hasn't unlocked it (R88 — Copy is
    /// gated behind auth, C213 — same rule the player's `audioURL` load uses).
    @MainActor
    var copyableText: String? {
        guard !LockGate.shared.isLocked(self) else { return nil }
        if let t = transcript, !t.isEmpty { return t }
        if let t = title, !t.isEmpty { return t }
        return nil
    }
}

