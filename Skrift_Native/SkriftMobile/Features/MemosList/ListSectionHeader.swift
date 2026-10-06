import SwiftUI

/// D180 / Q324 — the Notes list's section headers ("TODAY", "SAT 3 OCT", "RELATED") scroll WITH the
/// notes instead of pinning at the top. A SwiftUI plain `List` pins every `Section` header, and UIKit's
/// pinned-supplementary solve was ~27% of main-thread scroll work at 2,000 notes (plan/perf2/MEASURED.md),
/// so the header is the section's first ROW: same text, size, kerning and colour, no pinning.
/// Sections stay (search/filter grouping and the row diff are keyed on them).
enum ListSectionHeaderStyle {
    /// The decision itself; `ListHeadersScrollTests` pins it.
    static let pinsToTop = false
    /// Where the header sits in its row. Tuned against the pinned look it replaces
    /// (tuned against before/after sim screenshots of the pinned look).
    static let insets = EdgeInsets(top: 24, leading: 16, bottom: 3, trailing: 16)

    /// The day header's displayed text.
    static func text(for title: String) -> String { title.uppercased() }
}

/// A non-pinning header row. Not selectable (the list has a selection binding), no separator, no
/// background, and an accessibility header so VoiceOver's heading rotor still finds it.
struct ListSectionHeaderRow<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(ListSectionHeaderStyle.insets)
            .selectionDisabled()
            .accessibilityAddTraits(.isHeader)
    }
}

/// The day-section header: bold dim caps at `ListChrome` size/kerning.
struct DayHeaderRow: View {
    let title: String

    var body: some View {
        ListSectionHeaderRow {
            Text(ListSectionHeaderStyle.text(for: title))
                .font(.system(size: ListChrome.headerSize, weight: .bold))
                .kerning(ListChrome.headerKerning)
                .foregroundStyle(Color.skTextDim)
        }
    }
}
