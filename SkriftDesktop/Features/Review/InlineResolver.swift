import SwiftUI
import AppKit

/// A single occurrence's resolution. `.plain` = deliberately left as plain text;
/// `.person` = linked to that candidate.
enum ResolverChoice: Equatable {
    case person(NameCandidate)
    case plain
    var candidate: NameCandidate? { if case let .person(c) = self { return c } else { return nil } }
}

/// R3 — inline name disambiguation. Flow (per the user): ask "Who is X?" up top per
/// ambiguous alias and **auto-apply** — pick one person → it's applied to EVERY
/// mention at once (first → `[[Canonical]]`, rest → the alias), no extra step. Only
/// when the alias is actually several people do you pick "Different people" → then you
/// click each highlighted mention in the text (per-occurrence), which auto-applies
/// once they're all chosen. No "Apply" button anywhere.
///
/// The model is live UI state (which aliases remain, which are escalated, the
/// per-occurrence choices); `PipelineFile.ambiguousNames` stays the persisted source
/// of truth and is trimmed as each alias resolves. Apply runs through the existing
/// `Sanitiser.applyResolvedNames` / `applyResolvedOccurrences`.
@Observable
final class InlineResolverModel {
    let fileID: String
    private(set) var candidatesByAlias: [String: [NameCandidate]]   // lowercased alias → people
    private(set) var displayAlias: [String: String]                 // lowercased → as written
    private(set) var aliasOrder: [String]                           // lowercased, first-seen order
    /// Aliases switched to per-occurrence mode ("Different people").
    var escalated: Set<String> = []
    /// Per-occurrence choices for escalated aliases: alias → (body location → choice).
    var occDecisions: [String: [Int: ResolverChoice]] = [:]
    /// Bumped on escalate/de-escalate so the body's NSTextView re-styles its marks
    /// (it doesn't otherwise observe those fields).
    var styleVersion = 0

    // Wired by NoteDisplayView (which holds the file + model context).
    var onResolveAlias: ((String, ResolverChoice) -> Void)?       // apply one person/plain to ALL mentions
    var onEscalate: ((String) -> Void)?                            // → per-occurrence mode
    var onDeescalate: ((String) -> Void)?                          // ← back to the single question
    var onDecideOccurrence: ((String, Int, ResolverChoice) -> Void)?  // alias, body location, choice
    var jumpHandler: (() -> Void)?

    init(fileID: String, ambiguous: [AmbiguousOccurrence]) {
        self.fileID = fileID
        var c: [String: [NameCandidate]] = [:]
        var d: [String: String] = [:]
        var order: [String] = []
        for occ in ambiguous {
            let k = occ.alias.lowercased()
            if c[k] == nil { c[k] = occ.candidates; d[k] = occ.alias; order.append(k) }
        }
        candidatesByAlias = c; displayAlias = d; aliasOrder = order
    }

    var isEmpty: Bool { aliasOrder.isEmpty }
    func candidates(for alias: String) -> [NameCandidate] { candidatesByAlias[alias.lowercased()] ?? [] }
    func display(_ alias: String) -> String { displayAlias[alias.lowercased()] ?? alias }
    func isEscalated(_ alias: String) -> Bool { escalated.contains(alias.lowercased()) }
    func choice(alias: String, location: Int) -> ResolverChoice? { occDecisions[alias.lowercased()]?[location] }

    /// Drop a fully-resolved alias from the live state.
    func removeAlias(_ alias: String) {
        let k = alias.lowercased()
        candidatesByAlias[k] = nil
        displayAlias[k] = nil
        escalated.remove(k)
        occDecisions[k] = nil
        aliasOrder.removeAll { $0 == k }
    }
}

// ── Banner: the up-top asker (one row per unresolved alias) ────────────────────

