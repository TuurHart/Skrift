import SwiftUI

/// One review-time decision. `offset == nil` applies to every occurrence of the
/// alias; `canonical == nil` means "leave as plain text".
struct ResolverDecision {
    let alias: String
    let offset: Int?
    let canonical: String?
    let short: String?
}

/// Review-time ambiguous-name resolver. Smart model (agreed with the user): group
/// by alias by default — one choice covers all occurrences — but any alias with 2+
/// occurrences can expand to per-occurrence choices (the "two Jacks" case).
struct ResolverStrip: View {
    let occurrences: [AmbiguousOccurrence]
    var onResolve: ([ResolverDecision]) -> Void

    private static let plain = "__plain__"

    @State private var aliasChoice: [String: String] = [:]   // key → canonical | plain
    @State private var occChoice: [Int: String] = [:]        // offset → canonical | plain
    @State private var expanded: Set<String> = []

    private struct Group { let alias: String; let key: String; let candidates: [NameCandidate]; let occs: [AmbiguousOccurrence] }

    private var groups: [Group] {
        var map: [String: Group] = [:]
        var order: [String] = []
        for occ in occurrences {
            let key = occ.alias.lowercased()
            if let g = map[key] {
                map[key] = Group(alias: g.alias, key: key, candidates: g.candidates, occs: g.occs + [occ])
            } else {
                map[key] = Group(alias: occ.alias, key: key, candidates: occ.candidates, occs: [occ])
                order.append(key)
            }
        }
        return order.compactMap { map[$0] }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(groups, id: \.key) { group in groupView(group) }
            applyButton
        }
        .padding(14)
        .background(Theme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(Theme.accent.opacity(0.25), lineWidth: 0.5))
    }

    @ViewBuilder private func groupView(_ g: Group) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                (Text("Who is ").foregroundStyle(Theme.textSecondary)
                    + Text("“\(g.alias)”").foregroundStyle(Theme.textPrimary).bold()
                    + Text("?").foregroundStyle(Theme.textSecondary))
                    .font(.system(size: 12))
                if g.occs.count > 1 {
                    Text("· \(g.occs.count)×").font(.system(size: 11)).foregroundStyle(Theme.textMuted)
                }
            }

            if expanded.contains(g.key) {
                // Per-occurrence: each mention with its own context + choices.
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(g.occs, id: \.offset) { occ in
                        VStack(alignment: .leading, spacing: 5) {
                            context(occ)
                            FlowLayout(spacing: 6) {
                                ForEach(g.candidates, id: \.canonical) { c in
                                    pill(label(c.canonical), selected: occChoice[occ.offset] == c.canonical) {
                                        occChoice[occ.offset] = c.canonical
                                    }
                                }
                                plainPill(selected: occChoice[occ.offset] == Self.plain) {
                                    occChoice[occ.offset] = Self.plain
                                }
                            }
                        }
                        .padding(.leading, 10)
                        .overlay(alignment: .leading) { Rectangle().fill(Theme.hairline.opacity(0.1)).frame(width: 1) }
                    }
                    collapseToggle(g)
                }
            } else {
                FlowLayout(spacing: 6) {
                    ForEach(g.candidates, id: \.canonical) { c in
                        pill(label(c.canonical), selected: aliasChoice[g.key] == c.canonical) {
                            aliasChoice[g.key] = c.canonical
                        }
                    }
                    plainPill(selected: aliasChoice[g.key] == Self.plain) {
                        aliasChoice[g.key] = Self.plain
                    }
                }
                if g.occs.count > 1 { expandToggle(g) }
            }
        }
    }

    private func context(_ occ: AmbiguousOccurrence) -> some View {
        (Text("…\(occ.contextBefore)").foregroundStyle(Theme.textMuted)
            + Text(occ.alias).foregroundStyle(Theme.textSecondary).bold()
            + Text("\(occ.contextAfter)…").foregroundStyle(Theme.textMuted))
            .font(.system(size: 11))
            .lineLimit(1)
    }

    private func expandToggle(_ g: Group) -> some View {
        Button { expanded.insert(g.key); aliasChoice[g.key] = nil } label: {
            Label("These are different people", systemImage: "arrow.triangle.branch")
                .font(.system(size: 11)).foregroundStyle(Theme.accent)
        }
        .buttonStyle(.plain)
    }

    private func collapseToggle(_ g: Group) -> some View {
        Button { expanded.remove(g.key); for occ in g.occs { occChoice[occ.offset] = nil } } label: {
            Label("Same person, actually", systemImage: "arrow.uturn.left")
                .font(.system(size: 11)).foregroundStyle(Theme.textMuted)
        }
        .buttonStyle(.plain)
    }

    private func pill(_ text: String, selected: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text).font(.system(size: 11.5))
                .foregroundStyle(selected ? Theme.accent : Theme.textSecondary)
                .padding(.horizontal, 10).padding(.vertical, 3)
                .background(selected ? Theme.accent.opacity(0.18) : Theme.hairline.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(selected ? Theme.accent.opacity(0.5) : Theme.hairline.opacity(0.12), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    private func plainPill(selected: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text("leave plain").font(.system(size: 11.5))
                .foregroundStyle(selected ? Theme.textPrimary : Theme.textMuted)
                .padding(.horizontal, 10).padding(.vertical, 3)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.hairline.opacity(selected ? 0.3 : 0.12), style: StrokeStyle(lineWidth: 0.5, dash: selected ? [] : [3])))
        }
        .buttonStyle(.plain)
    }

    private var applyButton: some View {
        Button { onResolve(buildDecisions()) } label: {
            Text(allDecided ? "Apply names" : "Pick each name to continue")
                .font(.system(size: 12, weight: .medium)).foregroundStyle(.white)
                .padding(.horizontal, 14).padding(.vertical, 6)
                .background(Theme.accent.opacity(allDecided ? 1 : 0.4), in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .disabled(!allDecided)
    }

    private var allDecided: Bool {
        groups.allSatisfy { g in
            if expanded.contains(g.key) { return g.occs.allSatisfy { occChoice[$0.offset] != nil } }
            return aliasChoice[g.key] != nil
        }
    }

    private func buildDecisions() -> [ResolverDecision] {
        var out: [ResolverDecision] = []
        for g in groups {
            if expanded.contains(g.key) {
                for occ in g.occs {
                    let choice = occChoice[occ.offset]
                    let c = g.candidates.first { $0.canonical == choice }
                    out.append(ResolverDecision(alias: g.alias, offset: occ.offset, canonical: c?.canonical, short: c?.short))
                }
            } else {
                let choice = aliasChoice[g.key]
                let c = g.candidates.first { $0.canonical == choice }
                out.append(ResolverDecision(alias: g.alias, offset: nil, canonical: c?.canonical, short: c?.short))
            }
        }
        return out
    }

    private func label(_ canonical: String) -> String {
        canonical.replacingOccurrences(of: "[[", with: "").replacingOccurrences(of: "]]", with: "")
    }
}
