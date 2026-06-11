import SwiftUI
import SwiftData
import UIKit

enum MemoSort: String, CaseIterable, Identifiable {
    case recent = "Most recent"
    case oldest = "Oldest first"
    case longest = "Longest first"
    var id: String { rawValue }
}

struct MemoFilter: Equatable {
    var unsyncedOnly = false
    var hasPhotosOnly = false
    var place: String?
    var isActive: Bool { unsyncedOnly || hasPhotosOnly || place != nil }
}

/// The memos surface (mockup3): full-text search, day-group cards with honest
/// status pills, multi-select, a single funnel = Sort & Filter sheet, and the
/// record FAB. Tapping a card opens Memo detail; the FAB opens the recorder
/// (which on Stop pushes detail — the save-now flow).
struct MemosListView: View {
    // Trashed memos (deletedAt != nil) are excluded here and live in the
    // Recently Deleted screen until restored or purged.
    @Query(filter: #Predicate<Memo> { $0.deletedAt == nil },
           sort: \Memo.recordedAt, order: .reverse) private var memos: [Memo]
    @Query(filter: #Predicate<Memo> { $0.deletedAt != nil }) private var trashedMemos: [Memo]
    @Environment(\.modelContext) private var context
    private let repository = NotesRepository.shared

    @State private var path: [UUID] = []
    @State private var showRecord = false
    @State private var lastHandledStart = 0
    @ObservedObject private var intentBridge = RecordingIntentBridge.shared
    @State private var showSettings = false
    @State private var showSortFilter = false
    @State private var showTrash = false
    @State private var search = ""
    @State private var sort: MemoSort = .recent
    @State private var filter = MemoFilter()
    @State private var editMode: EditMode = .inactive
    @State private var selected: Set<UUID> = []
    @State private var syncing = false
    @State private var syncBanner: String?
    @State private var bannerToken = 0

    var body: some View {
        NavigationStack(path: $path) {
            ZStack(alignment: .bottom) {
                Color.skBg.ignoresSafeArea()

                if memos.isEmpty {
                    emptyState
                } else {
                    listContent
                }

                if editMode.isEditing {
                    selectionBar
                } else {
                    recordFAB
                }
            }
            .overlay(alignment: .top) { syncBannerView }
            .animation(Theme.Motion.spring, value: syncBanner)
            .navigationTitle("Memos")
            .toolbar { toolbarContent }
            .navigationDestination(for: UUID.self) { MemoDetailView(initialID: $0) }
            .fullScreenCover(isPresented: $showRecord) {
                RecordView(onSaved: { newID in path = [newID] })
            }
            .onChange(of: intentBridge.startRequestID) { handleStartRequest() }
            // Also catch a request that fired during a COLD launch (App Intent /
            // widget / deep link) BEFORE this view subscribed — onChange alone
            // misses it, which left Siri/widget "opens but doesn't record".
            .onAppear { handleStartRequest() }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .sheet(isPresented: $showSortFilter) {
                SortFilterSheet(sort: $sort, filter: $filter, places: availablePlaces)
            }
            // A sheet (like Settings) rather than a push: the stack's path is
            // typed [UUID] for memo detail, which a non-memo destination can't
            // join.
            .sheet(isPresented: $showTrash) { RecentlyDeletedView() }
        }
    }

    // MARK: - Content

    private var listContent: some View {
        VStack(spacing: 0) {
            SearchField(text: $search, prompt: "Search transcripts", fieldID: "memo-search")
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 6)

            // Native List → reliable swipe-to-delete (.swipeActions) + native
            // multi-select (EditMode + selection binding, incl. drag-over-rows).
            // Plain style + cleared backgrounds keep the custom card look.
            List(selection: $selected) {
                ForEach(groups, id: \.title) { group in
                    Section {
                        ForEach(group.memos) { memo in
                            MemoRow(memo: memo) { path.append(memo.id) }
                                .tag(memo.id)
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                                .accessibilityIdentifier("memo-row-\(flatIndex[memo.id] ?? 0)")
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) { deleteMemo(memo) } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                    .accessibilityIdentifier("swipe-delete-button")
                                }
                                // Quick copy without opening the memo (today: open → ⋯ →
                                // Copy). Leading edge so Delete keeps the trailing edge +
                                // full swipe to itself.
                                .swipeActions(edge: .leading) {
                                    Button { copyTranscript(memo) } label: {
                                        Label("Copy", systemImage: "doc.on.doc")
                                    }
                                    .tint(.skAccent)
                                    .accessibilityIdentifier("swipe-copy-button")
                                }
                                .contextMenu {
                                    // Second path to the same actions; empty while
                                    // selecting so long-press can't fight multi-select.
                                    if !editMode.isEditing {
                                        Button { copyTranscript(memo) } label: {
                                            Label("Copy transcript", systemImage: "doc.on.doc")
                                        }
                                        .accessibilityIdentifier("context-copy-button")
                                        Button(role: .destructive) { deleteMemo(memo) } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                                }
                        }
                    } header: {
                        Text(group.title.uppercased())
                            .font(.system(size: 11.5, weight: .bold))
                            .kerning(0.5)
                            .foregroundStyle(Color.skTextDim)
                    }
                }
                if groups.isEmpty {
                    Text("No matches")
                        .font(.subheadline)
                        .foregroundStyle(Color.skTextDim)
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .padding(.top, 60)
                }
                // Trash entry point, Voice Memos-style: a quiet footer row that
                // only exists while the trash is non-empty. Hidden during
                // multi-select so it can't collect a selection circle.
                if !trashedMemos.isEmpty && !editMode.isEditing {
                    recentlyDeletedRow
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                }
                Color.clear.frame(height: 80)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .environment(\.editMode, $editMode)
            .accessibilityIdentifier("memos-list")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 0) {
            ContentUnavailableView(
                "No memos yet",
                systemImage: "waveform",
                description: Text("Tap the mic to record your first memo.")
            )
            .accessibilityIdentifier("memos-empty")
            // The trash must stay reachable when the main list is empty (e.g.
            // everything was just deleted) — otherwise Restore is unreachable.
            if !trashedMemos.isEmpty {
                recentlyDeletedRow
                    .padding(.horizontal, 16)
                    .padding(.bottom, 110)   // clear the record FAB
            }
        }
    }

