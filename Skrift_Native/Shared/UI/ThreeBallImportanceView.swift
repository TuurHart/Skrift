import SwiftUI

// THE importance control (Q2, signed mock `three-ball-importance.html`) — ONE
// shared view for the Mac, phone and iPad (D107, C240), replacing the 10-circle
// `SignificanceCirclesView`. One row, cumulative fill, the word alone as
// readout (D134): tap a ball to set it, tap the lit one to clear to "Not
// rated". No refine wall, no amber, no flame tag — those left the control
// entirely with the refine pass (D52).
//
// Per `SignificanceCirclesView`'s precedent: each app supplies only a
// `ThreeBallStyle` (colours out of its own Theme + the measurements it owns);
// the view never branches on platform.

/// The per-app half of the control: what to draw it with, never what to draw.
struct ThreeBallStyle {

    // ── Colours (each app maps these from its own Theme) ─────────────────────

    var accent: Color
    var surface: Color
    /// The hairline above the sync line.
    var divider: Color
    /// Border of an unlit ball.
    var ring: Color
    /// The Mac outlines its card; the phone doesn't. nil = no outline.
    var cardStroke: Color?
    /// "Not rated", the sync line's default state.
    var textMuted: Color
    /// The sync sentence.
    var textSecondary: Color
    var green: Color

    // ── Measurements (D107: one size down from the old 10-circle control) ────

    var ballSize: CGFloat
    var gap: CGFloat
    /// The tap/click target, centred on the ball — larger than the glyph on
    /// both apps now (44pt phone/iPad, 20pt Mac; the old Mac control let the
    /// 13pt glyph itself be the target).
    var targetSize: CGFloat
    var cardRadius: CGFloat
    var syncDotSize: CGFloat
    var syncFontSize: CGFloat

    // ── Behaviour ────────────────────────────────────────────────────────────

    /// Pointer hover previews the would-be rating (Mac only).
    var hoverPreview: Bool
    /// `.help()` tooltips — a pointer affordance.
    var tooltips: Bool
    /// Shrink-to-fit on the one-line sync text — a narrow-screen guard.
    var scalesToFit: Bool
    var animation: Animation
}

struct ThreeBallImportanceView: View {
    /// nil = never rated (shows "Not rated"). The phone stores a non-optional 0
    /// and adapts at the call site, same convention as the old control.
    @Binding var value: Double?
    var style: ThreeBallStyle
    /// The Mac dims the control until a note is processed.
    var enabled: Bool = true
    /// Fires on tap, before the value is written — the phone's haptic.
    var onTap: () -> Void = {}
    /// Fires after the value is written — the phone's save.
    var onCommit: () -> Void = {}

    /// Ball under the pointer (drives the hover preview + scale-up, Mac only).
    @State private var hovered: Int?

    private var lit: Int { ThreeBallScale.step(for: value) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            topRow
            Rectangle().fill(style.divider).frame(height: 0.5)
                .padding(.top, 11).padding(.bottom, 9)
            syncLine
        }
        .padding(EdgeInsets(top: 13, leading: 13, bottom: 12, trailing: 13))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(style.surface, in: card)
        .overlay(style.cardStroke.map { card.stroke($0, lineWidth: 1) })
        .opacity(enabled ? 1 : 0.5)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("importance-balls")
    }

    private var card: RoundedRectangle {
        RoundedRectangle(cornerRadius: style.cardRadius, style: .continuous)
    }

    // ── Label row: "Importance" + balls on the left, live value on the right ──

    private var topRow: some View {
        HStack(spacing: 8) {
            HStack(spacing: style.gap) {
                Text("Importance")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(style.textMuted)
                ballsRow
            }
            Spacer(minLength: 8)
            valueLabel
        }
    }

    @ViewBuilder private var valueLabel: some View {
        if !enabled {
            Text("rate after processing")
                .font(.system(size: 11))
                .foregroundStyle(style.textMuted)
        } else if let hovered, style.hoverPreview, hovered != lit {
            Text(ThreeBallScale.name(forStep: hovered))
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(style.textSecondary)
                .accessibilityIdentifier("importance-value")
        } else {
            Text(ThreeBallScale.label(forStep: lit))
                .font(.system(size: 11.5, weight: lit == 0 ? .medium : .semibold))
                .foregroundStyle(lit == 0 ? style.textMuted : style.accent)
                .accessibilityIdentifier("importance-value")
        }
    }

    // ── The balls ─────────────────────────────────────────────────────────────

    private var ballsRow: some View {
        HStack(spacing: max(0, style.gap - (style.targetSize - style.ballSize))) {
            ForEach(1...ThreeBallScale.stepCount, id: \.self) { i in ball(i) }
        }
        .animation(style.animation, value: hovered)
        .animation(style.animation, value: lit)
    }

    private func ball(_ i: Int) -> some View {
        let isLit = i <= lit
        let isPreview = !isLit && hovered.map { i <= $0 } == true

        let fill: Color = isLit ? style.accent : isPreview ? style.accent.opacity(0.3) : .clear
        let border: Color = isLit ? style.accent : isPreview ? style.accent.opacity(0.55) : style.ring

        return Button {
            onTap()
            withAnimation(style.animation) {
                value = ThreeBallScale.toggling(value, tappedStep: i)
            }
            onCommit()
        } label: {
            Circle()
                .fill(fill)
                .overlay(Circle().strokeBorder(border, lineWidth: 1.5))
                .frame(width: style.ballSize, height: style.ballSize)
                .frame(width: style.targetSize, height: style.targetSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .scaleEffect(style.hoverPreview && hovered == i ? 1.22 : 1)
        .animation(.easeOut(duration: 0.1), value: hovered)
        .onHover { inside in
            guard style.hoverPreview, enabled else { return }
            if inside {
                hovered = i
            } else if hovered == i {
                hovered = nil
            }
        }
        .disabled(!enabled)
        .help(style.tooltips ? ThreeBallScale.name(forStep: i) : "")
        .accessibilityIdentifier("importance-ball-\(i)")
        .accessibilityLabel("Importance \(ThreeBallScale.name(forStep: i))")
        .accessibilityAddTraits(isLit ? .isSelected : [])
    }

    // ── What the rating MEANS for processing ─────────────────────────────────

    private var syncLine: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(lit == 0 ? style.textMuted : style.green)
                .frame(width: style.syncDotSize, height: style.syncDotSize)
            Text(ThreeBallScale.syncCopy(forStep: lit))
                .font(.system(size: style.syncFontSize))
                .lineLimit(1)
                .minimumScaleFactor(style.scalesToFit ? 0.85 : 1)
        }
        .foregroundStyle(style.textSecondary)
        .accessibilityIdentifier("importance-sync-line")
    }
}
