import SwiftUI

// THE note-header importance control (Q85, signed mock `Q75-note-header-final.html`,
// behaviour A — Tuur 2026-09-30: "tap is good, not drag"). One pill replaces the
// importance card: three mini balls + the tier word. Each tap steps Not rated →
// Passing → Useful → Important → Not rated (un-rating allowed, C88), and a toast
// names the step. ONE shared view for the phone, iPad and Mac (C115); each app
// supplies only a `NoteRatingPillStyle` — the view never branches on platform.

struct NoteRatingPillStyle {
    var accent: Color
    var accentText: Color
    var accentSoft: Color
    /// Fill of the un-rated pill.
    var surface: Color
    /// Hairline around the un-rated pill.
    var border: Color
    /// Unlit ball ring.
    var ring: Color
    var textDim: Color
    /// 26 pt on the phone/iPad, 22 pt on the Mac.
    var height: CGFloat
    var fontSize: CGFloat
    /// The touch target is taller than the pill on the phone (44 pt).
    var hitHeight: CGFloat
    var animation: Animation
}

/// One toast line for the host to render at screen level (like the tag Undo pill).
struct RatingToast: Identifiable, Equatable {
    let id = UUID()
    let text: String
}

struct NoteRatingPill: View {
    /// nil = never rated (the phone stores 0 and adapts at the call site).
    @Binding var value: Double?
    var style: NoteRatingPillStyle
    /// The Mac dims the pill until a note is processed.
    var enabled: Bool = true
    var onTap: () -> Void = {}
    /// Fires after the value is written — the phone's save + wall print.
    var onCommit: () -> Void = {}
    var onToast: (RatingToast) -> Void = { _ in }

    private var lit: Int { ThreeBallScale.step(for: value) }
    private var hitPad: CGFloat { max(0, (style.hitHeight - style.height) / 2) }

    var body: some View {
        Button {
            let from = lit
            onTap()
            let next = ThreeBallScale.stepped(value)
            withAnimation(style.animation) { value = next }
            onCommit()
            onToast(RatingToast(text: ThreeBallScale.toastCopy(from: from, to: ThreeBallScale.step(for: next))))
        } label: {
            HStack(spacing: 6) {
                HStack(spacing: 3) {
                    ForEach(1...ThreeBallScale.stepCount, id: \.self) { i in
                        Circle()
                            .fill(i <= lit ? style.accent : .clear)
                            .overlay(Circle().strokeBorder(i <= lit ? style.accent : style.ring, lineWidth: 1.2))
                            .frame(width: 8, height: 8)
                    }
                }
                Text(ThreeBallScale.label(forStep: lit))
                    .font(.system(size: style.fontSize, weight: lit == 0 ? .medium : .semibold))
                    .foregroundStyle(lit == 0 ? style.textDim : style.accentText)
                    .lineLimit(1)
            }
            .padding(.leading, 8).padding(.trailing, 10)
            .frame(height: style.height)
            .background(lit == 0 ? style.surface : style.accentSoft, in: .capsule)
            .overlay(lit == 0 ? Capsule().strokeBorder(style.border, lineWidth: 1) : nil)
            // Taller touch target, layout-neutral.
            .padding(.vertical, hitPad)
            .contentShape(Rectangle())
            .padding(.vertical, -hitPad)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.5)
        .fixedSize()
        .animation(style.animation, value: lit)
        .accessibilityIdentifier("rating-pill")
        .accessibilityLabel("Importance: \(ThreeBallScale.label(forStep: lit))")
        .accessibilityHint("Tap to change")
    }
}

/// The toast a host draws at screen level for a `RatingToast`; the caller clears
/// it after ~1.6 s (mock).
struct RatingToastView: View {
    let toast: RatingToast

    var body: some View {
        Text(toast.text)
            .font(.system(size: 13))
            .foregroundStyle(.white)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(Color.black.opacity(0.85), in: .capsule)
            .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
            .fixedSize()
            .accessibilityIdentifier("rating-toast")
    }
}

/// The header's pill row: the pill, and beside it the orange fading line when the
/// note is unrated. Both apps' headers place this identically.
struct NoteRatingRow: View {
    @Binding var value: Double?
    var style: NoteRatingPillStyle
    var enabled: Bool = true
    /// nil = no line (rated, held, trashed, still transcribing).
    var fadingLine: String?
    var lineFont: CGFloat = 11.5
    var lineColor: Color
    var onTap: () -> Void = {}
    var onCommit: () -> Void = {}
    var onToast: (RatingToast) -> Void = { _ in }

    var body: some View {
        HStack(spacing: 9) {
            NoteRatingPill(value: $value, style: style, enabled: enabled,
                           onTap: onTap, onCommit: onCommit, onToast: onToast)
            if let fadingLine {
                Text(fadingLine)
                    .font(.system(size: lineFont))
                    .foregroundStyle(lineColor)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("detail-lifecycle-line")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
