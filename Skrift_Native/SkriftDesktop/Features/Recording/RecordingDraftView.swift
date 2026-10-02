import SwiftUI

/// The m1/m2/m4 surface: the note pane BECOMES the recording draft while
/// `LiveRecordingSession.phase` is `.starting`/`.live`/`.settling` (`RootView` routes here —
/// see its body's phase switch). Signed mock `mocks/mac-live-transcription.html`; m2's
/// dictation-style editing is the picked design (git log "m2 picked, build board written"),
/// so settled text is ALWAYS editable here — never m1's plain read-only recording surface.
///
/// Thin shell around `RecordingDraftBody`, a pure value view with no `LiveRecordingSession`
/// dependency of its own — see that type's doc for why the split exists.
struct RecordingDraftView: View {
    @Bindable var session: LiveRecordingSession

    var body: some View {
        RecordingDraftBody(
            phase: session.phase,
            settledText: $session.settledText,
            wetText: session.wetText,
            elapsedLabel: session.elapsedLabel,
            notice: session.notice
        )
    }
}

/// The title a live take shows once it starts settling — the same derivation the rest of
/// the app uses for a title-less note (first non-empty line, word-boundary clip via the
/// shared `NoteTitle`), so the pane's header and the sidebar's synthetic row can never
/// disagree. `nil` while there's no text yet (still shows the placeholder / "Recording…").
enum LiveTakeTitle {
    static func derive(from settledText: String) -> String? {
        let line = settledText
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first(where: { !$0.isEmpty })
        guard let line, !line.isEmpty else { return nil }
        return NoteTitle.clip(line)
    }
}

/// Pure value view — every fact it draws is a parameter, nothing reached from the
/// environment or a live session. This is what lets `-snapshot-livedraft` (`Snapshot.swift`)
/// fixture-drive the live/settling states directly: a real `LiveRecordingSession` needs the
/// microphone and the caption engine to reach `.live`/`.settling`. Mirrors the existing `ConnectionsPanelBody`
/// idiom (a pure-view fixture injection — no engine, no `ModelContext`, mock-story values).
///
/// Renders the m1/m2 chrome while live (transport docked top-left, italic placeholder title,
/// meta chips, the "Not rated" line, an editable settled body + non-editable wet tail with a
/// pulsing caret) and m4's trimmed settling look (Tuur, 2026-07-28: "stop just stops" — the
/// transport simply vanishes, no narration; the title turns real; the wet tail keeps a
/// softer band while it firms up).
struct RecordingDraftBody: View {
    var phase: LiveRecordingSession.Phase
    @Binding var settledText: String
    var wetText: String
    var elapsedLabel: String
    /// The input died mid-take but the words so far are saved (recsj-029). nil = nothing to say.
    var notice: String? = nil

    @State private var pulse = false

