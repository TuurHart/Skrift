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
}
