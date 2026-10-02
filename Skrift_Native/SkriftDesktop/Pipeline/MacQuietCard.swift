import Foundation

/// The Mac's card model for a note that has no pipeline row (unrated quiet rows, locked-quiet
/// rows, stranded rated rows, fading search hits). Q107 (C115 / D136 / D135 / C98; parity audit
/// list-sidebar-67/69/71/75/79): it follows the phone's `MemoCard.cardModel` rule for rule —
/// tags, place and weather chips from the shared `NoteCardBuilder`; the amber fading line only
/// inside the 7-day window (`MemoSpine.rowClockLine`, the phone's own rule); no balls on a
/// locked row; the "2 versions" pill read from `EditConflictWatch`. Pure (the sidebar passes
/// the backlink and conflict sets in) so the host-less test bundle pins it.
enum MacQuietCard {
    @MainActor
    static func model(for memo: Memo, selected: Bool, backlinked: Set<UUID>,
                      conflicts: Set<UUID> = EditConflictWatch.shared.ids,
                      now: Date = Date()) -> NoteCardModel {
        let stamp = MemoDate.label(memo.recordedAt)
        let conflicted = conflicts.contains(memo.id)
        // Locked ⇒ title + 🔒 and nothing else (C91/C161, R88) — still IN the list, dimmed. The
        // two-versions pill outranks every other state, locked or not (the phone sets it first).
        if memo.locked {
            var l = LockedRow.card(stamp: stamp, title: LockedRow.title(for: memo), selected: selected, quiet: true)
            if conflicted { l.statusPill = .twoVersions }
            return l
        }
        var m = NoteCardModel(stamp: stamp)
        m.quiet = true
        m.selected = selected
        m.locked = false
        // Unrated memos ARE 0 — three hollow balls, the phone's readout (D135). A stranded RATED
        // memo shows its own balls.
        m.balls = ThreeBallScale.step(for: memo.significance)
        // D136: no standing spine line on a quiet row — the amber line appears only within 7 days
        // of fading (or once fading, as a search hit). A stranded rated memo keeps the honest
        // waiting line, which the phone has no equivalent of (it never strands).
        m.fadingLine = MemoSpine.rowClockLine(for: memo, backlinked: backlinked, now: now)
        m.quietLine = NoteConsent.isRated(memo) ? WayOutRules.strandedLine(for: memo) : nil
        if conflicted { m.statusPill = .twoVersions }
        // Q106 (C115): title, quote, snippet and source / book / duration / place / weather / tag
        // chips from the ONE shared builder the rated rows and the phone call.
        m.apply(NoteCardBuilder.content(for: memo.cardFacts()))
        return m
    }
}
