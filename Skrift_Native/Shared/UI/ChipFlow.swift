import SwiftUI

/// Q265 (C115/C240): the note card's chip row wraps instead of running past the card edge.
/// Chips flow onto at most `maxLines` lines in their given order; if some still do not fit,
/// the tail is replaced by one "+N" chip (N = how many are hidden). Shared by both apps'
/// `NoteCardView`. No `#if os()`; SwiftUI-only so the host-less Mac test bundle compiles it.

/// The line-break decision, pure so a test can drive it without a view.
enum ChipLineBreaker {
    struct Plan: Equatable {
        /// How many of the real chips are shown (the first `visible`, in order).
        var visible: Int
        /// Items per line. When chips are hidden the "+N" chip counts as the last item of the
        /// last line; so `lineCounts.reduce(0,+) == visible + (hidden > 0 ? 1 : 0)`.
        var lineCounts: [Int]
        var hidden: Int
    }

    /// `widths[i]` = chip i's natural width; `overflowWidth(k)` = width of the "+k" chip.
    /// Every item is clamped to `maxWidth` (a chip wider than the row takes a line alone and
    /// truncates). Always shows at least one chip.
    static func plan(widths: [CGFloat], overflowWidth: (Int) -> CGFloat,
                     maxWidth: CGFloat, spacing: CGFloat, maxLines: Int) -> Plan {
        let n = widths.count
        guard n > 0 else { return Plan(visible: 0, lineCounts: [], hidden: 0) }
        if let all = fit(widths.map { min($0, maxWidth) }, maxWidth: maxWidth,
                         spacing: spacing, maxLines: maxLines) {
            return Plan(visible: n, lineCounts: all, hidden: 0)
        }
        var v = n - 1
        while v >= 1 {
            let items = widths.prefix(v).map { min($0, maxWidth) } + [min(overflowWidth(n - v), maxWidth)]
            if let counts = fit(items, maxWidth: maxWidth, spacing: spacing, maxLines: maxLines) {
                return Plan(visible: v, lineCounts: counts, hidden: n - v)
            }
            v -= 1
        }
        // No longer run fits: the first chip, then "+N" on its own line.
        return Plan(visible: 1, lineCounts: maxLines >= 2 ? [1, 1] : [1], hidden: n - 1)
    }

    /// Greedy line fill; nil if it needs more than `maxLines` lines.
    private static func fit(_ items: [CGFloat], maxWidth: CGFloat, spacing: CGFloat,
                            maxLines: Int) -> [Int]? {
        var counts: [Int] = []
        var x: CGFloat = 0
        var inLine = 0
        for w in items {
            if inLine > 0, x + spacing + w > maxWidth {
                counts.append(inLine); inLine = 0; x = 0
            }
            x += (inLine > 0 ? spacing : 0) + w
            inLine += 1
        }
        if inLine > 0 { counts.append(inLine) }
        return counts.count <= maxLines ? counts : nil
    }
}

/// One chip inside `ChipFlowLayout`: its natural size, or 0×0 when proposed zero (the layout's
/// "hidden" signal). Wrap it in `.clipped()` so a collapsed chip draws nothing.
struct ChipSlot: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        if proposal.width == 0 || proposal.height == 0 { return .zero }
        return subviews.first?.sizeThatFits(proposal) ?? .zero
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        subviews.first?.place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(bounds.size))
    }
}

/// Lays out `chipCount` chips followed by `chipCount - 1` candidate "+k" chips (k = 1...n-1,
/// at index `chipCount + k - 1`). Only the chosen "+N" candidate is shown; unchosen chips and
/// candidates are proposed 0×0 at the origin, so each subview must be a clipped `ChipSlot`.
/// Subviews must be in that order.
struct ChipFlowLayout: Layout {
    var chipCount: Int
    var spacing: CGFloat = 4
    var lineSpacing: CGFloat = 4
    var maxLines: Int = 2

    /// Q323: the natural sizes of the subviews and the plan per width, kept for the layout's cache
    /// lifetime. A self-sizing List cell asks `sizeThatFits` repeatedly while scrolling (b179 trace:
    /// `ChipFlowLayout.plan` measured every chip subview on each ask, ~5% of main during a fast
    /// scroll); a subview's natural size never depends on the proposal, so each is measured once.
    /// SwiftUI rebuilds the cache (`updateCache`) whenever the subviews or the environment change.
    struct Cache {
        var natural: [Int: CGSize] = [:]
        var planWidth: CGFloat?
        var plan: ChipLineBreaker.Plan?
        /// How many subviews were measured (tests and the benchmark read it).
        var measured = 0
    }

