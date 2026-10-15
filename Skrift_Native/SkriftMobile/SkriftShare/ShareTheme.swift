import SwiftUI
import UIKit

/// The share sheet's calm look (Q464, mock `mocks/Q455-share-sheet.html`, option A): the app's
/// own grey background filling the system sheet, white cards, Settings-style rows, following the
/// phone's light/dark. Colours come from `Theme` (the shared `Palette`); only the two values the
/// mock adds on top live here.
enum ShareTheme {
    /// Ask the host for more height than any sheet can give; it clamps.
    static let hostHeight: CGFloat = 10_000
    /// The sheet's background: `--sk-bg`.
    static let backgroundUI = UIColor { tc in
        tc.userInterfaceStyle == .dark ? UIColor(red: 0x0f / 255, green: 0x11 / 255, blue: 0x17 / 255, alpha: 1)
                                       : UIColor(red: 0xf5 / 255, green: 0xf5 / 255, blue: 0xf7 / 255, alpha: 1)
    }
    /// Row separators inside a card: `--sk-sep` (rgba 60,60,67,.18 light / 84,84,88,.45 dark).
    static let separator = Color(uiColor: UIColor { tc in
        tc.userInterfaceStyle == .dark ? UIColor(red: 84 / 255, green: 84 / 255, blue: 88 / 255, alpha: 0.45)
                                       : UIColor(red: 60 / 255, green: 60 / 255, blue: 67 / 255, alpha: 0.18)
    })
    /// The nav bar's round buttons: `--sk-glass`.
    static let glass = Color(uiColor: UIColor { tc in
        tc.userInterfaceStyle == .dark ? UIColor(red: 44 / 255, green: 44 / 255, blue: 50 / 255, alpha: 0.78)
                                       : UIColor(white: 1, alpha: 0.78)
    })
    static let cardRadius: CGFloat = 14
}

/// The sheet's nav bar: ✕ (or nothing) on the left, "Skrift" centred, the action on the right.
struct ShareNavBar<Leading: View, Trailing: View>: View {
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        ZStack {
            Text("Skrift")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.skText)
                .accessibilityAddTraits(.isHeader)
            HStack {
                leading()
                Spacer(minLength: 8)
                trailing()
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .padding(.bottom, 8)
        .frame(minHeight: 72)
    }
}

/// A 44 pt nav-bar button: glass (✕, Done), accent (Save) or green (Saved).
struct ShareNavButtonStyle: ButtonStyle {
    enum Kind { case glass, primary, done }
    var kind: Kind = .glass
    var iconOnly = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(kind == .glass ? Color.skText : .white)
            .padding(.horizontal, iconOnly ? 0 : 14)
            .frame(minWidth: 44, minHeight: 44)
            .background(fill, in: .capsule)
            .overlay {
                if kind == .glass { Capsule().strokeBorder(Color.skBorder, lineWidth: 0.5) }
            }
            .shadow(color: kind == .glass ? .black.opacity(0.08) : .clear, radius: 1.5, y: 1)
            .opacity(configuration.isPressed ? 0.7 : 1)
    }

    private var fill: Color {
        switch kind {
        case .glass: return ShareTheme.glass
        case .primary: return .skAccent
        case .done: return .skGreen
        }
    }
}

/// A white card (`--sk-surface`, 14 pt corners) holding rows.
struct ShareCard<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content() }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.skSurface, in: .rect(cornerRadius: ShareTheme.cardRadius, style: .continuous))
            .clipShape(.rect(cornerRadius: ShareTheme.cardRadius, style: .continuous))
    }
}

/// A row separator inset 16 pt from the leading edge.
struct ShareRowSeparator: View {
    var body: some View {
        Rectangle().fill(ShareTheme.separator).frame(height: 0.5).padding(.leading, 16)
    }
}

/// The grey footer under a card (13 pt, `--sk-dim`).
struct ShareFooter: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(Color.skTextDim)
            .lineSpacing(1.5)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
