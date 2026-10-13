import SwiftUI

/// Q356 (Q6 mock `.chips`, "Filter by type"): the shelf's type filter. "All" plus one chip per kind
/// on the shelf, in the mock's order; with one kind there is nothing to filter, so no chips.
enum LibraryTypeFilter: Hashable {
    case all
    case kind(LibrarySourceKind)

    /// The mock's order: All, Books, Episodes, Articles, PDFs.
    private static let order: [LibrarySourceKind] = [.book, .episode, .article, .pdf]

    static func chips(for books: [Audiobook]) -> [LibraryTypeFilter] {
        let present = Set(books.map(\.sourceKind))
        guard present.count > 1 else { return [] }
        return [.all] + order.filter(present.contains).map { .kind($0) }
    }

    var label: String {
        switch self {
        case .all: "All"
        case .kind(.book): "Books"
        case .kind(.episode): "Episodes"
        case .kind(.article): "Articles"
        case .kind(.pdf): "PDFs"
        }
    }

    func apply(_ books: [Audiobook]) -> [Audiobook] {
        switch self {
        case .all: books
        case .kind(let k): books.filter { $0.sourceKind == k }
        }
    }
}

/// The chip row: 13pt medium, 30pt tall, 16pt corners; the pressed chip takes the accent wash.
struct LibraryTypeChips: View {
    let chips: [LibraryTypeFilter]
    @Binding var selection: LibraryTypeFilter

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(chips, id: \.self) { chip in
                    let on = chip == selection
                    Button { selection = chip } label: {
                        Text(chip.label)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(on ? Color.skAccentText : Color.skTextDim)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .frame(minHeight: 30)
                            .background(on ? Color.skAccentSoft : Color.skElev, in: .capsule)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                    .accessibilityIdentifier("library-type-chip")
                }
            }
        }
        .scrollIndicators(.hidden)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Filter by type")
    }
}