    func makeCache(subviews: Subviews) -> Cache { Cache() }
    func updateCache(_ cache: inout Cache, subviews: Subviews) { cache = Cache() }

    private func natural(_ i: Int, _ subviews: Subviews, _ cache: inout Cache) -> CGSize {
        if let s = cache.natural[i] { return s }
        let s = subviews[i].sizeThatFits(.unspecified)
        cache.natural[i] = s
        cache.measured += 1
        return s
    }

    private func plan(_ subviews: Subviews, maxWidth: CGFloat, cache: inout Cache) -> ChipLineBreaker.Plan {
        if let p = cache.plan, cache.planWidth == maxWidth { return p }
        let widths = (0..<chipCount).map { natural($0, subviews, &cache).width }
        var overflow: [Int: CGFloat] = [:]
        let p = ChipLineBreaker.plan(
            widths: widths,
            overflowWidth: { k in
                let i = chipCount + k - 1
                guard i < subviews.count else { return 0 }
                if let w = overflow[k] { return w }
                let w = natural(i, subviews, &cache).width
                overflow[k] = w
                return w
            },
            maxWidth: maxWidth, spacing: spacing, maxLines: maxLines)
        cache.plan = p
        cache.planWidth = maxWidth
        return p
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        guard chipCount > 0 else { return .zero }
        let maxWidth = proposal.width ?? .infinity
        let p = plan(subviews, maxWidth: maxWidth, cache: &cache)
        var widest: CGFloat = 0, height: CGFloat = 0
        var item = 0
        for (line, count) in p.lineCounts.enumerated() {
            var x: CGFloat = 0, rowH: CGFloat = 0
            for _ in 0..<count {
                let s = size(of: item, plan: p, subviews: subviews, maxWidth: maxWidth, cache: &cache)
                x += (x > 0 ? spacing : 0) + s.width
                rowH = max(rowH, s.height)
                item += 1
            }
            widest = max(widest, x)
            height += rowH + (line > 0 ? lineSpacing : 0)
        }
        return CGSize(width: min(maxWidth, widest), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        guard chipCount > 0 else { return }
        let p = plan(subviews, maxWidth: bounds.width, cache: &cache)
        var shown = Set<Int>()
        var item = 0, y = bounds.minY
        for (line, count) in p.lineCounts.enumerated() {
            var x = bounds.minX, rowH: CGFloat = 0
            for _ in 0..<count {
                let idx = index(of: item, plan: p)
                let s = size(of: item, plan: p, subviews: subviews, maxWidth: bounds.width, cache: &cache)
                subviews[idx].place(at: CGPoint(x: x, y: y), anchor: .topLeading,
                                    proposal: ProposedViewSize(width: s.width, height: s.height))
                shown.insert(idx)
                x += s.width + spacing
                rowH = max(rowH, s.height)
                item += 1
            }
            y += rowH + lineSpacing
        }
        // Q312: unchosen chips and candidates collapse to 0×0 at the origin (each is a clipped
        // `ChipSlot`, so it draws nothing). Parking them 10 000 pt off-screen made a phone List
        // cell grow ~10 000 pt tall for any card with 2+ chips.
        for i in 0..<subviews.count where !shown.contains(i) {
            subviews[i].place(at: bounds.origin, anchor: .topLeading, proposal: .zero)
        }
    }

    /// Subview index for the `item`-th shown element (the last one is "+N" when chips are hidden).
    private func index(of item: Int, plan p: ChipLineBreaker.Plan) -> Int {
        (p.hidden > 0 && item == p.visible) ? chipCount + p.hidden - 1 : item
    }

    private func size(of item: Int, plan p: ChipLineBreaker.Plan, subviews: Subviews,
                      maxWidth: CGFloat, cache: inout Cache) -> CGSize {
        let s = natural(index(of: item, plan: p), subviews, &cache)
        return CGSize(width: min(s.width, maxWidth), height: s.height)
    }
}