    /// Only `.settling` drops the transport + swaps in the real derived title — every other
    /// phase this view is asked to render (`.starting`/`.live`) looks like m1/m2.
    private var isSettling: Bool { phase == .settling }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                draftBody
            }
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 30)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg)
        .onAppear { pulse = true }
        .accessibilityIdentifier("recording-draft-view")
    }

    // ── Header: transport (live only) → title → meta chips → not-rated line ──
    // The pane carries NO transport at all (Tuur, second live take: "you have two
    // recordings, one on the top of the screen and one in the recording bar" — the
    // sidebar's live timer is the one transport, and it is already the stop button).
    // The words streaming in are the pane's whole recording indicator.
    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let notice { noticeBanner(notice) }
            titleLine
            metaChipsRow
            notRatedLine
        }
        .padding(.bottom, 18)
    }

    /// A device loss mid-take, said where the user is looking — the take is NOT silently
    /// dead, and what was captured is safe.
    private func noticeBanner(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundStyle(Theme.destructive)
            Text(text)
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.destructive.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityIdentifier("recording-draft.notice")
    }

    @ViewBuilder private var titleLine: some View {
        if isSettling, let derived = LiveTakeTitle.derive(from: settledText) {
            Text(derived)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(2)
        } else {
            Text("First words become the title…")
                .font(.system(size: 22, weight: .bold))
                .italic()
                .foregroundStyle(Theme.textMuted)
                .lineLimit(2)
        }
    }

    private var metaChipsRow: some View {
        HStack(spacing: 6) {
            MacContextChip(text: SkriftFormat.breadcrumbDate(Date()), systemImage: "calendar")
            MacContextChip(text: SourceKind.voiceMemo.label, systemImage: SourceKind.voiceMemo.glyph)
            MacContextChip(text: elapsedLabel, systemImage: "waveform")
        }
    }

    /// The doctrine's own line, matched here so a live take reads the same "unrated" promise
    /// the quiet row and the significance card make once it lands (mocks/mac-live-transcription.html
    /// m1/m2/m4 all show this unchanged — only m5, the ordinary at-rest pane, swaps the copy).
    private var notRatedLine: some View {
        HStack(spacing: 8) {
            Circle().strokeBorder(Theme.textMuted, lineWidth: 1.5).frame(width: 11, height: 11)
            Text("Not rated — record first, judge later")
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.textMuted)
        }
    }

    // ── Body: editable settled text, then the engine's non-editable wet tail ──
    @ViewBuilder private var draftBody: some View {
        VStack(alignment: .leading, spacing: 2) {
            // TextEditor-style editable region: every keystroke lands straight on
            // `session.settledText` (via the binding) — that's what flips `everEdited`
            // on the session side. `scrollDisabled` lets it grow with the outer
            // ScrollView instead of nesting a second scroller. minHeight stays SMALL:
            // a tall floor padded empty space between the settled text and the wet
            // tail, which read as a paragraph break in the middle of a sentence
            // (vision-gate catch) — the tail must hug the text it continues.
            // The invisible twin gives the editor its CONTENT height: a bare
            // `scrollDisabled` TextEditor doesn't reliably grow (it clipped the fixture's
            // second paragraph in the hosted snapshot — and hostPNG has lied about system
            // controls before, so trusting live-layout-only growth would be a repeat).
            ZStack(alignment: .topLeading) {
                Text(settledText.isEmpty ? " " : settledText)
                    .font(.system(size: 15))
                    .lineSpacing(9)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .opacity(0)
                TextEditor(text: $settledText)
                    .font(.system(size: 15))
                    .lineSpacing(9)
                    .foregroundStyle(Theme.textPrimary)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .scrollDisabled(true)
                    .accessibilityIdentifier("recording-draft.settled-text")
            }
            if !wetText.isEmpty || !isSettling {
                wetTail
            }
        }
    }

    /// The engine's volatile tail — dim italic, NOT editable, with a soft accent band once
    /// it's mid-settle (m4) and a pulsing caret while still live (m1/m2 — gone once the
    /// transport is, since nothing is still streaming in).
    private var wetTail: some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(wetText)
                .font(.system(size: 15))
                .italic()
                .foregroundStyle(Theme.textMuted)
                .padding(.vertical, isSettling ? 1 : 0)
                .padding(.horizontal, isSettling ? 3 : 0)
                .background(isSettling ? Theme.accent.opacity(0.12) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 3))
            if !isSettling {
                Rectangle().fill(Theme.accent).frame(width: 2, height: 17)
                    .opacity(pulse ? 0.3 : 1)
                    .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: pulse)
            }
        }
        .accessibilityIdentifier("recording-draft.wet-tail")
    }

}

/// The sidebar's synthetic "Recording…" row (m1/m2/m4) — NOT a `PipelineFile`, purely
/// presentational from the session. Pinned above the ordinary queue rows by `SidebarView`.
struct LiveTakeRow: View {
    var phase: LiveRecordingSession.Phase
    var elapsedLabel: String
    var settledText: String

    private var title: String {
        guard phase == .settling, let derived = LiveTakeTitle.derive(from: settledText) else {
            return "Recording…"
        }
        return derived
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "mic.fill").font(.system(size: 10.5)).foregroundStyle(Theme.destructive).frame(width: 14)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text("today · \(elapsedLabel)").font(.system(size: 10)).foregroundStyle(Theme.textMuted)
            }
            Spacer(minLength: 6)
            if phase == .settling {
                Text("settling…")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.accentText)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Theme.chip, in: Capsule())
            } else {
                Circle().fill(Theme.destructive).frame(width: 7, height: 7)
                    .opacity(0.85)
            }
        }
        .padding(.horizontal, 9).padding(.vertical, 6)
        // "Selected style" (brief) — the SAME accent tint `QueueRowView` uses for its
        // `selected` row, since this row IS the selected one for as long as it's shown.
        .background(Theme.accent.opacity(0.13), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.accent.opacity(0.2), lineWidth: 1))
        .accessibilityIdentifier("sidebar.live-take-row")
    }
}