    /// "Recently Deleted (N)" card row → the trash screen.
    private var recentlyDeletedRow: some View {
        Button { showTrash = true } label: {
            HStack(spacing: 10) {
                Image(systemName: "trash")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.skTextDim)
                Text("Recently Deleted")
                    .font(.system(size: 14.5, weight: .medium))
                    .foregroundStyle(Color.skText)
                Spacer()
                Text("\(trashedMemos.count)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.skTextDim)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.skTextFaint)
            }
            .skCard()
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("recently-deleted-row")
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button(editMode.isEditing ? "Done" : "Select") {
                withAnimation(Theme.Motion.snappy) {
                    if editMode.isEditing { editMode = .inactive; selected.removeAll() }
                    else { editMode = .active }
                }
            }
            .accessibilityIdentifier("select-button")
        }
        if !editMode.isEditing {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showSettings = true } label: { Image(systemName: "gearshape") }
                    .accessibilityIdentifier("settings-button")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: runSync) {
                    if syncing {
                        ProgressView().controlSize(.small).tint(.skAccent)
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                }
                .disabled(syncing)
                .accessibilityIdentifier("sync-button")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showSortFilter = true } label: {
                    Image(systemName: filter.isActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease")
                }
                .accessibilityIdentifier("sort-filter-button")
            }
        }
    }

    // MARK: - Bottom bars

    @ViewBuilder private var syncBannerView: some View {
        if let syncBanner {
            Text(syncBanner)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.skText)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Color.skElev, in: .capsule)
                .overlay(Capsule().stroke(Color.skBorder, lineWidth: 1))
                .padding(.top, 6)
                .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private func runSync() {
        guard !syncing else { return }
        Task {
            syncing = true
            let synced = await SyncCoordinator().syncAll()
            syncing = false
            let paired = MacConnection.load() != nil
            // Distinguish a real failure (memos still waiting) from "nothing to do".
            let stillWaiting = repository.allMemos().contains { $0.syncStatus == .waiting && $0.audioURL != nil }
            if !paired {
                flashBanner("Pair a Mac in Settings to sync")
            } else if synced > 0 {
                flashBanner("Synced \(synced) memo\(synced == 1 ? "" : "s")")
            } else if stillWaiting {
                flashBanner("Couldn't reach the Mac")
            } else {
                flashBanner("Up to date")
            }
        }
    }

    /// Show the top banner briefly. The token keeps an earlier banner's expiry
    /// from clipping a newer one.
    private func flashBanner(_ text: String) {
        bannerToken += 1
        let token = bannerToken
        syncBanner = text
        Task {
            try? await Task.sleep(for: .seconds(2.2))
            if bannerToken == token { syncBanner = nil }
        }
    }

    /// Present the recorder + auto-start for a Record intent / widget / deep link.
    /// `lastHandledStart` makes it fire once per request and catches a request that
    /// arrived during a cold launch before `.onChange` was subscribed.
    private func handleStartRequest() {
        guard intentBridge.startRequestID > lastHandledStart else { return }
        lastHandledStart = intentBridge.startRequestID
        // Just present — RecordView consumes the bridge's pending start once it's
        // foreground-active (no stale-flag propagation through the cover).
        showRecord = true
    }

    private var recordFAB: some View {
        Button { intentBridge.clearPendingStart(); showRecord = true } label: {
            Image(systemName: "mic.fill")
                .font(.system(size: 24))
                .foregroundStyle(.white)
                .frame(width: 64, height: 64)
                .background(Color.skRed, in: .circle)
                .overlay(Circle().stroke(.white.opacity(0.12), lineWidth: 4))
                .shadow(color: .skRed.opacity(0.45), radius: 12, y: 8)
        }
        .accessibilityIdentifier("new-recording-button")
        .padding(.bottom, 26)
    }

    private var selectionBar: some View {
        HStack {
            Text("\(selected.count) selected").font(.subheadline.weight(.semibold)).foregroundStyle(Color.skTextDim)
            Spacer()
            Button(role: .destructive, action: deleteSelected) {
                Label("Delete", systemImage: "trash")
            }
            .disabled(selected.isEmpty)
            .accessibilityIdentifier("delete-selected-button")
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
        .background(.ultraThinMaterial)
        .clipShape(.rect(topLeadingRadius: 20, topTrailingRadius: 20))
    }

    // MARK: - Actions

    private func deleteSelected() {
        for id in selected {
            guard let memo = memos.first(where: { $0.id == id }) else { continue }
            deleteMemo(memo)
        }
        selected.removeAll()
        editMode = .inactive
    }

    /// Quick copy straight from the list: transcript (fallback: title) → pasteboard,
    /// with a light haptic + the same top banner as sync. An empty memo says so
    /// instead of silently copying nothing.
    private func copyTranscript(_ memo: Memo) {
        guard let text = memo.copyableText else {
            flashBanner("Nothing to copy yet")
            return
        }
        UIPasteboard.general.string = text
        Haptics.tap(.light)
        flashBanner("Copied")
    }

    /// Soft-delete: move the memo to Recently Deleted (audio + sidecars stay on
    /// disk so Restore is lossless; purged for good after ~2 weeks at startup).
    /// Shared by multi-select delete, swipe-to-delete, and the context menu.
    private func deleteMemo(_ memo: Memo) {
        repository.softDelete(memo)
    }

    // MARK: - Derived

    private var filtered: [Memo] {
        memos.filter { matchesSearch($0) && matchesFilter($0) }.sorted(by: sortComparator)
    }

    private var flatIndex: [UUID: Int] {
        Dictionary(uniqueKeysWithValues: filtered.enumerated().map { ($0.element.id, $0.offset) })
    }

    private struct Group { let title: String; let memos: [Memo] }

    private var groups: [Group] {
        if sort == .longest {
            return filtered.isEmpty ? [] : [Group(title: "Longest first", memos: filtered)]
        }
        var order: [String] = []
        var bucket: [String: [Memo]] = [:]
        for memo in filtered {
            let key = MemoDate.group(memo.recordedAt)
            if bucket[key] == nil { order.append(key); bucket[key] = [] }
            bucket[key]?.append(memo)
        }
        return order.map { Group(title: $0, memos: bucket[$0] ?? []) }
    }

    private var availablePlaces: [String] {
        Array(Set(memos.compactMap { $0.metadata?.location?.placeName }.filter { !$0.isEmpty })).sorted()
    }

    private func matchesSearch(_ memo: Memo) -> Bool {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return true }
        if memo.transcript?.lowercased().contains(q) == true { return true }
        if memo.tags.contains(where: { $0.lowercased().contains(q) }) { return true }
        if memo.metadata?.location?.placeName?.lowercased().contains(q) == true { return true }
        return false
    }

    private func matchesFilter(_ memo: Memo) -> Bool {
        if filter.unsyncedOnly && memo.syncStatus == .synced { return false }
        if filter.hasPhotosOnly && (memo.metadata?.imageManifest?.isEmpty ?? true) { return false }
        if let place = filter.place, memo.metadata?.location?.placeName != place { return false }
        return true
    }

    private func sortComparator(_ a: Memo, _ b: Memo) -> Bool {
        switch sort {
        case .recent: return a.recordedAt > b.recordedAt
        case .oldest: return a.recordedAt < b.recordedAt
        case .longest: return a.duration > b.duration
        }
    }
}

