import SwiftUI
import SwiftData

/// The merged lifecycle shelf (mocks/lifecycle-ia-explorations.html #m3, Q4 locked
/// 2026-07-20): Fading + Recently Deleted collapse into ONE conveyor with ONE verb,
/// **Bring back** — absorbing `FadingShelfView` + `RecentlyDeletedView`. Reached from
/// the Notes header ⋯ (now a single item, not two).
///
/// Every countdown comes from `MemoSpine.oneLiner` (Shared, read-only) — nothing here
/// hand-writes a day count. "Bring back" carries the pinned cross-app semantics (same
/// on the Mac): it always sets `keptAt` (an explicit rescue is itself a touch — the
/// note must not re-fade the next second) and always clears `deletedAt` (a no-op for a
/// still-fading row, which never had one).
struct WayOutView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<Memo> { $0.deletedAt == nil },
           sort: \Memo.recordedAt, order: .forward) private var liveMemos: [Memo]
    @Query(filter: #Predicate<Memo> { $0.deletedAt != nil },
           sort: [SortDescriptor(\Memo.deletedAt, order: .forward)]) private var deletedMemos: [Memo]
    private let repository = NotesRepository.shared

    /// The memo a Delete-Now is pending confirmation for (deleted section only —
    /// the phone-owned destructive control the old trash screen had).
    @State private var confirmDelete: Memo?
    /// Row-tap peek (Mac parity, Tuur 2026-07-21): read the note before
    /// deciding to Bring back — a popup, not a push to the full editor.
    @State private var peek: Memo?

    private var fading: [Memo] {
        Self.orderedByImminence(fading: MemoLifecycle.partition(liveMemos).fading)
    }
    private var deleted: [Memo] { Self.orderedByImminence(deleted: deletedMemos) }
    private var total: Int { Self.total(fading: fading, deleted: deleted) }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.skBg.ignoresSafeArea()
                if total == 0 {
                    ContentUnavailableView(
                        "Nothing is fading",
                        systemImage: "leaf",
                        description: Text("Quiet notes start fading \(MemoLifecycle.fadeAfterDays) days after you last touch them.")
                    )
                    .accessibilityIdentifier("wayout-empty")
                } else {
                    list
                }
            }
            .navigationTitle("Fading · \(total)")
            .navigationBarTitleDisplayMode(.inline)
            // Opening the merged shelf clears the ⋯ dot — same stamp + key
            // FadingShelfView used (the dot's unread semantics are untouched).
            .onAppear { UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "fadingLastSeenAt") }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("wayout-done-button")
                }
            }
            .sheet(item: $peek) { memo in
                WayOutPeekSheet(memo: memo,
                                oneLiner: Self.oneLiner(for: memo),
                                isDeleted: memo.deletedAt != nil,
                                onBringBack: {
                                    Self.bringBack(memo, repository: repository)
                                    peek = nil
                                },
                                onDelete: {
                                    // Fading → soft (skip the rest of the fade,
                                    // straight to Recently Deleted, no confirm);
                                    // deleted → the phone-owned purge, through
                                    // the existing confirm dialog.
                                    if memo.deletedAt == nil {
                                        memo.deletedAt = Date()
                                        repository.save()
                                        peek = nil
                                    } else {
                                        peek = nil
                                        confirmDelete = memo
                                    }
                                })
            }
            .confirmationDialog(
                "Delete this note permanently? Its audio and photos will be gone for good.",
                isPresented: Binding(
                    get: { confirmDelete != nil },
                    set: { if !$0 { confirmDelete = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete Now", role: .destructive) {
                    if let memo = confirmDelete { repository.permanentlyDelete(memo) }
                    confirmDelete = nil
                }
                .accessibilityIdentifier("wayout-confirm-delete-button")
                Button("Cancel", role: .cancel) { confirmDelete = nil }
            }
        }
    }

    private var list: some View {
        List {
            Text("Quiet notes leave on their own when their clock runs out — Bring back rescues one at any point.")
                .font(.system(size: 11.5))
                .foregroundStyle(Color.skTextFaint)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .padding(.vertical, 4)

            if !fading.isEmpty {
                Section {
                    ForEach(fading) { memo in
                        WayOutRow(memo: memo, kind: .fading,
                                  bringBack: { Self.bringBack(memo, repository: repository) },
                                  onPeek: { peek = memo })
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                    }
                } header: {
                    SectionLabel("STILL VISIBLE")
                }
            }
            if !deleted.isEmpty {
                Section {
                    ForEach(deleted) { memo in
                        WayOutRow(memo: memo, kind: .deleted,
                                  bringBack: { Self.bringBack(memo, repository: repository) },
                                  onDeleteNow: { confirmDelete = memo },
                                  onPeek: { peek = memo })
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                    }
                } header: {
                    SectionLabel("RECENTLY DELETED")
                } footer: {
                    Text("Deleted notes are kept for \(TrashPolicy.retentionDays) days, then removed for good.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Color.skTextFaint)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .accessibilityIdentifier("wayout-list")
    }
}

// MARK: - Row

/// One row idiom for both sections (title, kind-specific meta, spine one-liner, ONE
/// verb). Deleted-kind rows additionally carry the phone-owned hard-delete control as
/// a swipe + context menu — a secondary destructive gesture, not a second button, so
/// the row still reads as one verb.
private struct WayOutRow: View {
    enum Kind { case fading, deleted }

    let memo: Memo
    let kind: Kind
    let bringBack: () -> Void
    var onDeleteNow: (() -> Void)? = nil
    var onPeek: () -> Void = {}

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(memo.displayTitle)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.skText)
                    .lineLimit(1)
                meta
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.skTextFaint)
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onPeek)
            Spacer(minLength: 8)
            // A fixed-width trailing column (not a flat HStack): the spine's
            // one-liners run noticeably longer than the old per-screen copy
            // ("moves to Recently Deleted in 29d" vs. old "fades in 29 days"),
            // so the countdown gets room to wrap to two lines above the button
            // instead of clipping or squeezing the title.
            VStack(alignment: .trailing, spacing: 6) {
                Text(WayOutView.oneLiner(for: memo))
                    .font(.system(size: 11))
                    .foregroundStyle(urgencyColor)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Bring back", action: bringBack)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(.skAccent)
                    .accessibilityIdentifier("wayout-row-bringback")
            }
            .frame(maxWidth: 140, alignment: .trailing)
        }
        .padding(.vertical, 2)
        .skCard()
        .modifier(DeleteNowActions(onDeleteNow: onDeleteNow))
    }

    @ViewBuilder private var meta: some View {
        switch kind {
        case .fading:
            HStack(spacing: 8) {
                Text(memo.recordedAt.formatted(date: .abbreviated, time: .omitted))
                if let place = memo.metadata?.location?.placeName, !place.isEmpty {
                    Text(place)
                }
            }
        case .deleted:
            if let deletedAt = memo.deletedAt {
                Text("deleted \(deletedAt.formatted(date: .abbreviated, time: .omitted))")
            }
        }
    }

    /// Red inside the countdown's last 3 days, amber otherwise — the same threshold
    /// FadingShelfView used, now shared by both sections (Don'ts: thresholds unchanged).
    private var urgencyColor: Color {
        let daysLeft: Int
        switch kind {
        case .fading: daysLeft = MemoLifecycle.daysUntilSweep(memo)
        case .deleted: daysLeft = memo.trashDaysRemaining() ?? 0
        }
        return daysLeft <= 3 ? Color.skRed : Color.skAmber
    }
}

