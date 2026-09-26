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
    /// The always-on spine line, triage surfaces (iPad regular) only.
    var quietLine: String? = nil
    /// iPad split view (m1): the row backing the detail pane wears `skAccentSoft`.
    /// Always false on the phone (`selectedMemoID` is nil there).
    var selected: Bool = false
    let onTap: () -> Void
    @Environment(\.editMode) var editMode

    var body: some View {
        if editMode?.wrappedValue.isEditing == true {
            // Multi-select uses the List's own selection chrome — no detail-pane
            // highlight while editing.
            MemoCard(memo: memo, enhancedTitle: enhancedTitle, fading: fading, clockLine: clockLine,
                     quiet: quiet, quietLine: quietLine)
        } else {
            // A Button, NOT .onTapGesture: a tap gesture on a List row fights
            // the context-menu lift on iOS 26 — a long-press just started the
            // row drifting as if scrolling and the menu never opened (device
            // round 1). The system resolves Button-tap vs long-press-menu vs
            // scroll natively.
            Button(action: onTap) {
                MemoCard(memo: memo, enhancedTitle: enhancedTitle, fading: fading, clockLine: clockLine,
                         quiet: quiet, quietLine: quietLine, selected: selected)
                    .contentShape(Rectangle())
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
    /// The spine one-liner a quiet row carries on TRIAGE surfaces only (iPad
    /// regular; the Mac list has its own) — the phone notebook keeps its
    /// urgency-only amber `clockLine` instead. Faint, not amber: quiet ≠
    /// urgent; a present status pill outranks it in the slot.
    var quietLine: String? = nil
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
        m.quietLine = quietLine
        m.quiet = quiet
        m.selected = selected
        m.locked = memo.locked
        m.balls = memo.locked ? nil : ThreeBallScale.step(for: memo.significance)
        if let kind = memo.statusKind {
            let pillKind: NoteCardModel.Pill.Kind = switch kind {
            case .synced: .done
            case .waiting: .amber
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
        if memo.isShareCapture {
            m.title = memo.shareCaptureTitle
            m.snippet = memo.shareCaptureSnippet
        } else if hasTitle {
            m.title = memo.displayTitle(enhancedTitle: enhancedTitle)
            if memo.isBookCapture, let quote = memo.quoteSnippet {
                m.quote = quote
            } else {
                m.snippet = transcriptSnippet
            }
        } else {
            if memo.isBookCapture, let quote = memo.quoteSnippet {
                m.quote = quote
                m.snippet = transcriptSnippet
            } else {
                m.snippet = snippet
            }
        }
        m.chips = chips.map { .init(text: $0.text, systemImage: $0.symbol, isTag: false) }
        // Source glyph joins the chips (m2 has no leading glyph column) + the tags.
        if !memo.isShareCapture, !memo.isBookCapture {
            let kind = SourceKind.of(memo)
            if kind != .voiceMemo {
                m.chips.insert(.init(text: kind.label, systemImage: kind.glyph), at: 0)
            }
        }
        m.chips.append(contentsOf: NoteCardModel.tagChips(for: memo.tags))
        if let filename = memo.thumbnailPhotoFilename,
           let img = MemoImageLoader.thumbnail(at: AppPaths.recordingsDirectory.appendingPathComponent(filename), maxWidth: 96) {
            m.thumb = Image(uiImage: img)
        }
        return m
    }

    struct Chip: Hashable { let text: String; let symbol: String? }

    var chips: [Chip] {
        var out: [Chip] = []
        // C3 share-item captures show a type label + optional domain instead of duration.
        if memo.isShareCapture {
            out.append(Chip(text: memo.shareCaptureTypeLabel, symbol: memo.shareCaptureGlyph))
            if let domain = memo.shareCaptureURLDomain {
                out.append(Chip(text: domain, symbol: nil))
            }
            return out
        }
        // Audiobook captures lead the meta line with "Book · ch. N".
        if let book = memo.bookCaptionLabel {
            out.append(Chip(text: book, symbol: SourceKind.audiobookQuote.glyph))
        }
        // Video imports lead the meta line with a "Video" source chip.
        if memo.isVideoImport {
            out.append(Chip(text: SourceKind.video.label, symbol: SourceKind.video.glyph))
        }
        // No duration chip on a note that HAS no audio (typed notes, Apple Note
        // imports) — a permanent "0:00" claims a recording that doesn't exist.
        if !memo.audioFilename.isEmpty {
            out.append(Chip(text: memo.durationLabel, symbol: nil))
        }
        if let place = memo.metadata?.location?.placeName, !place.isEmpty {
            out.append(Chip(text: place, symbol: "mappin.circle.fill"))
        }
        if let w = memo.metadata?.weather { out.append(Chip(text: "\(w.temperature)°", symbol: "cloud.sun.fill")) }
        return out
    }

    /// True when this row has a title to lead with — the user's own, else the Mac's
    /// generated one. Without the second arm a polished note showed its title in detail
    /// and its body text in the list.
    var hasTitle: Bool {
        if !(memo.title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) { return true }
        return !(enhancedTitle?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }
    var snippet: String {
        // "Note" for a typed note, "Voice note" otherwise — the shared fallback
        // (mocks/mac-new-note.html m3: "Voice note" on something you wrote reads
        // as a bug).
        guard let line = memo.firstTranscriptLine else {
            return SourceKind.of(memo).emptyTitleFallback
        }
        guard let transcript = memo.transcript else { return line }
        // Show the (2-line) transcript, but strip `[[img_NNN]]` markers so the raw
        // marker never reads as the row text — a VIDEO import always opens with
        // `[[img_001]]` (the frame), which otherwise filled the whole snippet.
        let cleaned = transcript
            .replacingOccurrences(of: #"\[\[img_\d+\]\]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\n{2,}"#, with: "\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? line : cleaned
    }
    /// Secondary line for titled rows: the transcript's first line, markers stripped.
    /// Nil when there's no transcript yet (the title alone carries the row).
    var transcriptSnippet: String? { memo.firstTranscriptLine }
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