// MARK: - Row

/// A memo row: taps open detail in normal mode; in EditMode the tap is left to the
/// List so its native multi-select (incl. drag-over-rows) and selection circle work.
/// Conditionally attaching the tap (rather than guarding inside it) is what frees the
/// tap for List selection — a no-op gesture would still swallow it. No NavigationLink,
/// so no disclosure chevron over the card.
private struct MemoRow: View {
    let memo: Memo
    let onTap: () -> Void
    @Environment(\.editMode) private var editMode

    var body: some View {
        if editMode?.wrappedValue.isEditing == true {
            MemoCard(memo: memo)
        } else {
            MemoCard(memo: memo)
                .contentShape(Rectangle())
                .onTapGesture(perform: onTap)
        }
    }
}

// MARK: - Card

private struct MemoCard: View {
    let memo: Memo

    var body: some View {
        HStack(spacing: 11) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(MemoDate.label(memo.recordedAt))
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(Color.skTextFaint)
                    Spacer()
                    statusPill
                }

                // Titled memos lead with the user-set title; the transcript snippet
                // drops to a dimmer second line. Untitled memos keep the
                // transcript-first behaviour.
                if hasTitle {
                    Text(memo.displayTitle)
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundStyle(Color.skText)
                        .lineLimit(1)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 6)

