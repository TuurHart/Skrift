import SwiftUI

/// THE notes-list card — m2 of `mocks/mac-notes-list-rich.html`, signed off 2026-08-18
/// ("m2 looks best, build that. make sure the ipad also follows that one to the T").
/// ONE view carries the layout rules; each app maps its model into `NoteCardModel`
/// and its theme into `NoteCardStyle` (the `SignificanceCirclesView` cure — the two
/// hand-built row implementations drifted for a month before this).
///
/// The card's rows, top to bottom (all optional parts collapse):
///   stamp line   — "Sun · 19:49" + fading/quiet line + status pill (per-app POLICY:
///                  the Mac always shows its pipeline state — its dashboard; the iPad
///                  sends a pill only for in-flight/error, per the locked
///                  always-on-badge-is-no-signal doctrine. The VIEW just renders
///                  what the model carries.)
///   title        — one line, semibold; locked notes render 🔒 + title and NOTHING else
///   quote        — audiobook idiom (accent bar, italic) when the note leads with one
///   snippet      — up to 2 lines, dim
///   chips        — duration · place · book · #tags
///   thumb        — 44pt, trailing, only when the note visibly carries a photo
struct NoteCardModel {
    var stamp: String
    /// Amber urgency line after the stamp ("starts fading 14 Sep") — nil when calm.
    var fadingLine: String?
    /// Faint spine line for quiet (unrated) rows; the pill outranks it in the slot.
    var quietLine: String?
    var statusPill: Pill?
    var title: String?
    /// Audiobook-capture lead quote (already stripped of "> ").
    var quote: String?
    var snippet: String?
    var chips: [Chip] = []
    var thumb: Image?
    var locked = false
    /// Unrated = dimmed, hollow — untriaged, not urgent.
    var quiet = false
    var selected = false
    /// Display-only three-ball importance (Q26, one-notes-list D135): 0–3 lit
    /// balls in the stamp line, nil to omit entirely (locked rows). NEVER
    /// tappable here — rating happens in detail, via `ThreeBallImportanceView`.
    var balls: Int?

    struct Pill: Equatable {
        var label: String
        var kind: Kind
        var pulses = false
        enum Kind { case progress, done, error, amber }
    }
    struct Chip: Equatable {
        var text: String
        var systemImage: String?
        var isTag = false
    }
}

/// Per-app colors — construct from each app's theme, never inline color literals
/// in the view (the SignificanceStyle pattern).
struct NoteCardStyle {
    var accent: Color
    var accentSoft: Color
    var accentText: Color
    var text: Color
    var textDim: Color
    var textFaint: Color
    var amber: Color
    var green: Color
    var red: Color
    var chipFill: Color
    var surface: Color
    var border: Color
}

struct NoteCardView: View {
    let model: NoteCardModel
    let style: NoteCardStyle

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                stampLine
                if model.locked {
                    lockedTitle
                } else {
                    if let title = model.title, !title.isEmpty { titleLine(title) }
                    if let quote = model.quote, !quote.isEmpty { quoteLine(quote) }
                    if let snippet = model.snippet, !snippet.isEmpty { snippetLines(snippet) }
                    if !model.chips.isEmpty { chipsRow }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let thumb = model.thumb, !model.locked {
                thumb
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .padding(.top, 14)
            }
        }
        .padding(10)
        .background(
            model.selected ? style.accentSoft : style.surface,
            in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(model.selected ? style.accent.opacity(0.55) : style.border, lineWidth: 1))
        .opacity(model.quiet ? 0.62 : 1)
    }

    private var stampLine: some View {
        HStack(spacing: 6) {
            Text(model.stamp)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(style.textFaint)
                .lineLimit(1).fixedSize()
            if let fading = model.fadingLine {
                Text("· \(fading)")
                    .font(.system(size: 10.5))
                    .foregroundStyle(style.amber.opacity(0.9))
                    .lineLimit(1)
            } else if let quiet = model.quietLine, model.statusPill == nil {
                Text("· \(quiet)")
                    .font(.system(size: 10.5))
                    .foregroundStyle(style.textFaint)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if let pill = model.statusPill { pillView(pill) }
            if let balls = model.balls { ballsView(balls) }
        }
    }

    /// Display-only three-ball importance readout (mocks/one-notes-list.html
    /// `.rb` — 7pt circles, hollow ring when unlit). Never a `Button`: rating a
    /// note from the list is not a verb this row offers (D137's "intentional
    /// choice" doctrine applies to the whole control, not just the bulk one).
    private func ballsView(_ lit: Int) -> some View {
        HStack(spacing: 3) {
            ForEach(1...3, id: \.self) { i in
                Circle()
                    .fill(i <= lit ? style.accent : .clear)
                    .overlay(Circle().strokeBorder(i <= lit ? style.accent : style.border, lineWidth: 1.2))
                    .frame(width: 7, height: 7)
            }
        }
        .accessibilityIdentifier("card-importance-balls")
        .accessibilityLabel(lit == 0 ? "Unrated" : "Importance \(lit) of 3")
    }

    private func pillView(_ pill: NoteCardModel.Pill) -> some View {
        let color: Color = switch pill.kind {
        case .progress: style.accentText
        case .done: style.green
        case .error: style.red
        case .amber: style.amber
        }
        return Text(pill.label)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(color.opacity(0.12), in: Capsule())
            .fixedSize()
    }

    private var lockedTitle: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(style.textDim)
            Text(model.title?.isEmpty == false ? model.title! : "Locked note")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(style.text)
                .lineLimit(1)
        }
        .padding(.top, 1)
    }

    private func titleLine(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(style.text)
            .lineLimit(1)
            .padding(.top, 1)
    }

    private func quoteLine(_ quote: String) -> some View {
        // The shared-input idiom (locked 2026-07-12): accent bar + italic, no bubble.
        HStack(alignment: .top, spacing: 8) {
            RoundedRectangle(cornerRadius: 1.5).fill(style.accent).frame(width: 3)
            Text(quote)
                .font(.system(size: 11.5))
                .italic()
                .foregroundStyle(style.textDim)
                .lineLimit(2)
        }
        .padding(.top, 1)
    }

    private func snippetLines(_ snippet: String) -> some View {
        Text(snippet)
            .font(.system(size: 11.5))
            .foregroundStyle(style.textDim)
            .lineLimit(2)
            .padding(.top, 1)
    }

    private var chipsRow: some View {
        HStack(spacing: 4) {
            ForEach(Array(model.chips.enumerated()), id: \.offset) { _, chip in
                HStack(spacing: 3) {
                    if let symbol = chip.systemImage {
                        Image(systemName: symbol).font(.system(size: 8.5))
                    }
                    Text(chip.text).font(.system(size: 10))
                }
                .foregroundStyle(chip.isTag ? style.accentText : style.textDim)
                .padding(.horizontal, 7).padding(.vertical, 2)
                .background(chip.isTag ? style.accentSoft : style.chipFill, in: Capsule())
                .lineLimit(1).fixedSize()
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 4)
    }
}