/// Trailing swipe + context menu for "Delete Now" — deleted-section rows only. A
/// no-op passthrough when `onDeleteNow` is nil, so fading rows use the same row body.
private struct DeleteNowActions: ViewModifier {
    let onDeleteNow: (() -> Void)?

    func body(content: Content) -> some View {
        if let onDeleteNow {
            content
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive, action: onDeleteNow) {
                        Label("Delete Now", systemImage: "trash")
                    }
                    .accessibilityIdentifier("wayout-delete-now-button")
                }
                .contextMenu {
                    Button(role: .destructive, action: onDeleteNow) {
                        Label("Delete Now", systemImage: "trash")
                    }
                }
        } else {
            content
        }
    }
}

// MARK: - Pure helpers (no SwiftUI — testable directly; see WayOutViewTests)

extension WayOutView {
    /// "Bring back" — pinned cross-app semantics (identical on the Mac, BASE.md's
    /// cross-lane seam note): ALWAYS sets `keptAt` (even for a still-fading note — it
    /// must not re-fade the next second) and ALWAYS clears `deletedAt` (a no-op when
    /// the row was only fading, never deleted).
    @MainActor
    static func bringBack(_ memo: Memo, repository: NotesRepository) {
        memo.keptAt = Date()
        memo.deletedAt = nil
        repository.save()
    }

    /// Fading rows, soonest-to-move-to-Recently-Deleted first.
    static func orderedByImminence(fading: [Memo]) -> [Memo] {
        fading.sorted { MemoLifecycle.fadesAt($0) < MemoLifecycle.fadesAt($1) }
    }

