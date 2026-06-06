import SwiftUI
import SwiftData

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
    @Query(sort: \Memo.recordedAt, order: .reverse) private var memos: [Memo]
    @Environment(\.modelContext) private var context
    private let repository = NotesRepository.shared

    @State private var path: [UUID] = []
    @State private var showRecord = false
    @State private var showSettings = false
    @State private var showSortFilter = false
    @State private var search = ""
    @State private var sort: MemoSort = .recent
    @State private var filter = MemoFilter()
    @State private var selecting = false
    @State private var selected: Set<UUID> = []

    var body: some View {
        NavigationStack(path: $path) {
            ZStack(alignment: .bottom) {
                Color.skBg.ignoresSafeArea()

                if memos.isEmpty {
                    emptyState
                } else {
                    listContent
                }

                if selecting {
                    selectionBar
                } else {
                    recordFAB
                }
            }
            .navigationTitle("Memos")
            .toolbar { toolbarContent }
            .navigationDestination(for: UUID.self) { MemoDetailView(initialID: $0) }
            .fullScreenCover(isPresented: $showRecord) {
                RecordView(onSaved: { newID in path = [newID] })
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .sheet(isPresented: $showSortFilter) {
                SortFilterSheet(sort: $sort, filter: $filter, places: availablePlaces)
            }
        }
    }

    // MARK: - Content

    private var listContent: some View {
        ScrollView {
            SearchField(text: $search, prompt: "Search transcripts", fieldID: "memo-search")
                .padding(.horizontal, 16)
                .padding(.top, 4)

            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(groups, id: \.title) { group in
                    Text(group.title.uppercased())
                        .font(.system(size: 11.5, weight: .bold))
                        .kerning(0.5)
                        .foregroundStyle(Color.skTextDim)
                        .padding(.horizontal, 20)
                        .padding(.top, 16).padding(.bottom, 7)

                    ForEach(group.memos) { memo in
                        MemoCard(
                            memo: memo,
                            selecting: selecting,
                            isSelected: selected.contains(memo.id),
                            onRetry: { MemoSaver().retranscribe(id: memo.id) }
                        )
                        .padding(.horizontal, 16)
                        .padding(.bottom, 10)
                        .contentShape(Rectangle())
                        .onTapGesture { tap(memo) }
                        .accessibilityIdentifier("memo-row-\(flatIndex[memo.id] ?? 0)")
                    }
                }
                if groups.isEmpty {
                    Text("No matches")
                        .font(.subheadline)
                        .foregroundStyle(Color.skTextDim)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                }
                Color.clear.frame(height: 96)
            }
        }
        .accessibilityIdentifier("memos-list")
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "No memos yet",
            systemImage: "waveform",
            description: Text("Tap the mic to record your first memo.")
        )
        .accessibilityIdentifier("memos-empty")
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button(selecting ? "Done" : "Select") {
                withAnimation(Theme.Motion.snappy) {
                    selecting.toggle()
                    if !selecting { selected.removeAll() }
                }
            }
            .accessibilityIdentifier("select-button")
        }
        if !selecting {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showSettings = true } label: { Image(systemName: "gearshape") }
                    .accessibilityIdentifier("settings-button")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { Task { await SyncCoordinator().syncAll() } } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                }
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

    private var recordFAB: some View {
        Button { showRecord = true } label: {
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

    private func tap(_ memo: Memo) {
        if selecting {
            if selected.contains(memo.id) { selected.remove(memo.id) } else { selected.insert(memo.id) }
        } else {
            path.append(memo.id)
        }
    }

    private func deleteSelected() {
        for id in selected {
            guard let memo = memos.first(where: { $0.id == id }) else { continue }
            if let url = memo.audioURL { try? FileManager.default.removeItem(at: url) }
            memo.metadata?.imageManifest?.forEach {
                try? FileManager.default.removeItem(at: AppPaths.recordingsDirectory.appendingPathComponent($0.filename))
            }
            WordTimingsStore().delete(for: id)
            repository.delete(memo)
        }
        selected.removeAll()
        selecting = false
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

// MARK: - Card

private struct MemoCard: View {
    let memo: Memo
    let selecting: Bool
    let isSelected: Bool
    let onRetry: () -> Void

    var body: some View {
        HStack(spacing: 11) {
            if selecting {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(isSelected ? Color.skAccent : Color.skTextFaint)
            }

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(MemoDate.label(memo.recordedAt))
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(Color.skTextFaint)
                    Spacer()
                    statusPill
                }

                Text(snippet)
                    .font(.system(size: 14.5, weight: .medium))
                    .foregroundStyle(hasTranscript ? Color.skText : Color.skTextFaint)
                    .italic(!hasTranscript)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 6)

                FlowLayout(spacing: 5, lineSpacing: 5) {
                    ForEach(chips, id: \.self) { chip in
                        ContextChip(text: chip.text, systemImage: chip.symbol)
                    }
                    ForEach(memo.tags.prefix(2), id: \.self) { tag in
                        Text("#\(tag)")
                            .font(.system(size: 11))
                            .foregroundStyle(Color(hex: 0xc5bcff))
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

    @ViewBuilder private var statusPill: some View {
        if memo.statusKind == .error {
            Button(action: onRetry) {
                StatusPill(style: .error, label: "Retry", systemImage: "exclamationmark.circle.fill")
            }
        } else {
            StatusPill(style: memo.statusKind.pillStyle, label: memo.statusKind.label)
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
    private var snippet: String {
        if let line = memo.firstTranscriptLine { return memo.transcript ?? line }
        return "Voice memo"
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
