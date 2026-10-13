import SwiftUI

/// The phone/iPad look for the shared `TagEditorRow` (C240) — 14 pt chips, 30 pt
/// tall, tap-arms-then-removes (D139 signed mock `tag-ui-revamp.html`).
///
/// App-only on purpose: it lives outside `Theme.swift` so the share extension, which
/// compiles Theme.swift, doesn't also have to compile `TagEditorRow`/`TagRules`/`FlowLayout`.
extension TagRowStyle {
    static let phone = TagRowStyle(
        chipFont: .system(size: 14, weight: .medium), chipHeight: 30, chipHPad: 12,
        fieldWidth: 110, armsOnTap: true,
        textColor: .skAccentText, backgroundColor: .skAccentSoft, dimTextColor: .skTextDim,
        elevColor: .skElev, borderColor: .skBorder, dangerColor: .skRed,
        fieldBackground: .skElev, fieldBorder: .skBorder)

    /// The note header's tags (Q359, mock Q350 pick 7): quiet accent words on the rating
    /// row — no chip fill, no outline — with "+ tag" in faint text.
    static let phoneInline = TagRowStyle(
        chipFont: .system(size: 13, weight: .medium), chipHeight: 26, chipHPad: 0,
        fieldWidth: 100, armsOnTap: true,
        textColor: .skAccentText, backgroundColor: .clear, dimTextColor: .skTextFaint,
        elevColor: .skElev, borderColor: .clear, dangerColor: .skRed,
        fieldBackground: .skElev, fieldBorder: .skBorder)
}