                    if let secondary = transcriptSnippet {
                        Text(secondary)
                            .font(.system(size: 12.5, weight: .regular))
                            .foregroundStyle(Color.skTextDim)
                            .lineLimit(1)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 2)
                    }
                } else {
                    Text(snippet)
                        .font(.system(size: 14.5, weight: .medium))
                        .foregroundStyle(hasTranscript ? Color.skText : Color.skTextFaint)
                        .italic(!hasTranscript)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 6)
                }

                FlowLayout(spacing: 5, lineSpacing: 5) {
                    ForEach(chips, id: \.self) { chip in
                        ContextChip(text: chip.text, systemImage: chip.symbol)
                    }
                    ForEach(memo.tags.prefix(2), id: \.self) { tag in
                        Text("#\(tag)")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.skAccentText)
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Color.skAccentSoft, in: .rect(cornerRadius: 7, style: .continuous))
                    }
                }
                .padding(.top, 9)
            }

            if hasPhoto {
                RoundedRectangle.sk(11)
                    .fill(LinearGradient(colors: [Color(hex: 0x2b3350), Color(hex: 0x1a1f33)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 48, height: 48)
                    .overlay(photoThumb)
                    .overlay(RoundedRectangle.sk(11).stroke(Color.skBorder, lineWidth: 1))
            }
        }
        .skCard()
    }

    // A failed on-device transcription is informational, not a dead end: the memo
    // syncs as raw audio (the Mac transcribes it) and can be hand-edited in detail.
    // `statusKind` is nil for phone-only (significance 0) memos → no sync pill.
    @ViewBuilder private var statusPill: some View {
        if let kind = memo.statusKind {
            StatusPill(style: kind.pillStyle, label: kind.label)
        }
    }

    @ViewBuilder private var photoThumb: some View {
        if let first = memo.metadata?.imageManifest?.first,
           let img = UIImage(contentsOfFile: AppPaths.recordingsDirectory.appendingPathComponent(first.filename).path) {
            Image(uiImage: img).resizable().scaledToFill()
                .frame(width: 48, height: 48)
                .clipShape(.rect(cornerRadius: 11, style: .continuous))
        } else {
            Image(systemName: "photo").font(.system(size: 16)).foregroundStyle(Color.skTextFaint)
        }
    }

    private struct Chip: Hashable { let text: String; let symbol: String? }

    private var chips: [Chip] {
        var out = [Chip(text: memo.durationLabel, symbol: nil)]
        if let place = memo.metadata?.location?.placeName, !place.isEmpty {
            out.append(Chip(text: place, symbol: "mappin.circle.fill"))
        }
        if let w = memo.metadata?.weather { out.append(Chip(text: "\(w.temperature)°", symbol: "cloud.sun.fill")) }
        return out
    }

    private var hasTranscript: Bool { !(memo.transcript ?? "").isEmpty }
    private var hasPhoto: Bool { !(memo.metadata?.imageManifest?.isEmpty ?? true) }
    /// True when the user gave the memo an explicit (non-blank) title.
    private var hasTitle: Bool {
        !(memo.title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }
    private var snippet: String {
        if let line = memo.firstTranscriptLine { return memo.transcript ?? line }
        return "Voice memo"
    }
    /// Secondary line for titled rows: the transcript's first line, markers stripped.
    /// Nil when there's no transcript yet (the title alone carries the row).
    private var transcriptSnippet: String? { memo.firstTranscriptLine }
}