struct InlineResolverBanner: View {
    var model: InlineResolverModel

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            ForEach(model.aliasOrder, id: \.self) { alias in
                if model.isEscalated(alias) { escalatedRow(alias) } else { aliasRow(alias) }
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.accent.opacity(0.22), lineWidth: 0.5))
    }

    @ViewBuilder private func aliasRow(_ alias: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            (Text("Who is ").foregroundStyle(Theme.textSecondary)
                + Text("“\(model.display(alias))”").foregroundStyle(Theme.textPrimary).bold()
                + Text("?").foregroundStyle(Theme.textSecondary))
                .font(.system(size: 12))
            FlowLayout(spacing: 6) {
                ForEach(model.candidates(for: alias), id: \.canonical) { c in
                    chip(clean(c.canonical), filled: true) { model.onResolveAlias?(alias, .person(c)) }
                }
                chip("Leave plain", filled: false) { model.onResolveAlias?(alias, .plain) }
                Button { model.onEscalate?(alias) } label: {
                    Label("Different people", systemImage: "arrow.triangle.branch")
                        .font(.system(size: 11)).foregroundStyle(Theme.textMuted)
                        .padding(.horizontal, 9).padding(.vertical, 3)
                        .overlay(Capsule().stroke(Theme.hairline.opacity(0.14), lineWidth: 0.5))
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder private func escalatedRow(_ alias: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "hand.tap").font(.system(size: 11)).foregroundStyle(Theme.accent)
            (Text("Tap each ").foregroundStyle(Theme.textSecondary)
                + Text("“\(model.display(alias))”").foregroundStyle(Theme.textPrimary).bold()
                + Text(" in the text to identify it").foregroundStyle(Theme.textSecondary))
                .font(.system(size: 12))
            Spacer(minLength: 6)
            if model.jumpHandler != nil {
                Button { model.jumpHandler?() } label: {
                    Text("Jump to next ›").font(.system(size: 11)).foregroundStyle(Theme.accent)
                        .padding(.horizontal, 9).padding(.vertical, 3)
                        .overlay(Capsule().stroke(Theme.accent.opacity(0.3), lineWidth: 0.5))
                }
                .buttonStyle(.plain)
            }
            Button { model.onDeescalate?(alias) } label: {   // back to the single question
                Text("It’s one person").font(.system(size: 11)).foregroundStyle(Theme.textMuted)
            }
            .buttonStyle(.plain)
            .help("These are all the same person — ask once instead")
        }
    }

    private func chip(_ text: String, filled: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text).font(.system(size: 11.5))
                .foregroundStyle(filled ? Theme.accent : Theme.textMuted)
                .padding(.horizontal, 10).padding(.vertical, 3)
                .background(filled ? Theme.accent.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6)
                    .stroke(filled ? Theme.accent.opacity(0.4) : Theme.hairline.opacity(0.14),
                            style: StrokeStyle(lineWidth: 0.5, dash: filled ? [] : [3])))
        }
        .buttonStyle(.plain)
    }

    private func clean(_ canonical: String) -> String {
        canonical.replacingOccurrences(of: "[[", with: "").replacingOccurrences(of: "]]", with: "")
    }
}

// ── Popover shown at a clicked mention ────────────────────────────────────────

/// Modes: `.alias` (single, default) lets you pick one person for ALL mentions or
/// escalate; `.occurrence` (after escalation) picks the person for just this mention.
struct ResolverPopover: View {
    enum Mode { case alias, occurrence }
    let mode: Mode
    let alias: String
    let contextBefore: String
    let contextAfter: String
    let candidates: [NameCandidate]
    let current: ResolverChoice?
    var onPick: (ResolverChoice) -> Void
    var onEscalate: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            (Text(mode == .occurrence ? "Who is this " : "Who is ").foregroundStyle(Theme.textSecondary)
                + Text("“\(alias)”").foregroundStyle(Theme.textPrimary).bold()
                + Text("?").foregroundStyle(Theme.textSecondary))
                .font(.system(size: 12)).padding(.bottom, mode == .alias ? 0 : 3)

            if mode == .alias {
                Text("Applies to every mention").font(.system(size: 9.5)).foregroundStyle(Theme.textMuted).padding(.bottom, 7)
            }

            (Text("…\(contextBefore)").foregroundStyle(Theme.textMuted)
                + Text(alias).foregroundStyle(Theme.textSecondary).bold()
                + Text("\(contextAfter)…").foregroundStyle(Theme.textMuted))
                .font(.system(size: 10.5)).italic().lineLimit(2).padding(.bottom, 9)

            ForEach(candidates, id: \.canonical) { c in
                optionRow(initials(c.canonical), clean(c.canonical),
                          selected: current?.candidate?.canonical == c.canonical) { onPick(.person(c)) }
            }

            Rectangle().fill(Theme.hairline.opacity(0.08)).frame(height: 0.5).padding(.vertical, 6)

            optionRow("—", "Leave as plain text", plain: true, selected: current == .plain) { onPick(.plain) }

            if mode == .alias {
                Button(action: onEscalate) {
                    Label("They’re different people", systemImage: "arrow.triangle.branch")
                        .font(.system(size: 11.5)).foregroundStyle(Theme.accent)
                        .padding(.horizontal, 8).padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .frame(width: 248)
        .background(Theme.surfaceHover)
    }

    @ViewBuilder
    private func optionRow(_ avatar: String, _ name: String, plain: Bool = false, selected: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(avatar).font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(plain ? Theme.textMuted : Theme.accent)
                    .frame(width: 18, height: 18)
                    .background((plain ? Theme.hairline.opacity(0.06) : Theme.accent.opacity(0.25)), in: Circle())
                Text(name).font(.system(size: 12.5)).foregroundStyle(plain ? Theme.textMuted : Theme.textPrimary)
                Spacer(minLength: 4)
                if selected { Image(systemName: "checkmark").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.accent) }
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
