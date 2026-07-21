import SwiftUI

/// "On its way out" — the ONE conveyor (Q4, mocks/lifecycle-ia-explorations.html
/// #m3), replacing BOTH the old `FadingShelfColumn` and `MacTrashColumn`: the
/// fade → trash → purge pipeline is one journey, not two shelves with two verbs
/// that both meant "bring back". A pure body (data + action closures, no
/// ModelContext — the `ConnectionsPanelBody`/`ConnectionsPanel` split): the
/// caller (`JournalView`, or a `Snapshot` fixture) supplies the arrays and
/// wires the closures to whichever store each mutation actually belongs to.
struct WayOutColumn: View {
    /// Untouched notes past `fadeAfterDays`, still visible elsewhere, counting
    /// down to the auto-move (`MemoLifecycle.partition(_:).fading`).
    let fading: [Memo]
    /// Memos with `deletedAt` set — the memo trash.
    let deleted: [Memo]
    /// The transitional tail (Q5): trashed Mac-local uploads with no backing
    /// Memo. Empty once step ⑤ ships `MacMemoAuthor` and backfills the rest.
    let macOnlyFiles: [PipelineFile]
    /// keptAt + deletedAt=nil already applied by the caller's own predicate
    /// hook — this just fires after the row's tap.
    var onBringBack: (Memo) -> Void = { _ in }
    var onRestoreMacLocal: (PipelineFile) -> Void = { _ in }
    var onDeleteMacLocal: (PipelineFile) -> Void = { _ in }
    var onBack: () -> Void = {}
    /// Fired after the peek sheet's own Bring back write — the caller refreshes
    /// its arrays (the row buttons refresh via their own callbacks).
    var onChanged: () -> Void = {}

    @State private var confirmDeleteMacLocal: PipelineFile?

