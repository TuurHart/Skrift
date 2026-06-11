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
/// click each highlighted mention in the text (per-occurrence) and EVERY pick applies
/// instantly: the clicked mention becomes its `[[link]]`/short name on the spot while
/// the remaining mentions stay highlighted, and the alias commits once they're all
/// chosen. No "Apply" button anywhere.
///
/// Instant apply works by recompute, not splice: the model keeps a pristine
/// `snapshot` of the body plus the choices made so far (keyed by snapshot occurrence
/// INDEX), and every pick re-renders the whole body from those via
/// `Sanitiser.applyPartialOccurrences` — so first-mention-gets-`[[Canonical]]` stays
/// a DOCUMENT-order fact (assigning an earlier mention to a person later moves the
/// link there and demotes the previously-linked mention in the same refresh).
/// Until an alias completes the partial render is view-owned: `ambiguousNames`
/// is untouched and the snapshot is restorable (note switch puts the pristine body
/// back). Completion behaves exactly as before — persist via
/// `Sanitiser.applyResolvedOccurrences` over the snapshot, trim the alias, recompile.
///
/// The model is live UI state (which aliases remain, which are escalated, the
/// per-occurrence choices); `PipelineFile.ambiguousNames` stays the persisted source
/// of truth and is trimmed as each alias resolves.
@Observable
final class InlineResolverModel {
    let fileID: String
    private(set) var candidatesByAlias: [String: [NameCandidate]]   // lowercased alias → people
    private(set) var displayAlias: [String: String]                 // lowercased → as written
    private(set) var aliasOrder: [String]                           // lowercased, first-seen order
    /// Aliases switched to per-occurrence mode ("Different people").
    var escalated: Set<String> = []

    // ── In-flight per-occurrence state (instant apply) ─────────────────────────
    /// The pristine body every in-flight choice keys against. Set on the first
    /// pick (or re-based after a commit / hand edit); nil = nothing in flight.
    private(set) var snapshot: String?
    /// What the last partial render produced — should equal the file body. A hand
    /// edit mid-flight makes it stale: marks fall back to undecided and the next
    /// pick re-bases on the edited text (in-flight choices are dropped; mentions
    /// already rendered as links stay as the user sees them).
    private(set) var lastRendered: String?
    /// Per-occurrence choices for escalated aliases: alias → (SNAPSHOT occurrence
    /// index → choice). Index-keyed, NOT offset-keyed, so the storage-vs-model
    /// offset drift from image attachments and the re-rendering itself can't
    /// misattribute a choice.
    private(set) var occDecisions: [String: [Int: ResolverChoice]] = [:]
    /// alias → its occurrence count in the snapshot (the banner's progress
    /// denominator; also the completion check's total).
    private(set) var occTotals: [String: Int] = [:]
    /// alias → for the k-th plain occurrence of the alias in `lastRendered`
    /// (reading order), the snapshot occurrence index it stands for (-1 = foreign
    /// text, e.g. another person's short name that happens to read as the alias).
    private(set) var plainSlots: [String: [Int]] = [:]

    /// Bumped on escalate/de-escalate/re-render so the body's NSTextView re-styles
    /// its marks (it doesn't otherwise observe those fields).
    var styleVersion = 0

    // Wired by NoteDisplayView (which holds the file + model context).
    var onResolveAlias: ((String, ResolverChoice) -> Void)?       // apply one person/plain to ALL mentions
    var onEscalate: ((String) -> Void)?                            // → per-occurrence mode
    var onDeescalate: ((String) -> Void)?                          // ← back to the single question
    /// alias, plain-occurrence index in the CURRENT body (reading order), choice.
    var onDecideOccurrence: ((String, Int, ResolverChoice) -> Void)?
    /// Restore the pristine snapshot to the file if an in-flight partial render is
    /// abandoned (note switch / external rewrite). Wired per file.
    var onAbandonPartial: (() -> Void)?
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

    /// Any in-flight per-occurrence choice at all (across aliases)?
    var hasPartialDecisions: Bool { occDecisions.contains { !$0.value.isEmpty } }

    /// In-flight choices for one alias, keyed by snapshot occurrence index.
    func decisions(for alias: String) -> [Int: ResolverChoice] { occDecisions[alias.lowercased()] ?? [:] }

    /// True while `text` is exactly what the last partial render produced — the
    /// gate for trusting index-keyed choices against the displayed body.
    func renderMatches(model text: String) -> Bool { lastRendered == text }

    /// Banner progress for an escalated alias: (assigned so far, total mentions).
    func progress(for alias: String) -> (assigned: Int, total: Int)? {
        let k = alias.lowercased()
        guard isEscalated(k), let total = occTotals[k], total > 0 else { return nil }
        let assigned = (occDecisions[k] ?? [:]).keys.filter { (0..<total).contains($0) }.count
        return (min(assigned, total), total)
    }

    func setOccurrenceTotal(_ n: Int, for alias: String) { occTotals[alias.lowercased()] = n }

