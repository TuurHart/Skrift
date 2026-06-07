import SwiftUI
import AppKit

/// One review-time decision passed to `ProcessingCoordinator.applyResolvedNames`.
/// `offset == nil` applies to every occurrence of the alias (legacy per-alias path);
/// `offset != nil` is a per-occurrence ordinal (the inline resolver always uses this,
/// so two friends named "Jack" stay distinct). `canonical == nil` = leave as plain text.
struct ResolverDecision {
    let alias: String
    let offset: Int?
    let canonical: String?
    let short: String?
}

/// A single occurrence's resolution while reviewing inline. Absent from the model =
/// undecided; `.plain` = deliberately left as plain text; `.person` = linked.
enum ResolverChoice: Equatable {
    case person(NameCandidate)
    case plain
    var candidate: NameCandidate? { if case let .person(c) = self { return c } else { return nil } }
}

/// Shared state for R3 — inline-in-text name disambiguation. The big card is gone;
/// instead each ambiguous mention is marked + clicked in the body (full-paragraph
/// context), and resolution is per-occurrence by nature. Decisions are keyed by the
/// mention's character location in the CURRENT body (stable because the body text is
/// only mutated on Apply, never per click). On Apply, `NoteDisplayView` re-enumerates
/// `Sanitiser.plainOccurrences` in the same order and feeds the existing order-based
/// `applyResolvedOccurrences` — so the engine work was already done.
@Observable
final class InlineResolverModel {
    let fileID: String
    /// lowercased alias → candidate people (identical for every occurrence of the alias).
    let candidatesByAlias: [String: [NameCandidate]]
    /// lowercased alias → the alias as it reads in the note (for the popover title).
    let displayAlias: [String: String]
    /// lowercased alias → occurrence count from `ambiguousNames` (banner total before
    /// the body reports what it actually found).
    private let aliasCounts: [String: Int]

    /// body char-location → the user's choice. Absent = undecided.
    var decisions: [Int: ResolverChoice] = [:]
    /// Occurrences the body text view actually marked (drives the banner total once known).
    var observedTotal: Int?
    /// Registered by the body so the banner's "jump to next" can scroll to it.
    var jumpHandler: (() -> Void)?

    init(fileID: String, ambiguous: [AmbiguousOccurrence]) {
        self.fileID = fileID
        var cands: [String: [NameCandidate]] = [:]
        var disp: [String: String] = [:]
        var counts: [String: Int] = [:]
        for occ in ambiguous {
            let key = occ.alias.lowercased()
            if cands[key] == nil { cands[key] = occ.candidates; disp[key] = occ.alias }
            counts[key, default: 0] += 1
        }
        candidatesByAlias = cands
        displayAlias = disp
        aliasCounts = counts
    }

    var total: Int { observedTotal ?? aliasCounts.values.reduce(0, +) }
    var decidedCount: Int { decisions.count }
    var pendingCount: Int { max(0, total - decidedCount) }
    var allDecided: Bool { total > 0 && decidedCount >= total }

    func candidates(for alias: String) -> [NameCandidate] { candidatesByAlias[alias.lowercased()] ?? [] }
}

// ── Slim banner (replaces the old resolver card) ──────────────────────────────

/// A quiet bar above the note while names need identifying: progress + a jump-to-next
/// nudge + Apply. The actual choosing happens inline in the body.
struct InlineResolverBanner: View {
    var model: InlineResolverModel
    var onApply: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(Theme.accent).frame(width: 7, height: 7)
                .overlay(Circle().stroke(Theme.accent.opacity(0.22), lineWidth: 3))

            if model.allDecided {
                (Text("All ").foregroundStyle(Theme.textSecondary)
                    + Text(countWord(model.total)).foregroundStyle(Theme.textPrimary).bold()
                    + Text(" identified").foregroundStyle(Theme.textSecondary))
                    .font(.system(size: 12))
            } else if model.decidedCount == 0 {
                (Text(countWord(model.total)).foregroundStyle(Theme.textPrimary).bold()
                    + Text(" to identify").foregroundStyle(Theme.textSecondary)
                    + Text(" — click a highlighted name").foregroundStyle(Theme.textMuted))
                    .font(.system(size: 12))
            } else {
                (Text("\(model.decidedCount) of \(model.total)").foregroundStyle(Theme.textPrimary).bold()
                    + Text(" identified").foregroundStyle(Theme.textSecondary))
                    .font(.system(size: 12))
            }

