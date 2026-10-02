import SwiftUI

/// Full-screen themed background (the mockups' near-black radial). Apply at each
/// screen root behind a `NavigationStack` content view.
/// The ONE screen-title style (device round 4, build 48: "every screen should
/// have the word at the top be the same size" — they were 30/26/34/34).
/// 30pt bold; each root tab renders it in its own custom header row.
struct ScreenTitle: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.system(size: 30, weight: .bold))
            .foregroundStyle(Color.skText)
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
            // lineLimit + fixedSize: in the iPad's narrower list column
            // "Transcribing" was breaking MID-WORD across two lines inside the
            // capsule (2026-07-23 shot). A status chip never wraps.
            Text(label).lineLimit(1)
        }
        .font(.system(size: 10.5, weight: .bold))
        .foregroundStyle(style.fg)
        .padding(.horizontal, 9)
        .padding(.vertical, 3)
        .background(style.bg, in: .capsule)
        .fixedSize(horizontal: true, vertical: false)
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
    /// Optional focus binding (⌘F on the Notes list moves focus into the field).
    var focus: FocusState<Bool>.Binding? = nil

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 14)).foregroundStyle(Color.skTextFaint)
            field
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Color.skTextFaint) }
                    .accessibilityLabel(SharedCopy.clearSearchLabel)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(Color.skSurface, in: .rect(cornerRadius: Theme.Radius.field, style: .continuous))
        .overlay(RoundedRectangle.sk(Theme.Radius.field).stroke(Color.skBorder, lineWidth: 1))
    }

    @ViewBuilder private var field: some View {
        let tf = TextField("", text: $text, prompt: Text(prompt).foregroundStyle(Color.skTextFaint))
            .font(.system(size: 14)).foregroundStyle(Color.skText).tint(.skAccent)
            .autocorrectionDisabled()
            .accessibilityIdentifier(fieldID)
        if let focus { tf.focused(focus) } else { tf }
    }
}

enum TagChipStyle { case applied, suggestion, add }

/// `UIActivityViewController` in SwiftUI clothing: the system share sheet (the one wrapper
/// the memo "Share note…" and the book "Share book…" sheets both present).
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

// MARK: - Book sheet pieces (shared by the audiobook sheets)

/// A capsule progress bar on the border track. `fill` is a parameter (the shelf tile turns
/// green when finished); `minFill` keeps a visible dot at zero progress.
struct ThinProgressBar: View {
    let fraction: Double
    var height: CGFloat = 3
    var fill: Color = .skAccent
    var minFill: CGFloat = 4

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.skBorder)
                Capsule().fill(fill)
                    .frame(width: max(minFill, geo.size.width * fraction))
            }
        }
        .frame(height: height)
    }
}

/// The drawn drag handle at the top of a bottom sheet (the signed mocks draw it; the system
/// indicator is not used). Width and spacing differ a little per sheet, so they are parameters.
struct SheetGrabber: View {
    var width: CGFloat = 36
    var top: CGFloat = 8
    var bottom: CGFloat = 14

    var body: some View {
        Capsule().fill(Color.skBorder).frame(width: width, height: 4)
            .frame(maxWidth: .infinity)
            .padding(.top, top).padding(.bottom, bottom)
    }
}

/// Small-caps label over a rounded text field (book title / author forms).
struct LabeledTextField: View {
    let label: String
    @Binding var text: String
    let id: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .kerning(0.5)
                .foregroundStyle(Color.skTextFaint)
            TextField(label, text: $text)
                .font(.system(size: 14))
                .foregroundStyle(Color.skText)
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(Color.skElev, in: .rect(cornerRadius: Theme.Radius.field, style: .continuous))
                .accessibilityIdentifier(id)
        }
    }
}

/// The outlined Cancel + accent confirm pair at the bottom of a small form sheet.
struct CancelConfirmRow: View {
    let confirmTitle: String
    let cancelID: String
    let confirmID: String
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button("Cancel") { onCancel() }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.skTextDim)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .overlay(RoundedRectangle.sk(11).stroke(Color.skBorder, lineWidth: 1))
                .accessibilityIdentifier(cancelID)

            Button(action: onConfirm) {
                Text(confirmTitle)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(Color.skAccent, in: .rect(cornerRadius: 11, style: .continuous))
            }
            .accessibilityIdentifier(confirmID)
        }
    }
}

extension View {
    /// The floating glass capsule of the mini-player bar and pill: fixed height, thin material,
    /// hairline border, top sheen, drop shadow (`shadow` = blur radius; the offset is half).
    func miniGlass(height: CGFloat, shadow: CGFloat = 16) -> some View {
        self
            .frame(height: height)
            .background(.ultraThinMaterial, in: .capsule)
            .overlay(Capsule().strokeBorder(Color.skBorder, lineWidth: 0.5))
            .overlay(
                Capsule()
                    .fill(LinearGradient(colors: [.white.opacity(0.09), .clear],
                                         startPoint: .top, endPoint: .center))
                    .allowsHitTesting(false)
            )
            .shadow(color: .black.opacity(0.45), radius: shadow, y: shadow / 2)
    }
}

/// Scaffold for the two book-transfer sheets (share out, import in): drag handle, cover +
/// title + subtitle header, the caller's phase content, an optional amber failure line. The
/// cover view and the detent height stay parameters.
struct BookTransferSheet<Cover: View, Content: View>: View {
    let id: String
    let detent: CGFloat
    let title: String
    let subtitle: String
    let failure: String?
    @ViewBuilder var cover: () -> Cover
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            SheetGrabber(width: 34)

            HStack(spacing: 12) {
                cover()
                    .frame(width: 58, height: 58)
                    .clipShape(RoundedRectangle.sk(8))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(Color.skText)
                        .lineLimit(2)
                    Text(subtitle)
                        .font(.system(size: 12)).foregroundStyle(Color.skTextDim)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }

            content()

            if let failure {
                Text(failure)
                    .font(.system(size: 12)).foregroundStyle(Color.skAmber)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 10)
            }
        }
        .padding(16)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color.skSurface.ignoresSafeArea())
        .presentationDetents([.height(detent)])
        .accessibilityIdentifier(id)
    }
}
