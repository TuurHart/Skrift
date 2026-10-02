import Foundation

// THE cross-app color table (SharedKit wave 2) — hex VALUES only, no Color types.
// Each app's Theme keeps its own dynamic wrapper (UIColor / NSColor provider) and
// sources these constants, so a semantic color can never again be tuned twice
// (the warmFill-drift class of bug — fixed by construction). App-specific tokens
// (Mac sidebar/step colors) stay in each app's Theme: they have no twin to drift
// from — the moment one grows a twin it moves here (chipFill/accentText, 2026-07-25).

/// One light/dark hex pair — a color both apps agree on.
struct PalettePair: Sendable {
    let light: UInt32
    let dark: UInt32
}

/// A cross-app token whose two apps DISAGREE today (drift found by the wave-2
/// extraction, 2026-07-16 — light columns tuned twice, differently). Kept
/// per-app so this refactor changes ZERO pixels; each entry is a pending
/// reconciliation (eyeball round → collapse to one PalettePair).
struct DriftedPair: Sendable {
    let phone: PalettePair
    let mac: PalettePair
}

enum Palette {
    // Agreed cross-app tokens                      light       dark
    static let surface    = PalettePair(light: 0xffffff, dark: 0x181a23)
    static let accent     = PalettePair(light: 0x6c5ce0, dark: 0x7c6bf5)
    static let green      = PalettePair(light: 0x0f9d72, dark: 0x34d399)
    static let amber      = PalettePair(light: 0xd97706, dark: 0xf59e0b)
    static let red        = PalettePair(light: 0xdc2626, dark: 0xef4444)
    static let nameLinked = PalettePair(light: 0x6c5ce0, dark: 0x9d8ff7)
    /// Bar-control / field chip fill — the quiet container a toolbar control sits in
    /// (iPadOS-26 containment, signed mock ipad-note-chrome-belongs.html). Was a
    /// phone-only token until the Mac note toolbar mirrored the chrome (2026-07-25).
    static let chipFill   = PalettePair(light: 0xebebf0, dark: 0x1e2130)
    /// The lighter-purple accent for small text/labels on an accent-soft fill (tag
    /// text, an active bar chip). Deepens on light so it stays legible on white.
    static let accentText = PalettePair(light: 0x6051c8, dark: 0xb9acff)

    /// The accent-soft fill (selected row, active chip): `accent` at this alpha. ONE number
    /// (iPad was 0.13, Mac 0.16; Q177 took the phone's) that both Themes apply.
    static let accentSoftAlpha: Double = 0.13

    // Drifted cross-app tokens — reconcile pending an eyeball round.
    static let bg = DriftedPair(
        phone: PalettePair(light: 0xf5f5f7, dark: 0x0f1117),
        mac:   PalettePair(light: 0xf7f7fa, dark: 0x0f1117))
    static let textPrimary = DriftedPair(
        phone: PalettePair(light: 0x1c1c1e, dark: 0xe4e4e7),
        mac:   PalettePair(light: 0x1c1c20, dark: 0xe4e4e7))
    static let textSecondary = DriftedPair(
        phone: PalettePair(light: 0x6c6c72, dark: 0x8b8b97),
        mac:   PalettePair(light: 0x6c6c76, dark: 0x8b8b97))
    static let textTertiary = DriftedPair(
        phone: PalettePair(light: 0xa3a3aa, dark: 0x55556a),
        mac:   PalettePair(light: 0x9696a2, dark: 0x55556a))
    static let nameSuggest = DriftedPair(
        phone: PalettePair(light: 0x8a6d3b, dark: 0xbda481),
        mac:   PalettePair(light: 0x966e30, dark: 0xbda481))
    static let nameSuggestLine = DriftedPair(
        phone: PalettePair(light: 0xa8843f, dark: 0xc4a982),
        mac:   PalettePair(light: 0x966e30, dark: 0xab9676))

    // ── Speaker identity (conversation turns, 2026-07-27) ────────────────────────
    //
    // A colour per voice, so a two-person conversation is followed by hue instead of by
    // reading forty names (signed mock `mocks/conversation-turns-D-hifi.html`, E1+b).
    //
    // Keyed by DIARIZATION SLOT, never by name or by order of appearance: renaming
    // "Speaker 2" to "Bulldops", or the Sanitiser resolving a header to a roster person,
    // must not reshuffle every colour in the note. The slot is stable for the life of the
    // diarization (`DiarizationData.slotNames` keys, `turnSlots`).
    //
    // NOT semantic colours. `green`/`amber`/`red` above mean good/warning/bad app-wide —
    // borrowing one would make a speaker read as a verdict (the placeholder in the first
    // mock used `green` and it was wrong for exactly that reason). These are six hues
    // chosen only to be told apart: teal, rose, sky, apricot, violet-blue, moss. All sit
    // clear of `accent` (#6c5ce0/#7c6bf5) so "this turn is playing" stays unambiguous, and
    // clear of `nameLinked` so a linked person still reads as a link.
    //
    // Light values are darkened for contrast on white; dark values lightened. Both were
    // picked at the same perceived weight so no speaker looks more important than another.
    static let speakerHues: [PalettePair] = [
        PalettePair(light: 0x0f7d74, dark: 0x5fd4c4),   // 0 teal
        PalettePair(light: 0xa8446a, dark: 0xf08cae),   // 1 rose
        PalettePair(light: 0x2b6cb0, dark: 0x7cb8f0),   // 2 sky
        PalettePair(light: 0x9a5b1c, dark: 0xe0a465),   // 3 apricot
        PalettePair(light: 0x5a4fa8, dark: 0xa79bf0),   // 4 violet-blue
        PalettePair(light: 0x4f7a2b, dark: 0xa3cd77),   // 5 moss
    ]

    /// The hue for a diarization slot. Cycles past the table rather than running out —
    /// a 9-speaker recording repeats hues instead of losing the distinction entirely,
    /// and the gutter name is always there to disambiguate. Negative/unknown slots fold
    /// to 0 so an unslotted turn still renders.
    static func speakerHue(slot: Int) -> PalettePair {
        speakerHues[((slot % speakerHues.count) + speakerHues.count) % speakerHues.count]
    }
}