            Spacer(minLength: 8)

            if model.pendingCount > 0, model.jumpHandler != nil {
                Button { model.jumpHandler?() } label: {
                    Text("Jump to next ›")
                        .font(.system(size: 11.5)).foregroundStyle(Theme.accent)
                        .padding(.horizontal, 10).padding(.vertical, 3)
                        .overlay(Capsule().stroke(Theme.accent.opacity(0.35), lineWidth: 0.5))
                }
                .buttonStyle(.plain)
            }

            Button(action: onApply) {
                Text("Apply names")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(.white)
                    .padding(.horizontal, 13).padding(.vertical, 5)
                    .background(Theme.accent.opacity(model.allDecided ? 1 : 0.4), in: RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(.plain)
            .disabled(!model.allDecided)
        }
        .padding(.horizontal, 13).padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.accent.opacity(0.22), lineWidth: 0.5))
    }

    private func countWord(_ n: Int) -> String { n == 1 ? "1 name" : "\(n) names" }
}

// ── Popover shown at a clicked name ───────────────────────────────────────────

/// The candidate chooser anchored at an ambiguous mention. Full-paragraph context is
/// right there in the note; this just echoes the immediate phrase and lists the people.
struct ResolverPopover: View {
    let alias: String
    let contextBefore: String
    let contextAfter: String
    let candidates: [NameCandidate]
    let current: ResolverChoice?
    var onPick: (ResolverChoice) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            (Text("Who is ").foregroundStyle(Theme.textSecondary)
                + Text("“\(alias)”").foregroundStyle(Theme.textPrimary).bold()
                + Text(" here?").foregroundStyle(Theme.textSecondary))
                .font(.system(size: 12))
                .padding(.bottom, 3)

            (Text("…\(contextBefore)").foregroundStyle(Theme.textMuted)
                + Text(alias).foregroundStyle(Theme.textSecondary).bold()
                + Text("\(contextAfter)…").foregroundStyle(Theme.textMuted))
                .font(.system(size: 10.5)).italic()
                .lineLimit(2)
                .padding(.bottom, 9)

            ForEach(candidates, id: \.canonical) { c in
                optionRow(initials(c.canonical), clean(c.canonical),
                          selected: current?.candidate?.canonical == c.canonical) {
                    onPick(.person(c))
                }
            }

            Rectangle().fill(Theme.hairline.opacity(0.08)).frame(height: 0.5).padding(.vertical, 6)

            optionRow("—", "Leave as plain text", plain: true, selected: current == .plain) {
                onPick(.plain)
            }

            HStack(alignment: .top, spacing: 5) {
                Image(systemName: "chevron.right").font(.system(size: 8, weight: .bold)).foregroundStyle(Theme.textMuted)
                    .padding(.top, 2)
                Text("Each mention is set on its own — two friends with the same name stay separate.")
                    .font(.system(size: 9.5)).foregroundStyle(Theme.textMuted).lineLimit(2)
            }
            .padding(.top, 7).padding(.horizontal, 2)
        }
        .padding(12)
        .frame(width: 244)
        .background(Theme.surfaceHover)
    }

    @ViewBuilder
    private func optionRow(_ avatar: String, _ name: String, plain: Bool = false, selected: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(avatar)
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(plain ? Theme.textMuted : Theme.accent)
                    .frame(width: 18, height: 18)
                    .background((plain ? Theme.hairline.opacity(0.06) : Theme.accent.opacity(0.25)), in: Circle())
                Text(name)
                    .font(.system(size: 12.5))
                    .foregroundStyle(plain ? Theme.textMuted : Theme.textPrimary)
                Spacer(minLength: 4)
                if selected {
                    Image(systemName: "checkmark").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.accent)
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? Theme.accent.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 7))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func clean(_ canonical: String) -> String {
        canonical.replacingOccurrences(of: "[[", with: "").replacingOccurrences(of: "]]", with: "")
    }
    private func initials(_ canonical: String) -> String {
        let core = clean(canonical)
        let chars = core.split(separator: " ").prefix(2).compactMap { $0.first }
        return chars.isEmpty ? "?" : String(chars).uppercased()
    }
}