    /// Deleted rows, soonest-to-be-purged-for-good first.
    static func orderedByImminence(deleted: [Memo]) -> [Memo] {
        deleted.sorted { ($0.deletedAt ?? .distantFuture) < ($1.deletedAt ?? .distantFuture) }
    }

    /// The merged shelf count shown in both the nav title and the ⋯ menu label.
    static func total(fading: [Memo], deleted: [Memo]) -> Int {
        fading.count + deleted.count
    }

    /// The spine's one-liner for a way-out row — "moves to Recently Deleted in Nd"
    /// while still visible, "gone for good in ~Nd" once deleted. `MemoSpine`'s chain
    /// picks the right branch on its own (`deletedAt` beats everything), so this is
    /// the ONE place either row kind reads its countdown from.
    static func oneLiner(for memo: Memo, now: Date = Date()) -> String {
        MemoSpine.oneLiner(for: MemoSpine.station(for: .from(memo, backlinked: []), now: now), now: now)
    }
}


// MARK: - Peek

/// Read-only popup for a conveyor row (Mac parity — the Mac's peek sheet with
/// Bring back inside): title, meta, the spine one-liner, the full body with
/// photos rendered at their `[[img_NNN]]` markers (m4/m6 2026-07-22 — the
/// marker used to print literally), and the verbs. Delete joins Bring back:
/// soft for a fading note, the confirm-gated purge for a deleted one — the
/// peek shouldn't lose a verb the row underneath has.
private struct WayOutPeekSheet: View {
    let memo: Memo
    let oneLiner: String
    let isDeleted: Bool
    let onBringBack: () -> Void
    let onDelete: () -> Void
    @Environment(\.dismiss) private var dismiss

    /// A displayable slice of the body: a text run or a resolved photo.
    private enum BodyRun: Identifiable {
        case text(id: Int, String)
        case photo(id: Int, UIImage)
        var id: Int {
            switch self {
            case .text(let id, _), .photo(let id, _): return id
            }
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.skBg.ignoresSafeArea()
                VStack(alignment: .leading, spacing: 10) {
                    Text(memo.displayTitle)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Color.skText)
                        .lineLimit(2)
                    HStack(spacing: 10) {
                        Text(memo.recordedAt.formatted(date: .abbreviated, time: .omitted))
                        if let place = memo.metadata?.location?.placeName { Text(place) }
                        if memo.duration > 0 { Text(Duration.seconds(memo.duration).formatted(.time(pattern: .minuteSecond))) }
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(Color.skTextFaint)
                    Text(oneLiner)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.skAmber)
                    ScrollView {
                        bodyView
                    }
                    Button(action: onBringBack) {
                        Text("Bring back")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.skAccent)
                    .accessibilityIdentifier("wayout-peek-bringback")
                    Button(action: onDelete) {
                        Text(isDeleted ? "Delete now" : "Delete")
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(Color.skRed)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 9)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("wayout-peek-delete")
                }
                .padding(16)
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder private var bodyView: some View {
        let runs = bodyRuns()
        VStack(alignment: .leading, spacing: 10) {
            ForEach(runs) { run in
                switch run {
                case .text(_, let str):
                    Text(str)
                        .font(.system(size: 14.5))
                        .foregroundStyle(Color.skTextDim)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                case .photo(_, let image):
                    Image(uiImage: image)
                        .resizable().aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 160)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if runs.isEmpty {
                Text("No transcript.")
                    .font(.system(size: 14.5))
                    .foregroundStyle(Color.skTextDim)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// Split the raw transcript into text/photo runs — marker `[[img_NNN]]`
    /// resolves through the manifest to its on-disk file (`Memo.imageURL`,
    /// the same rule every transcript renderer uses). Unresolvable markers
    /// are dropped, never printed.
    private func bodyRuns() -> [BodyRun] {
        let raw = memo.transcript ?? ""
        guard !raw.isEmpty else { return [] }
        let ns = raw as NSString
        var out: [BodyRun] = []
        var textBuffer = ""
        func flushText() {
            let trimmed = textBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { out.append(.text(id: out.count, trimmed)) }
            textBuffer = ""
        }
        for piece in BodyTransform.pieces(of: raw) {
            switch piece.segment {
            case .text(let str):
                textBuffer += str
            case .image(let n):
                if let url = memo.imageURL(markerIndex: n),
                   let image = UIImage(contentsOfFile: url.path) {
                    flushText()
                    out.append(.photo(id: out.count, image))
                }
            case .task, .memoLink:
                textBuffer += ns.substring(with: piece.rawRange)
            }
        }
        flushText()
        return out
    }
}
