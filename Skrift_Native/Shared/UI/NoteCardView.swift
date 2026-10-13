import SwiftUI

/// THE notes-list row — the "Skrift new" frames of `mocks/Q349-notes-list-apple.html`, signed
/// 2026-10-13 with D194's picks (D190 / D193: the list reads like Apple Notes). ONE view carries
/// the layout rules; each app maps its model into `NoteCardModel` and its theme + sizes into
/// `NoteCardStyle` (the `SignificanceCirclesView` cure — two hand-built rows drifted for a month).
///
/// The row, top to bottom (all optional parts collapse):
///   line 1 — the title, bold, one line (🔒 + title only on a locked note); trailing: a status
///            pill ONLY while something is happening (Transcribing, error, 2 versions), then the
///            grey "Unrated" marker on an unrated note (where the importance balls used to sit;
///            a rated note shows nothing there — D194)
///   line 2 — the date (`MemoDate.listDate`, primary colour) + the first line, dim; a book
///            quote keeps its accent bar + italics here
///   line 3 — "Portfolio" (Personal shows nothing), the amber fading line, and at the right
///            end the media marker (mic + length, book + chapter, link + domain)
///   thumb  — 52 pt phone / 40 pt Mac, trailing, centred, only when the note carries a photo
/// Rows sit in ONE card per group with hairlines between them (`position`), not a card each.
struct NoteCardModel {
    /// Line 2's date. The adapters fill it with `MemoDate.listDate` (D190).
    var stamp: String
    /// Amber urgency line ("starts fading 14 Sep") — nil when calm. Line 3.
    var fadingLine: String?
    /// The Mac's honest waiting line on a stranded rated memo. Line 3, faint.
    var quietLine: String?
    var statusPill: Pill?
    var title: String?
    /// Audiobook-capture lead quote (already stripped of "> ").
    var quote: String?
    var snippet: String?
    /// The shared builder's chips. The row no longer draws them (D194: tags, place and weather
    /// leave the row); `media` carries the one marker that stays. Kept on the model because
    /// both apps' card-content parity tests compare them.
    var chips: [Chip] = []
    var thumb: Image?
    var locked = false
    /// Unrated row (the Mac's quiet rows). No longer dims the row (D194).
    var quiet = false
    var selected = false
    /// Importance, 0–3, nil for locked rows (Q26). The row shows NO importance (D194); 0 is read
    /// as "unrated" and draws the grey Unrated marker. NEVER tappable — rating lives in detail.
    var balls: Int?
    /// Line 3's right end: mic + length, book + chapter, link + domain (`NoteCardBuilder.media`).
    var media: Chip?
    /// The note goes to the Portfolio (D189). Line 3 says so; Personal shows nothing (D194).
    var portfolio = false
    /// Where this row sits in its group's one card.
    var position: GroupPosition = .only

    enum GroupPosition: Equatable { case only, first, middle, last
        static func of(index: Int, count: Int) -> GroupPosition {
            if count <= 1 { return .only }
            if index == 0 { return .first }
            return index == count - 1 ? .last : .middle
        }
        var roundsTop: Bool { self == .only || self == .first }
        var roundsBottom: Bool { self == .only || self == .last }
    }

    /// D194: an unrated note shows a small grey dot + "Unrated" in importance's old spot.
    var showsUnrated: Bool { !locked && balls == 0 }

    struct Pill: Equatable {
        var label: String
        var kind: Kind
        var pulses = false
        /// Optional leading glyph (the conflict pill's fork, Q4 mock).
        var systemImage: String? = nil
        enum Kind { case progress, done, error, amber }
        /// C98/D139: the note has two versions waiting for a pick. Amber, a fork glyph, no
        /// pulse — it waits for him. Same slot as Transcribing; it outranks every other pill.
        static let twoVersions = Pill(label: "2 versions", kind: .amber, systemImage: "arrow.triangle.branch")
    }
    struct Chip: Equatable {
        var text: String
        var systemImage: String?
        var isTag = false
    }

    /// C115 shared tag-chip builder — the ONE way a note's tags become chips, so
    /// the phone and the Mac card models can't drift again (Q65 found the Mac
    /// list carrying a tagged note's duration/source chips but never its
    /// `#tags`; Q68 fixes it by routing BOTH card models through this).
    static func tagChips(for tags: [String]) -> [Chip] {
        tags.map { Chip(text: "#\($0)", isTag: true) }
    }
}

