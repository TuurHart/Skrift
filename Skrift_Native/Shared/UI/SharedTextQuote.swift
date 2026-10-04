import SwiftUI

// Q285 (C240, D170): the shared TEXT capture is a borderless italic quote with an accent bar,
// no card, no kicker. One view here; the per-app part is a style struct (the `NoteCardStyle`
// pattern). No `#if os()` in this file. Link, file and photo captures keep their cards.

/// Colours + size for the quote. Numbers match the phone's original `captureTextQuote`.
struct SharedTextQuoteStyle {
    var text: Color
    var bar: Color
    var fontSize: CGFloat = 15
    var lineSpacing: CGFloat = 4
    var barWidth: CGFloat = 2.5
    var barInset: CGFloat = 14
}

/// The shared-text quote: italic text, accent bar on the left, nothing around it.
struct SharedTextQuote: View {
    let text: String
    let style: SharedTextQuoteStyle

    var body: some View {
        Text(text)
            .font(.system(size: style.fontSize).italic())
            .lineSpacing(style.lineSpacing)
            .foregroundStyle(style.text)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, style.barInset)
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: style.barWidth / 2)
                    .fill(style.bar)
                    .frame(width: style.barWidth)
            }
    }
}
