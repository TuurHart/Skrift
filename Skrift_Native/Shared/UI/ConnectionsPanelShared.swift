import SwiftUI

// Q181 (C239/C240, R58): the Connections panel's look + wording, ONE copy for the Mac and
// the iPad (they were twin code: 300 vs 280 wide, 11 vs 10pt header, why-chips capped on
// one side only, hide on one view mode only). Pattern = the note card: shared views here,
// a per-app `ConnectionsPanelStyle` carrying only the colours. No `#if os()` in this file.
//
// Picks where the two apps differed (veto in the Q181 commit message): the phone's size,
// wording and shape won unless a signed mock named the Mac's (the related-panel mock names
// the Mac's hover-✕ and 280pt, but the iPad panel already shipped at 300 and the spec has
// no number, so the wider one stands for both).

enum ConnectionsPanelSpec {
    /// The standing panel's width on both apps (Mac was 280, iPad 300).
    static let panelWidth: CGFloat = 300
    static let headerTitle = "CONNECTIONS"
    static let headerTitleSize: CGFloat = 11
    static let headerCountSize: CGFloat = 10
    /// The Date rail's date line (Mac 9pt uppercase, iPad 10pt).
    static let dateLineSize: CGFloat = 10
    static let dateLineFlagSize: CGFloat = 8.5
    /// Chips shown per row before "+N" (the Mac's cap; the iPad showed all).
    static let whyChipCap = 3
    /// Hide a pairing: one wording, on the Mac's hover ✕ tooltip and both apps' context menu.
    static let hideLabel = "Not related — hide"
    static let hideIcon = "xmark"
    /// The close / collapse control's accessibility label.
    static let closeLabel = "Hide Connections"

    /// "12 Mar" — the row date, one format.
    static func day(_ date: Date?) -> String {
        guard let date else { return "—" }
        return date.formatted(.dateTime.day().month(.abbreviated))
    }
}

extension ConnectionWhy {
    /// What the chip prints: a recurring term in curly quotes (the phone's look), a person
    /// or #tag as is.
    var displayText: String { kind == .term ? "“\(text)”" : text }
}

/// The cap decision, pure: the first `whyChipCap` chips and how many are folded into "+N".
struct ConnectionWhyPlan: Equatable {
    let shown: [ConnectionWhy]
    let extra: Int

    init(_ chips: [ConnectionWhy], cap: Int = ConnectionsPanelSpec.whyChipCap) {
        shown = Array(chips.prefix(cap))
        extra = max(0, chips.count - cap)
    }
}

/// The only per-app part of the panel chrome: colours.
struct ConnectionsPanelStyle {
    var headerTitle: Color
    var countText: Color
    var countFill: Color
    var dateText: Color
    var flagText: Color
    var importance: Color
    var importanceTop: Color
    var whyPerson: Color
    var whyTag: Color
    var whyTerm: Color
    var whyMore: Color

    func whyColor(_ kind: ConnectionWhy.Kind) -> Color {
        switch kind {
        case .person: whyPerson
        case .tag: whyTag
        case .term: whyTerm
        }
    }
}

/// "CONNECTIONS" + the count capsule.
struct ConnectionsHeaderLabel: View {
    let count: Int
    let style: ConnectionsPanelStyle

    var body: some View {
        HStack(spacing: 7) {
            Text(ConnectionsPanelSpec.headerTitle)
                .font(.system(size: ConnectionsPanelSpec.headerTitleSize, weight: .bold)).tracking(0.5)
                .foregroundStyle(style.headerTitle)
            if count > 0 {
                Text("\(count)")
                    .font(.system(size: ConnectionsPanelSpec.headerCountSize, weight: .bold).monospacedDigit())
                    .foregroundStyle(style.countText)
                    .padding(.horizontal, 7).padding(.vertical, 1)
                    .background(style.countFill, in: Capsule())
            }
        }
    }
}

/// The why-chips under a row: ≤3 coloured by kind + "+N".
struct ConnectionWhyRow: View {
    let chips: [ConnectionWhy]
    let style: ConnectionsPanelStyle

    var body: some View {
        let plan = ConnectionWhyPlan(chips)
        if !plan.shown.isEmpty {
            HStack(spacing: 4) {
                ForEach(plan.shown, id: \.self) { chip in
                    let color = style.whyColor(chip.kind)
                    HStack(spacing: 3) {
                        if chip.kind == .person {
                            Image(systemName: "person.fill").font(.system(size: 7.5))
                        }
                        Text(chip.displayText)
                            .font(.system(size: 9.5, weight: .medium))
                            .lineLimit(1)
                    }
                    .foregroundStyle(color)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(color.opacity(chip.kind == .term ? 0.08 : 0.13), in: Capsule())
                }
                if plan.extra > 0 {
                    Text("+\(plan.extra)")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(style.whyMore)
                }
            }
            .padding(.top, 3)
        }
    }
}

/// The Date rail's top line: date · flag · importance readout. `readout` is
/// `ThreeBallScale.readout` (nil when unrated).
struct ConnectionDateLine: View {
    let date: Date
    let flag: String?
    let readout: String?
    let isTop: Bool
    let style: ConnectionsPanelStyle

    var body: some View {
        HStack(spacing: 6) {
            Text(ConnectionsPanelSpec.day(date))
                .font(.system(size: ConnectionsPanelSpec.dateLineSize).monospacedDigit())
                .foregroundStyle(style.dateText)
            if let flag {
                Text(flag)
                    .font(.system(size: ConnectionsPanelSpec.dateLineFlagSize, weight: .bold)).tracking(0.4)
                    .foregroundStyle(style.flagText)
            }
            Spacer(minLength: 4)
            if let readout {
                Text(readout)
                    .font(.system(size: ConnectionsPanelSpec.dateLineSize, weight: .bold).monospacedDigit())
                    .foregroundStyle(isTop ? style.importanceTop : style.importance)
            }
        }
    }
}