// MARK: - Quick copy

extension Memo {
    /// What a quick "Copy" copies: the transcript when there is one, else the
    /// title; nil when the memo has neither (not yet transcribed, untitled).
    var copyableText: String? {
        if let t = transcript, !t.isEmpty { return t }
        if let t = title, !t.isEmpty { return t }
        return nil
    }
}

// MARK: - Sort & Filter sheet

private struct SortFilterSheet: View {
    @Binding var sort: MemoSort
    @Binding var filter: MemoFilter
    let places: [String]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Sort") {
                    Picker("Sort", selection: $sort) {
                        ForEach(MemoSort.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                Section("Filter") {
                    Toggle("Unsynced only", isOn: $filter.unsyncedOnly)
                        .accessibilityIdentifier("filter-unsynced")
                    Toggle("Has photos", isOn: $filter.hasPhotosOnly)
                    if !places.isEmpty {
                        Picker("Place", selection: $filter.place) {
                            Text("Any").tag(String?.none)
                            ForEach(places, id: \.self) { Text($0).tag(String?.some($0)) }
                        }
                    }
                }
                if filter.isActive {
                    Button("Clear filters", role: .destructive) { filter = MemoFilter() }
                }
            }
            .navigationTitle("Sort & Filter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.accessibilityIdentifier("sortfilter-done")
                }
            }
        }
        .presentationDetents([.medium])
    }
}
