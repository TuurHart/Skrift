import SwiftUI

/// Q66/D148 (option A of `mocks/Q49-one-filter.html`, Tuur 2026-09-26: "one
/// filter bar I pick A"): the chip row carries everything — the four status
/// chips, then Date (and, phone-only, Unsynced) past them, then a sort word
/// that steps to the next order on tap. No Filter icon, no sheet/popover
/// beyond what Date itself opens. Two colors is all either app's chip needs
/// (accent for "on", dim for idle) — construct from each app's own palette,
/// the `NoteCardStyle` pattern.
struct ChipRowStyle {
    var accent: Color
    var dim: Color
}

/// A chip past the four status ones — dashed outline when idle (it "stacks",
/// per the mock's own admission, rather than picking one of a set), solid
/// accent wash + hairline when active. Date and Unsynced both use this.
struct ExtraFilterChip: View {
    let label: String
    let active: Bool
    let style: ChipRowStyle
    var body: some View {
        Text(label)
            .font(.system(size: 11))
            .lineLimit(1).fixedSize()
            .foregroundStyle(active ? style.accent : style.dim)
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(active ? style.accent.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(active ? style.accent.opacity(0.22) : style.dim.opacity(0.35),
                                  style: active ? StrokeStyle(lineWidth: 1)
                                                : StrokeStyle(lineWidth: 1, dash: [3, 2]))
            )
            .contentShape(Rectangle())
    }
}

/// The row-ending sort word ("Newest ↓") — tap steps to the next sort.
/// `MemoSort.next`/`SidebarSort.next` already carry the cycle; this view only
/// renders whatever short label the caller hands it and reports the tap.
struct SortCycleWord: View {
    let word: String
    let style: ChipRowStyle
    let onTap: () -> Void
    var body: some View {
        Button(action: onTap) {
            Text("\(word) ↓")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(style.dim)
                .lineLimit(1).fixedSize()
        }
        .buttonStyle(.plain)
    }
}
