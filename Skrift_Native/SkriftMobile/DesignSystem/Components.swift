import SwiftUI

/// Full-screen themed background (the mockups' near-black radial). Apply at each
/// screen root behind a `NavigationStack` content view.
struct SkScreenBackground: View {
    var body: some View {
        Color.skBg.ignoresSafeArea()
    }
}

extension View {
    /// Surface card: bg + hairline border + continuous 16-corner + padding.
    func skCard(padding: CGFloat = Theme.Space.cardPadding) -> some View {
        self
            .padding(padding)
            .background(Color.skSurface, in: .rect(cornerRadius: Theme.Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle.sk(Theme.Radius.card).stroke(Color.skBorder, lineWidth: 1)
            )
    }
}

/// Uppercase section label (`TITLE`, `TRANSCRIPT`, `TAGS`, `CONTEXT`, `ON YOUR NETWORK`).
struct SectionLabel: View {
    let text: String
    var trailing: String?

    init(_ text: String, trailing: String? = nil) {
        self.text = text
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: 5) {
            Text(text)
            if let trailing {
                Text(trailing).foregroundStyle(Color.skTextFaint)
            }
        }
        .font(.system(size: 11.5, weight: .bold))
        .kerning(0.5)
        .foregroundStyle(Color.skTextDim)
    }
}

// MARK: - Status pill

enum PillStyle {
    case synced, waiting, working, error

    var fg: Color {
        switch self {
        case .synced: return .skGreen
        case .waiting: return .skTextDim
        case .working: return .skAmber
        case .error: return .skRed
        }
    }

    var bg: Color {
        switch self {
        case .synced: return Color.skGreen.opacity(0.13)
        case .waiting: return Color.white.opacity(0.06)
        case .working: return Color.skAmber.opacity(0.14)
        case .error: return Color.skRed.opacity(0.14)
        }
    }
}

/// Honest status chip (Synced / Waiting / Transcribing / Retry). `working` pulses;
/// `error` shows a retry affordance when given an action.
struct StatusPill: View {
    let style: PillStyle
    let label: String
    var systemImage: String?

    var body: some View {
        HStack(spacing: 4) {
            if style == .working {
                Circle()
                    .fill(Color.skAmber)
                    .frame(width: 7, height: 7)
                    .shadow(color: .skAmber, radius: 4)
                    .symbolEffectPulseFallback()
            } else if let systemImage {
                Image(systemName: systemImage).font(.system(size: 10, weight: .bold))
            }
            Text(label)
        }
        .font(.system(size: 10.5, weight: .bold))
        .foregroundStyle(style.fg)
        .padding(.horizontal, 9)
        .padding(.vertical, 3)
        .background(style.bg, in: .capsule)
    }
}

private extension View {
    /// `.symbolEffect(.pulse)` only applies to symbols; for the plain dot we just
    /// breathe the opacity so "transcribing" reads as alive.
    @ViewBuilder func symbolEffectPulseFallback() -> some View {
        self.modifier(PulseOpacity())
    }
}

private struct PulseOpacity: ViewModifier {
    @State private var on = false
    func body(content: Content) -> some View {
        content
            .opacity(on ? 0.45 : 1)
            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: on)
            .onAppear { on = true }
    }
}

// MARK: - Chips

/// Context chip (duration, 📍 place, ⛅ temp, day period). Quiet elev background.
struct ContextChip: View {
    let text: String
    var systemImage: String?

    var body: some View {
        HStack(spacing: 3) {
            if let systemImage {
                Image(systemName: systemImage).font(.system(size: 10))
            }
            Text(text).lineLimit(1).truncationMode(.tail)
        }
        .font(.system(size: 11))
        .foregroundStyle(Color.skTextDim)
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(Color.skElev, in: .rect(cornerRadius: 7, style: .continuous))
    }
}

/// Rounded search field used by the memos + names lists. The id sits on the
/// `TextField` so XCUITest can type into it.
struct SearchField: View {
    @Binding var text: String
    var prompt: String = "Search"
    var fieldID: String = "search-field"

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 14)).foregroundStyle(Color.skTextFaint)
            TextField("", text: $text, prompt: Text(prompt).foregroundStyle(Color.skTextFaint))
                .font(.system(size: 14)).foregroundStyle(Color.skText).tint(.skAccent)
                .autocorrectionDisabled()
                .accessibilityIdentifier(fieldID)
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Color.skTextFaint) }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(Color.skSurface, in: .rect(cornerRadius: Theme.Radius.field, style: .continuous))
        .overlay(RoundedRectangle.sk(Theme.Radius.field).stroke(Color.skBorder, lineWidth: 1))
    }
}

enum TagChipStyle { case applied, suggestion, add }

/// A `#tag` chip: applied (filled accent), suggestion (dashed outline), or the
/// `+ Add tag` affordance.
struct TagChip: View {
    let label: String
    let style: TagChipStyle

    var body: some View {
        Text(label)
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundStyle(fg)
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .background(background)
            .overlay(overlay)
    }

    private var fg: Color {
        switch style {
        case .applied: return .white
        case .suggestion: return Color(hex: 0xb9acff)
        case .add: return .skTextDim
        }
    }

    @ViewBuilder private var background: some View {
        switch style {
        case .applied: Capsule().fill(Color.skAccent)
        case .suggestion: Capsule().fill(Color.clear)
        case .add: Capsule().fill(Color.skElev)
        }
    }

    @ViewBuilder private var overlay: some View {
        switch style {
        case .applied:
            EmptyView()
        case .suggestion:
            Capsule().strokeBorder(Color.skAccent.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
        case .add:
            Capsule().strokeBorder(Color.skBorder, lineWidth: 1)
        }
    }
}
