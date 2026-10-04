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
    /// Unrated-live fade (every width — see MemoCard.quiet).
    var quiet: Bool = false
    /// iPad split view (m1): the row backing the detail pane wears `skAccentSoft`.
    /// Always false on the phone (`selectedMemoID` is nil there).
    var selected: Bool = false
    let onTap: () -> Void
    @Environment(\.editMode) var editMode

    var body: some View {
        // Multi-select uses the List's own selection chrome — no detail-pane
        // highlight while editing.
        let editing = editMode?.wrappedValue.isEditing == true
        let card = MemoCard(memo: memo, enhancedTitle: enhancedTitle, fading: fading,
                            clockLine: clockLine, quiet: quiet,
                            selected: editing ? false : selected)
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
    /// Unrated-live fade (m1b B + Tuur's 2026-07-23 phone extension: "when I
    /// take a note that I know is important I give it a score straight away" —
    /// so unrated genuinely means untriaged, on EVERY width): the row dims and
    /// wears the hollow ○ (the unfilled significance circles' own idiom).
    /// Rating the note IS the flag — no Flag verb anywhere.
    var quiet: Bool = false
    /// iPad split view (m1): the selected row (its note is in the detail pane)
    /// gets an accent-soft fill. Always false on the phone.
    var selected: Bool = false

    /// m2 adapter (2026-08-19, chunk 2 of the un-twinning): every derivation this
    /// card owned now FEEDS the shared `NoteCardView` instead of a hand-built
    /// layout — the Mac maps its own rows into the same view, so the two lists
    /// cannot drift again ("make sure the ipad also follows that one to the T").
    var body: some View {
        // Q26 fix (BUGS §4): this used to layer .opacity(0.55) OVER NoteCardView's
        // own quiet dim (0.62), so an unrated row read at 0.34 — nearly invisible.
        // `m.quiet` below already drives the ONE dim; this view adds nothing on top.
        NoteCardView(model: cardModel, style: .skrift)
            .accessibilityIdentifier(memo.isShareCapture ? "capture-row" : "memo-card")
    }

    var cardModel: NoteCardModel {
        var m = NoteCardModel(stamp: MemoDate.label(memo.recordedAt))
        m.fadingLine = clockLine ?? (fading ? "fading" : nil)
        m.quiet = quiet
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
        if memo.locked {
            m.title = memo.title?.isEmpty == false ? memo.title : "Locked note"
            return m   // locked rows show title + 🔒 and NOTHING else
        }
        // Q106 (C115): title, quote, snippet and chips come from the ONE shared builder
        // the Mac's rows call too (`NoteCardBuilder`); only the chrome above is this app's.
        m.apply(NoteCardBuilder.content(for: memo.cardFacts(generatedTitle: enhancedTitle)))
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

