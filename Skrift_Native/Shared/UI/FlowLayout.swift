import SwiftUI

/// Wrapping horizontal layout — chips/tags flow onto new lines. Pure SwiftUI
/// `Layout` (iOS 16 / macOS 13+), so it renders under `ImageRenderer` for snapshots.
/// SHARED: one copy for the phone app, the Mac app, and the Share extension (the
/// two apps previously carried byte-equivalent-but-not-identical copies).
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6
    /// Q540: centre each item vertically on its line (the tag field is 6 pt shorter than the chip
    /// beside it). Off by default: other callers keep their top-aligned look.
    var centerItems = false

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > maxWidth, x > 0 {
                x = 0; y += rowHeight + lineSpacing; rowHeight = 0
            }
            x += sz.width + spacing
            rowHeight = max(rowHeight, sz.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: min(maxWidth, widest), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        // Pass 1: break the items into lines and measure each line's height.
        var lines: [[(index: Int, size: CGSize)]] = [[]]
        var x = bounds.minX
        for (i, s) in subviews.enumerated() {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > bounds.maxX, x > bounds.minX {
                lines.append([]); x = bounds.minX
            }
            lines[lines.count - 1].append((i, sz))
            x += sz.width + spacing
        }
        // Pass 2: place, top-aligned or centred on the line.
        var y = bounds.minY
        for line in lines {
            let rowHeight = line.map(\.size.height).max() ?? 0
            var px = bounds.minX
            for item in line {
                let dy = centerItems ? (rowHeight - item.size.height) / 2 : 0
                subviews[item.index].place(at: CGPoint(x: px, y: y + dy), anchor: .topLeading,
                                           proposal: ProposedViewSize(item.size))
                px += item.size.width + spacing
            }
            y += rowHeight + lineSpacing
        }
    }
}
