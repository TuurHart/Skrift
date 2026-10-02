import SwiftUI

/// The Review "Fading" entry row — ONE view for the phone's Review river and the Mac
/// Journal rail (Q169; was an SF leaf + unread dot + count on the phone and a 🍂 emoji,
/// no dot, a different count on the Mac). Each app passes its `WayOutEntryStyle`.
struct WayOutEntryStyle {
    var amber: Color
    var text: Color
    var textDim: Color
    var textFaint: Color
    var fill: Color
    var glyphSize: CGFloat
    var titleFont: Font
    var countFont: Font
    var cornerRadius: CGFloat
    var horizontalPadding: CGFloat
    var verticalPadding: CGFloat
}

struct WayOutEntryRow: View {
    let count: Int
    let unread: Bool
    var isOn = false
    let style: WayOutEntryStyle

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: WayOut.entryGlyph)
                .font(.system(size: style.glyphSize))
                .foregroundStyle(style.amber)
            Text(WayOut.entryTitle)
                .font(style.titleFont)
                .foregroundStyle(isOn ? style.text : style.textDim)
            if unread {
                Circle().fill(style.amber).frame(width: 6, height: 6)
            }
            Spacer(minLength: 8)
            if count > 0 {
                Text("\(count)")
                    .font(style.countFont)
                    .foregroundStyle(style.textFaint)
            }
        }
        .padding(.horizontal, style.horizontalPadding)
        .padding(.vertical, style.verticalPadding)
        .background(style.fill, in: RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous))
        .contentShape(Rectangle())
    }
}
