import SwiftUI

/// THE destination control (D204, Q395): a tap pill that works like the rating pill (`NoteRatingPill`).
/// One tap flips Personal ⇄ Portfolio in place. No dropdown, no menu, no sheet, no expanding row:
/// the pill never changes size while you choose, so nothing around it re-lays out. ONE view for
/// the Mac, the iPad and the phone (each app maps its theme into `DestinationRowStyle`, the
/// `NoteCardView` / `NoteRatingPillStyle` seam), drawn in the header row beside the rating pill
/// (`NoteRatingRow`'s trailing slot, Q386).
///
/// The two states are DELIBERATELY UNEQUAL in colour: Personal is a quiet accent pill (nothing is
/// leaving, so nothing is said); Portfolio is the amber pill (this note goes to a repo an AI
/// reads). The colour split carries the privacy boundary, so a glance answers "which side of the
/// line is this note on". The folder Portfolio writes to (`_inbox/`) is spoken to VoiceOver and
/// shown as the Mac tooltip, not drawn: a folder label appearing on the tap would move the row.
///
/// Portfolio adds no tag (D205). idea / inspiration / project are plain tags, offered as quiet
/// suggestions by `TagEditorRow(presets:)` (`PortfolioTagPresets.suggestions`) while the note is
/// Portfolio and has none of them.
struct DestinationRowStyle {
    /// The private family (`.personal`) — the app accent.
    var accent: Color
    var accentSoft: Color
    var accentText: Color
    /// The portfolio family (`.portfolio`) — the amber token.
    var portfolio: Color
    var portfolioSoft: Color
    /// The pill's 1 pt ring. The Q350 note mock has a flat tinted pill (no ring), so the phone
    /// turns it off; the Mac keeps its look until Q360 decides.
    var chipOutlined: Bool = true
    /// Pill height: 26 pt on the phone/iPad (level with the rating pill, Q382), 22 pt on the Mac.
    var chipHeight: CGFloat = 22
    /// Touch target height, layout-neutral (44 pt on the phone, same as `NoteRatingPillStyle`).
    var chipHitHeight: CGFloat = 22
    var chipFontSize: CGFloat = 11.5
    var chipSidePadding: CGFloat = 9
}

struct DestinationRowView: View {
    @Binding var destination: NoteDestination
    /// Called only when the value actually CHANGES — callers persist + `markEdited` here.
    var onPick: (NoteDestination) -> Void
    var style: DestinationRowStyle

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var hitPad: CGFloat { max(0, (style.chipHitHeight - style.chipHeight) / 2) }
    private var hue: Color { destination.isPortfolio ? style.portfolio : style.accent }

    var body: some View {
        Button {
            withAnimation(reduceMotion ? nil : SkMotion.snappy) {
                NoteDestination.tapped(&destination, onPick: onPick)
            }
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(hue)
                    .frame(width: 6, height: 6)
                Text(destination.label)
                    .font(.system(size: style.chipFontSize, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(destination.isPortfolio ? style.portfolio : style.accentText)
            .padding(.horizontal, style.chipSidePadding)
            .frame(height: style.chipHeight)
            .background(destination.isPortfolio ? style.portfolioSoft : style.accentSoft, in: .capsule)
            .overlay {
                if style.chipOutlined {
                    Capsule().strokeBorder(hue.opacity(0.35), lineWidth: 1)
                }
            }
            // Taller touch target, layout-neutral (the rating pill's trick).
            .padding(.vertical, hitPad)
            .contentShape(Rectangle())
            .padding(.vertical, -hitPad)
        }
        .buttonStyle(.plain)
        .fixedSize()
        .animation(reduceMotion ? nil : SkMotion.snappy, value: destination)
        .accessibilityIdentifier("destination-pill")
        .accessibilityLabel("Destination: \(destination.label)")
        .accessibilityValue(destination.portfolioFolder.map { "Exports to \($0)/" } ?? "Exports to your vault")
        .accessibilityHint("Tap to switch to \(destination.toggled.label)")
        .help("Tap to switch to \(destination.toggled.label)")
    }
}