    func setChoice(alias: String, snapshotIndex: Int, choice: ResolverChoice) {
        occDecisions[alias.lowercased(), default: [:]][snapshotIndex] = choice
    }

    func clearDecisions(for alias: String) { occDecisions[alias.lowercased()] = nil }

    /// The snapshot occurrence index behind the k-th plain occurrence of `alias`
    /// in the rendered body (nil = no in-flight state / out of range / foreign).
    func snapshotIndex(alias: String, plainIndex k: Int) -> Int? {
        let key = alias.lowercased()
        guard snapshot != nil, k >= 0 else { return nil }
        if let slots = plainSlots[key] {
            guard k < slots.count, slots[k] >= 0 else { return nil }
            return slots[k]
        }
        // Escalated after the last render → untouched by it, so order maps 1:1.
        guard k < (occTotals[key] ?? 0) else { return nil }
        return k
    }

    /// The in-flight choice shown at the k-th plain occurrence of `alias` in the
    /// rendered body (order-based — the caller verifies `renderMatches` first).
    func choiceAtPlainIndex(alias: String, plainIndex k: Int) -> ResolverChoice? {
        guard let s = snapshotIndex(alias: alias, plainIndex: k) else { return nil }
        return occDecisions[alias.lowercased()]?[s]
    }

    /// Begin in-flight state on `body` (the first pick), or RE-BASE on it after a
    /// hand edit invalidated the previous render — previous choices are dropped
    /// (whatever they already rendered is part of `body` now).
    func beginPartial(body: String) {
        snapshot = body
        lastRendered = body
        occDecisions = [:]
        var slots: [String: [Int]] = [:]
        for key in escalated {
            let n = Sanitiser.plainOccurrences(of: display(key), in: body).count
            occTotals[key] = n
            slots[key] = Array(0..<n)   // identity: nothing rendered yet
        }
        plainSlots = slots
    }

    /// Re-base remaining in-flight choices onto a freshly COMMITTED body (another
    /// alias just resolved). Index-keyed choices survive position shifts; if an
    /// alias's occurrence count changed (pathological — the commit minted new
    /// text that reads as this alias), its choices are dropped for a clean restart.
    func rebase(snapshot newSnapshot: String) {
        let old = snapshot
        snapshot = newSnapshot
        for key in escalated {
            let newCount = Sanitiser.plainOccurrences(of: display(key), in: newSnapshot).count
            if let old, occDecisions[key]?.isEmpty == false,
               Sanitiser.plainOccurrences(of: display(key), in: old).count != newCount {
                occDecisions[key] = nil
            }
            occTotals[key] = newCount
        }
    }

    /// Record a partial render: the rendered text + the per-occurrence rendered
    /// ranges from `Sanitiser.applyPartialOccurrences`, folded into the
    /// plain-occurrence → snapshot-index slot map the marks/clicks use.
    func setRender(text: String, ranges: [String: [NSRange]]) {
        lastRendered = text
        var slots: [String: [Int]] = [:]
        for key in escalated {
            guard let emitted = ranges[key] else { continue }
            slots[key] = Sanitiser.plainSlotMap(alias: display(key), rendered: text, occurrenceRanges: emitted)
        }
        plainSlots = slots
    }

    /// Drop all in-flight state (after a commit with nothing left in flight, a
    /// restore, or a stale-state reset).
    func clearPartial() {
        snapshot = nil
        lastRendered = nil
        occDecisions = [:]
        plainSlots = [:]
    }

    /// True while `core` (a link's inner text) is a candidate of an alias with
    /// in-flight choices — such a `[[link]]` was rendered by the resolver and is
    /// NOT committed yet (it may still demote/move as more mentions are assigned),
    /// so the unlink popover must not offer it.
    func isInFlightCandidate(core: String) -> Bool {
        guard snapshot != nil else { return false }
        let key = NamesMerge.keyName(core).trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { return false }
        for (alias, d) in occDecisions where !d.isEmpty {
            guard isEscalated(alias) else { continue }
            if (candidatesByAlias[alias] ?? []).contains(where: {
                NamesMerge.keyName($0.canonical).trimmingCharacters(in: .whitespaces)
                    .caseInsensitiveCompare(key) == .orderedSame
            }) { return true }
        }
        return false
    }

    /// Drop a fully-resolved alias from the live state.
    func removeAlias(_ alias: String) {
        let k = alias.lowercased()
        candidatesByAlias[k] = nil
        displayAlias[k] = nil
        escalated.remove(k)
        occDecisions[k] = nil
        occTotals[k] = nil
        plainSlots[k] = nil
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
            if let p = model.progress(for: alias) {
                Text("\(p.assigned) of \(p.total) assigned")
                    .font(.system(size: 11))
                    .foregroundStyle(p.assigned > 0 ? Theme.accent : Theme.textMuted)
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(Theme.accent.opacity(p.assigned > 0 ? 0.10 : 0), in: Capsule())
                    .overlay(Capsule().stroke(Theme.accent.opacity(p.assigned > 0 ? 0.3 : 0.12), lineWidth: 0.5))
            }
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