/// Per-app colours and sizes — construct from each app's theme, never inline literals in the
/// view (the SignificanceStyle pattern). Sizes default to the phone's (Q349: 16 / 14 / 12.5);
/// the Mac passes its own (14 / 12.5 / 11.5).
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
    var titleSize: CGFloat = 16
    var lineSize: CGFloat = 14
    var folderSize: CGFloat = 12.5
    var thumbSize: CGFloat = 52
    var thumbRadius: CGFloat = 7
    var spacing: CGFloat = 12
    var padding = EdgeInsets(top: 11, leading: 16, bottom: 11, trailing: 14)
    var cornerRadius: CGFloat = 12
}

struct NoteCardView: View {
    let model: NoteCardModel
    let style: NoteCardStyle

    var body: some View {
        HStack(alignment: .center, spacing: style.spacing) {
            VStack(alignment: .leading, spacing: 2) {
                lineOne
                if !model.locked { lineTwo }
                lineThree
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let thumb = model.thumb, !model.locked {
                thumb
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: style.thumbSize, height: style.thumbSize)
                    .clipShape(RoundedRectangle(cornerRadius: style.thumbRadius, style: .continuous))
            }
        }
        .padding(style.padding)
        .background(model.selected ? style.accentSoft : style.surface, in: shape)
        // One card per group: the group's outer edge, drawn piecewise so no line runs between rows.
        .overlay(GroupEdge(position: model.position, radius: style.cornerRadius)
            .stroke(style.border, lineWidth: 1))
        // The hairline between rows, from the text's leading edge to the card's trailing edge.
        .overlay(alignment: .top) {
            if !model.position.roundsTop {
                Rectangle().fill(style.border).frame(height: 1).padding(.leading, style.padding.leading)
            }
        }
        .contentShape(shape)
    }

    private var shape: UnevenRoundedRectangle {
        let top = model.position.roundsTop ? style.cornerRadius : 0
        let bottom = model.position.roundsBottom ? style.cornerRadius : 0
        return UnevenRoundedRectangle(topLeadingRadius: top, bottomLeadingRadius: bottom,
                                      bottomTrailingRadius: bottom, topTrailingRadius: top, style: .continuous)
    }

    // MARK: Line 1 — title, pill, Unrated

    private var lineOne: some View {
        HStack(spacing: 6) {
            if model.locked {
                Image(systemName: "lock.fill")
                    .font(.system(size: style.titleSize * 0.72, weight: .semibold))
                    .foregroundStyle(style.textDim)
            }
            Text(text.title)
                .font(.system(size: style.titleSize, weight: .semibold))
                .foregroundStyle(style.text)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let pill = model.statusPill { pillView(pill) }
            if model.showsUnrated { unratedMarker }
        }
    }

    /// D194: rating and importance share the same place; a rated note shows nothing here.
    private var unratedMarker: some View {
        HStack(spacing: 4) {
            Circle().fill(style.textFaint).frame(width: 6, height: 6)
            Text("Unrated")
        }
        .font(.system(size: style.folderSize))
        .foregroundStyle(style.textFaint)
        .fixedSize()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("card-unrated")
    }

    private func pillView(_ pill: NoteCardModel.Pill) -> some View {
        let color: Color = switch pill.kind {
        case .progress: style.accentText
        case .done: style.green
        case .error: style.red
        case .amber: style.amber
        }
        return HStack(spacing: 3) {
            if let glyph = pill.systemImage { Image(systemName: glyph).font(.system(size: 9, weight: .semibold)) }
            Text(pill.label)
        }
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(color.opacity(0.12), in: Capsule())
            .fixedSize()
    }

    // MARK: Line 2 — date + first line (or the quote)

    private var text: NoteRowText.Lines {
        if model.locked {
            return .init(title: model.title?.isEmpty == false ? model.title! : SharedCopy.lockedTitleFallback, line: nil)
        }
        return NoteRowText.lines(title: model.title, snippet: model.snippet,
                                 busy: model.statusPill?.kind == .progress ? model.statusPill?.label : nil)
    }

