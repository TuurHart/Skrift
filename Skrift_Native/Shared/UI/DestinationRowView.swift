import SwiftUI

/// THE destination control — signed off 2026-08-26 from `mocks/note-destination-tags.html`,
/// version **B, COLLAPSED**. ONE view for the Mac, the iPad and the phone (each app maps its
/// theme into `DestinationRowStyle`, the `NoteCardView` / `SignificanceCirclesView` seam).
///
/// **Where it lives:** on the note, directly beside the importance circles. The two decisions
/// belong together because they are the same kind of decision — importance says *whether* a
/// note may leave Skrift, destination says *where* — and both are one tap with nothing to open.
/// (Version A put it inside the tag sheet; rejected — it isn't a tag. Version C put tags and
/// destinations in one fuzzy-matched list; rejected outright, because it would land "add the
/// word inspiration" one keystroke from "move this note into the repo an AI reads".)
///
/// **Resting, it is ONE chip: the answer it currently holds.** Tap expands to all four; picking
/// collapses it again. And the two resting states are DELIBERATELY UNEQUAL:
///
/// - `.personal` — a quiet accent chip and nothing else. Nothing is leaving, so nothing is said.
/// - a portfolio destination — the chip in the portfolio colour, plus the folder it writes to.
///   (An "AI READS THIS" line sat here for a day; Tuur cut it 2026-08-27 — the amber chip and
///   the named folder already carry it, and a label that shouts on every portfolio note is the
///   always-on badge this project keeps deciding against.)
///
/// That asymmetry is the point, and it is the same doctrine as the notes list's status pill: an
/// always-on badge is no signal. The warning has to mean something the moment it appears, which
/// it only can if it is absent the rest of the time.
///
/// The colour split carries the boundary itself — one family is private, three are public — so a
/// glance answers "which side of the line is this note on" without reading a word.
struct DestinationRowStyle {
    /// The private family (`.personal`) — the app accent.
    var accent: Color
    var accentSoft: Color
    var accentText: Color
    /// The portfolio family (`.project` / `.idea` / `.inspiration`) — the amber token.
    var portfolio: Color
    var portfolioSoft: Color
    var text: Color
    var textDim: Color
    var textFaint: Color
    var border: Color
    var chipFill: Color
}

struct DestinationRowView: View {
    @Binding var destination: NoteDestination
    /// What to show as the folder for a destination — the app supplies it, because "is a folder
    /// configured on THIS device" is a per-device fact (a destination is a folder bookmark, the
    /// same shape as today's Obsidian picker). `nil` = not set up here yet, so no path is shown.
    var folderLabel: (NoteDestination) -> String?
    /// Called only when the value actually CHANGES — callers persist + `markEdited` here.
    var onPick: (NoteDestination) -> Void

    @State private var expanded: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let style: DestinationRowStyle

    /// `startExpanded` is the snapshot/preview seam — the Mac's `-snapshot-destinations`
    /// harness needs the open state on screen, and `expanded` is private @State. The app
    /// never passes it.
    init(destination: Binding<NoteDestination>,
         folderLabel: @escaping (NoteDestination) -> String?,
         onPick: @escaping (NoteDestination) -> Void,
         style: DestinationRowStyle,
         startExpanded: Bool = false) {
        _destination = destination
        self.folderLabel = folderLabel
        self.onPick = onPick
        self.style = style
        _expanded = State(initialValue: startExpanded)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if expanded {
                VStack(spacing: 7) {
                    familyLabels
                    segments
                }
                .overlay { familyDivider }
            }
            footer
        }
        // A CONTROL, not a banner. Without this the Mac's ~1400pt note column stretched the
        // four segments into full-width slabs with a label floating in the middle of each,
        // and pushed "AI READS THIS" a thousand points away from the chip it describes
        // (caught in `-snapshot-destinations`, not in review). The phone's content width is
        // ~354pt, comfortably under the cap, so nothing changes there — one rule, both apps.
        .frame(maxWidth: 440, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Destination: \(destination.label)")
    }

    // MARK: - Resting

    /// True when there is anything to say about where this note goes — a folder, or the
    /// portfolio notice. `.personal` with no folder has neither, which is the whole point of it.
    private var hasDetail: Bool {
        folderLabel(destination) != nil || destination.isPortfolio
    }