    private var total: Int { fading.count + deleted.count + macOnlyFiles.count }
    private var orderedMacOnly: [PipelineFile] {
        macOnlyFiles.sorted { ($0.deletedAt ?? .distantPast) < ($1.deletedAt ?? .distantPast) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if total == 0 {
                Text("Nothing is on its way out.")
                    .font(.system(size: 12)).foregroundStyle(Theme.textMuted)
            } else {
                Text("Everything leaving, on one line, soonest first. Untouched notes drift here on their own; Bring back rescues from any point of the journey.")
                    .font(.system(size: 11.5)).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if !fading.isEmpty {
                        section("Still visible → moving to Recently Deleted") {
                            ForEach(WayOutRules.fadingOrdered(fading), id: \.persistentModelID) { memo in
                                memoRow(memo)
                            }
                        }
                    }
                    if !deleted.isEmpty {
                        section("In Recently Deleted → gone for good") {
                            ForEach(WayOutRules.deletedOrdered(deleted), id: \.persistentModelID) { memo in
                                memoRow(memo)
                            }
                        }
                    }
                    if !macOnlyFiles.isEmpty {
                        section("Mac-only files") {
                            VStack(alignment: .leading, spacing: 9) {
                                ForEach(orderedMacOnly, id: \.id) { pf in macRow(pf) }
                                Text("Uploaded on this Mac before captures synced.")
                                    .font(.system(size: 10.5)).foregroundStyle(Theme.textMuted)
                            }
                        }
                    }
                }
            }
            Text("Automatic: each note moves along on its day. Bring back = never fades again. Your iPhone does the permanent deleting.")
                .font(.system(size: 11)).foregroundStyle(Theme.textMuted)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 24).padding(.horizontal, 30)
        // Centered reading column, same feel as the Looking-back river (Tuur's
        // 2026-07-21 round: rows hugged the left with dead space right).
        .frame(maxWidth: 820, alignment: .leading)
        .frame(maxWidth: .infinity)
        .alert("Delete permanently?",
               isPresented: Binding(get: { confirmDeleteMacLocal != nil }, set: { if !$0 { confirmDeleteMacLocal = nil } })) {
            Button("Delete Now", role: .destructive) {
                if let pf = confirmDeleteMacLocal { onDeleteMacLocal(pf) }
                confirmDeleteMacLocal = nil
            }
            Button("Cancel", role: .cancel) { confirmDeleteMacLocal = nil }
        } message: {
            Text("This removes the note and its audio from disk. This can’t be undone.")
        }
        .sheet(item: $peek) { target in
            UnpipelinedMemoSheet(memoID: target.id, action: .bringBack,
                                 onClose: { peek = nil },
                                 onProcessed: { _ in peek = nil; onChanged() })
        }
        .accessibilityIdentifier("wayout.root")
    }

    private var header: some View {
        HStack {
            Text("On its way out · \(total)").font(.system(size: 17, weight: .bold))
            Spacer()
            backCapsule(action: onBack)
        }
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold)).tracking(0.4).foregroundStyle(Theme.textMuted)
            content()
        }
    }

    // ── Fading / Deleted rows (Memo-backed, cloud) ───────────────────────

    @State private var peek: WayOutPeek?

    private func memoRow(_ memo: Memo) -> some View {
        let station = MemoSpine.station(for: .from(memo, backlinked: []))
        return HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(WayOutRules.displayTitle(memo))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary).lineLimit(1)
                HStack(spacing: 10) {
                    Text(memo.recordedAt.formatted(date: .abbreviated, time: .omitted))
                    if let place = memo.metadata?.location?.placeName { Text(place) }
                    if memo.duration > 0 { Text(SkriftFormat.clock(memo.duration)) }
                }
                .font(.system(size: 10.5)).foregroundStyle(Theme.textMuted)
            }
            Spacer(minLength: 8)
            Text(MemoSpine.oneLiner(for: station))
                .font(.system(size: 10.5))
                .foregroundStyle(urgencyColor(station))
            capsuleButton("Bring back", prominent: false) { onBringBack(memo) }
                .accessibilityIdentifier("wayout-row-bringback")
        }
        .padding(.horizontal, 16).padding(.vertical, 11)
        .contentShape(Rectangle())
        // Peek before you rescue (Tuur, 2026-07-21): the row opens read-only;
        // the buttons keep their own taps.
        .onTapGesture { peek = WayOutPeek(id: memo.id.uuidString) }
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.hairline.opacity(0.07), lineWidth: 1))
        .frame(maxWidth: 760, alignment: .leading)
    }

    /// Warm colors carry the same urgency reading as the old shelves (never
    /// reintroduced as new doctrine, just preserved): Fading stays amber until
    /// ≤3 days out, then red; Deleted stays muted until ≤3 days out, then red.
    private func urgencyColor(_ station: MemoSpine.Station) -> Color {
        switch station {
        case .fading(let deletedAt):
            let days = Int(ceil(deletedAt.timeIntervalSinceNow / 86_400))
            return days <= 3 ? Theme.destructive : Theme.amber
        case .deleted(let goneAt):
            let days = Int(ceil(goneAt.timeIntervalSinceNow / 86_400))
            return days <= 3 ? Theme.destructive : Theme.textMuted
        default:
            return Theme.textMuted
        }
    }

    // ── Mac-only tail (PipelineFile-backed, local) ───────────────────────

    private func macRow(_ pf: PipelineFile) -> some View {
        let days = pf.trashDaysRemaining()
        return HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(pf.displayTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary).lineLimit(1)
                Text(days == 0 ? "Removed today" : "\(days) day\(days == 1 ? "" : "s") left")
                    .font(.system(size: 10.5)).foregroundStyle(Theme.textMuted)
            }
            Spacer(minLength: 8)
            capsuleButton("Restore", prominent: false) { onRestoreMacLocal(pf) }
                .accessibilityIdentifier("wayout-maclocal-restore")
            Button { confirmDeleteMacLocal = pf } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11)).foregroundStyle(Theme.destructive)
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(Theme.destructive.opacity(0.14), in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16).padding(.vertical, 11)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.hairline.opacity(0.07), lineWidth: 1))
        .frame(maxWidth: 760, alignment: .leading)
    }
}

/// Sheet target for the row peek (Identifiable string id).
struct WayOutPeek: Identifiable { let id: String }

/// The clear column-back affordance (Tuur, 2026-07-21: the tiny top-right
/// "✕ Back" was easy to miss) — a real capsule with a leading chevron, shared
/// by the conveyor and the Places map.
@ViewBuilder
func backCapsule(action: @escaping () -> Void) -> some View {
    Button(action: action) {
        HStack(spacing: 5) {
            Image(systemName: "chevron.left").font(.system(size: 10, weight: .bold))
            Text("Back").font(.system(size: 11.5, weight: .semibold))
        }
        .foregroundStyle(Theme.accent)
        .padding(.horizontal, 12).padding(.vertical, 5)
        .background(Theme.accent.opacity(0.12), in: Capsule())
        .contentShape(Capsule())
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("column-back")
}

/// hostPNG-safe capsule button (system button styles render wrong offscreen —
/// memory `project_connections_panel`). Moved here from the retired
/// FadingShelfColumn.swift; used by WayOutColumn's row actions and by
/// SidebarView's band + UnpipelinedMemoSheet's Process capsule.
@ViewBuilder
func capsuleButton(_ title: String, prominent: Bool, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(prominent ? .white : Theme.accent)
            .padding(.horizontal, 12).padding(.vertical, 5)
            .background(prominent ? Theme.accent : Theme.accent.opacity(0.12), in: Capsule())
    }
    .buttonStyle(.plain)
}
