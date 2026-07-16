import Foundation

// THE cross-app color table (SharedKit wave 2) — hex VALUES only, no Color types.
// Each app's Theme keeps its own dynamic wrapper (UIColor / NSColor provider) and
// sources these constants, so a semantic color can never again be tuned twice
// (the warmFill-drift class of bug — fixed by construction). App-specific tokens
// (Mac sidebar/step colors, phone chip fills) stay in each app's Theme: they have
// no twin to drift from.

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
}