    /// The collapsed chip, and — expanded — the same line restated under the segments, so the
    /// consequence of the pick you are about to make is on screen while you make it.
    ///
    /// Expanded on a `.personal` note the line is EMPTY, so it is dropped entirely rather than
    /// rendered as a lone "→" pointing at nothing (caught on the simulator, not in review).
    @ViewBuilder
    private var footer: some View {
        if expanded && !hasDetail {
            EmptyView()
        } else {
            footerLine
        }
    }

    private var footerLine: some View {
        HStack(spacing: 8) {
            if expanded {
                Text("→").font(.system(size: 11)).foregroundStyle(style.textFaint)
            } else {
                chip
            }
            if let folder = folderLabel(destination) {
                Text(folder)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(destination.isPortfolio ? style.portfolio : style.textDim)
                    .lineLimit(1).truncationMode(.head)
            }
        }
    }

    private var chip: some View {
        Button {
            withAnimation(reduceMotion ? nil : SkMotion.snappy) { expanded = true }
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(destination.isPortfolio ? style.portfolio : style.accent)
                    .frame(width: 6, height: 6)
                Text(destination.label)
                    .font(.system(size: 11.5, weight: .semibold))
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .opacity(0.55)
            }
            .foregroundStyle(destination.isPortfolio ? style.portfolio : style.accentText)
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(destination.isPortfolio ? style.portfolioSoft : style.accentSoft, in: .capsule)
            .overlay(Capsule().strokeBorder(
                (destination.isPortfolio ? style.portfolio : style.accent).opacity(0.35), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("destination-chip")
        .accessibilityHint("Change where this note goes")
    }

    // MARK: - Expanded

    /// PRIVATE | PORTFOLIO over the segments — the boundary named, once, where the choice is made.
    /// Measured rather than `maxWidth: .infinity`d, because the split is 1 segment to 3: an even
    /// two-up would centre "PORTFOLIO" over the Inspiration/Idea boundary and label the wrong columns.
    private var familyLabels: some View {
        GeometryReader { geo in
            let gap: CGFloat = 6
            let cell = max(0, (geo.size.width - gap * 3) / 4)
            HStack(spacing: gap) {
                Text("PRIVATE").frame(width: cell)
                Text("PORTFOLIO").frame(width: cell * 3 + gap * 2)
            }
            .font(.system(size: 9, weight: .bold))
            .tracking(0.8)
            .foregroundStyle(style.textFaint)
        }
        .frame(height: 11)
        .accessibilityHidden(true)
    }

    /// The dashed line between the Private cell and the three Portfolio cells, running the full
    /// height of labels + cells. Drawn as an overlay at the cell boundary (the same measure
    /// `familyLabels` uses) so it adds no layout width and the columns stay where they were.
    private var familyDivider: some View {
        GeometryReader { geo in
            let gap: CGFloat = 6
            let cell = max(0, (geo.size.width - gap * 3) / 4)
            Path { p in
                p.move(to: CGPoint(x: cell + gap / 2, y: 0))
                p.addLine(to: CGPoint(x: cell + gap / 2, y: geo.size.height))
            }
            .stroke(style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            .foregroundStyle(style.textFaint)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var segments: some View {
        HStack(spacing: 6) {
            ForEach(NoteDestination.allCases, id: \.self) { d in
                segment(d)
            }
        }
    }

    private func segment(_ d: NoteDestination) -> some View {
        let on = d == destination
        let hue = d.isPortfolio ? style.portfolio : style.accent
        return Button {
            if d != destination {
                destination = d
                onPick(d)
            }
            withAnimation(reduceMotion ? nil : SkMotion.snappy) { expanded = false }
        } label: {
            VStack(spacing: 6) {
                Circle()
                    .fill(on ? hue : style.textFaint)
                    .frame(width: 7, height: 7)
                Text(d.label)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1).minimumScaleFactor(0.8)
                    .foregroundStyle(on ? hue : style.textDim)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(on ? hue.opacity(0.14) : style.chipFill,
                        in: .rect(cornerRadius: 11, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(on ? hue.opacity(0.55) : style.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("destination-\(d.rawValue)")
        .accessibilityAddTraits(on ? [.isSelected] : [])
    }
}