    private var lineTwo: some View {
        HStack(spacing: 6) {
            Text(model.stamp)
                .foregroundStyle(style.text)
                .monospacedDigit()
                .fixedSize()
            if let quote = model.quote, !quote.isEmpty {
                // The shared-input idiom (locked 2026-07-12): accent bar + italic, no bubble.
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 1).fill(style.accent)
                        .frame(width: 2.5, height: style.lineSize * 0.95)
                    Text(quote).italic().foregroundStyle(style.textDim).lineLimit(1)
                }
            } else if let busy = text.busy {
                Text(busy).foregroundStyle(style.accentText).lineLimit(1)
            } else if let line = text.line {
                Text(line).foregroundStyle(style.textDim).lineLimit(1)
            }
        }
        .font(.system(size: style.lineSize))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Line 3 — Portfolio, fading, media

    @ViewBuilder private var lineThree: some View {
        let showsFolder = model.portfolio && !model.locked
        let clock = model.locked ? nil : (model.fadingLine ?? model.quietLine)
        let media = model.locked ? nil : model.media
        if showsFolder || clock != nil || media != nil {
            HStack(spacing: 5) {
                if showsFolder {
                    Circle().fill(style.amber).frame(width: 6, height: 6)
                    Text(NoteDestination.portfolio.label).foregroundStyle(style.amber)
                }
                if let clock {
                    Text(showsFolder ? "· \(clock)" : clock)
                        .foregroundStyle(model.fadingLine != nil ? style.amber : style.textFaint)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                if let media {
                    HStack(spacing: 4) {
                        if let glyph = media.systemImage {
                            Image(systemName: glyph).font(.system(size: style.folderSize * 0.85))
                        }
                        Text(media.text).lineLimit(1).monospacedDigit()
                    }
                    .foregroundStyle(style.textFaint)
                    .layoutPriority(-1)
                }
            }
            .font(.system(size: style.folderSize))
            .padding(.top, 1)
        }
    }
}

/// The outer edge of one row's slice of its group card: the full rounded rect for a lone row,
/// open at the bottom for the first, open at the top for the last, two sides in between — so
/// the group reads as one bordered card and no line runs across the card between rows.
private struct GroupEdge: Shape {
    let position: NoteCardModel.GroupPosition
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: 0.5, dy: 0.5)
        let rad = min(radius, r.height / 2, r.width / 2)
        var p = Path()
        switch position {
        case .only:
            p.addRoundedRect(in: r, cornerSize: CGSize(width: rad, height: rad), style: .continuous)
        case .first:
            p.move(to: CGPoint(x: r.minX, y: rect.maxY))
            p.addLine(to: CGPoint(x: r.minX, y: r.minY + rad))
            p.addArc(tangent1End: CGPoint(x: r.minX, y: r.minY), tangent2End: CGPoint(x: r.minX + rad, y: r.minY), radius: rad)
            p.addLine(to: CGPoint(x: r.maxX - rad, y: r.minY))
            p.addArc(tangent1End: CGPoint(x: r.maxX, y: r.minY), tangent2End: CGPoint(x: r.maxX, y: r.minY + rad), radius: rad)
            p.addLine(to: CGPoint(x: r.maxX, y: rect.maxY))
        case .middle:
            p.move(to: CGPoint(x: r.minX, y: rect.minY)); p.addLine(to: CGPoint(x: r.minX, y: rect.maxY))
            p.move(to: CGPoint(x: r.maxX, y: rect.minY)); p.addLine(to: CGPoint(x: r.maxX, y: rect.maxY))
        case .last:
            p.move(to: CGPoint(x: r.minX, y: rect.minY))
            p.addLine(to: CGPoint(x: r.minX, y: r.maxY - rad))
            p.addArc(tangent1End: CGPoint(x: r.minX, y: r.maxY), tangent2End: CGPoint(x: r.minX + rad, y: r.maxY), radius: rad)
            p.addLine(to: CGPoint(x: r.maxX - rad, y: r.maxY))
            p.addArc(tangent1End: CGPoint(x: r.maxX, y: r.maxY), tangent2End: CGPoint(x: r.maxX, y: r.maxY - rad), radius: rad)
            p.addLine(to: CGPoint(x: r.maxX, y: rect.minY))
        }
        return p
    }
}
