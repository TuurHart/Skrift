import SwiftUI
import SwiftData
import MapKit

/// Journal on the Mac (SIGNED mock `mocks/journal-desktop.html` v2): the phone's three
/// Journal screens become one simultaneous surface — a navigation RAIL (mini month
/// calendar with dot density + places) and a reading COLUMN ("Looking back" river +
/// selected-day notes; clicking Places swaps the column for the map, the rail never
/// changes). Same shared rules as the phone (`LookbackProvider`, `PlaceCluster`) over
/// the same synced memos — zero new logic, different glass.
///
/// Data: the CLOUD `Memo` store, read-only (ingest is significance-gated; sync is not —
/// so the journal sees the full corpus). The Mac never mutates memos from here.
struct JournalView: View {
    var model: AppModel
    var coordinator: ProcessingCoordinator
    /// Open a memo in the Queue surface (when its PipelineFile exists).
    var onOpenInQueue: (String) -> Void = { _ in }
    /// Snapshot/test injection — nil = fetch from the cloud store.
    var injectedMemos: [Memo]? = nil
    /// Snapshot-only: open directly in map mode with the top place selected.
    var debugStartInMap = false

    @State private var memos: [Memo] = []
    @State private var month: Date = Date()
    @State private var selectedDay: Date = Date()
    @State private var mapMode = false
    @State private var selectedPlace: PlaceCluster?
    @State private var span = MKCoordinateSpan(latitudeDelta: 40, longitudeDelta: 40)
    /// Explicit camera position — WITHOUT it the Map runs in automatic framing,
    /// and every span-driven re-cluster (annotation content change) makes the
    /// automatic camera re-fit all pins, snapping the map back mid-gesture
    /// (the "glitchy" 2026-07-16 device finding).
    @State private var camera: MapCameraPosition = .automatic

    private var calendar: Calendar { .current }
    private var clusters: [PlaceCluster] { PlaceCluster.build(from: memos) }

    var body: some View {
        HStack(spacing: 0) {
            rail
                .frame(width: 252)
                .background(Theme.sidebar.opacity(0.55))
                .overlay(alignment: .trailing) {
                    Rectangle().fill(Theme.hairline.opacity(0.07)).frame(width: 0.5)
                }
            column
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.bg)
        .task {
            refresh()
            if debugStartInMap, let first = clusters.first {
                focus(first)
            }
        }
    }

    private func refresh() {
        if let injected = injectedMemos {
            memos = MemoDuplicates.canonicalRows(injected).filter { $0.deletedAt == nil }
            return
        }
        guard let cloud = MemoCloudStore.container else { memos = []; return }
        let all = (try? cloud.mainContext.fetch(FetchDescriptor<Memo>())) ?? []
        memos = MemoDuplicates.canonicalRows(all).filter { $0.deletedAt == nil }
    }

    // ── Rail: mini month calendar + places ─────────────────────────────

    private var rail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SurfaceSwitch(model: model)
                    .padding(.bottom, 16)
                monthHeader
                MiniMonthGrid(month: month,
                              counts: LookbackProvider.dayCounts(for: memos, month: month),
                              selectedDay: $selectedDay,
                              onPick: { mapMode = false })
                Text("PLACES")
                    .font(.system(size: 10, weight: .semibold)).tracking(0.5)
                    .foregroundStyle(Theme.textMuted)
                    .padding(.top, 18).padding(.bottom, 6).padding(.leading, 2)
                ForEach(clusters.prefix(8)) { cluster in
                    placeRow(cluster)
                }
                if clusters.isEmpty {
                    Text("Notes with a location land here.")
                        .font(.system(size: 11)).foregroundStyle(Theme.textMuted)
                        .padding(.leading, 2)
                } else {
                    // Ambient mini-map (mock review-minimap.html #m1): geography is
                    // always on screen; the river never moves. Click → full map,
                    // fitted to every pin, no place pre-selected.
                    RailMiniMap(clusters: clusters) {
                        selectedPlace = nil
                        mapMode = true
                        if let region = PlaceCluster.fitRegion(for: clusters) {
                            withAnimation { camera = .region(region) }
                        }
                    }
                    .padding(.top, 12)
                }
            }
            .padding(14)
        }
    }

    private var monthHeader: some View {
        HStack {
            Text(month.formatted(.dateTime.month(.wide).year()))
                .font(.system(size: 12.5, weight: .bold))
            Spacer()
            HStack(spacing: 10) {
                Button { step(-1) } label: { Image(systemName: "chevron.left") }
                Button { step(1) } label: { Image(systemName: "chevron.right") }
            }
            .buttonStyle(.plain).font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Theme.textMuted)
        }
        .padding(.bottom, 8)
    }

    private func step(_ by: Int) {
        if let next = calendar.date(byAdding: .month, value: by, to: month) { month = next }
    }

    /// Select a place and fly the camera to it — the rail click and the map-mode
    /// entry path. An explicit region also takes the Map out of `.automatic`, so
    /// pin re-clustering can never re-frame the user's view.
    private func focus(_ cluster: PlaceCluster) {
        selectedPlace = cluster
        mapMode = true
        withAnimation {
            camera = .region(MKCoordinateRegion(
                center: cluster.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.3, longitudeDelta: 0.3)))
        }
    }

    private func placeRow(_ cluster: PlaceCluster) -> some View {
        let isOn = mapMode && selectedPlaceShownBy(cluster)
        return Button {
            focus(cluster)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "smallcircle.filled.circle")
                    .font(.system(size: 9)).foregroundStyle(Theme.accent)
                Text(cluster.name).font(.system(size: 12))
                    .foregroundStyle(isOn ? Theme.textPrimary : Theme.textSecondary)
                    .lineLimit(1)
                Spacer()
                Text("\(cluster.memos.count)").font(.system(size: 10.5))
                    .foregroundStyle(Theme.textMuted)
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(isOn ? Theme.accent.opacity(0.13) : .clear,
                        in: RoundedRectangle(cornerRadius: 7))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // ── Column: Looking back river ⇄ map mode ──────────────────────────

    @ViewBuilder private var column: some View {
        if mapMode {
            mapColumn
        } else {
            lookbackColumn
        }
    }

    private var lookbackColumn: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text(SharedCopy.reviewTitle).font(.system(size: 17, weight: .bold))
                Text("As your notes age, past thinking resurfaces here — a month ago, a year ago, on this day.")
                    .font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                    .padding(.bottom, 10)

                if memos.isEmpty {
                    emptyState
                } else {
                    ForEach(LookbackProvider.entries(for: memos, now: selectedDay)) { entry in
                        if let memo = memos.first(where: { $0.id == entry.id }) {
                            card(memo, kick: entry.label, warmKick: false)
                        }
                    }
                    dayHeader
                    let dayMemos = LookbackProvider.memos(for: memos, onDay: selectedDay)
                    if dayMemos.isEmpty {
                        Text("No notes this day.")
                            .font(.system(size: 12)).foregroundStyle(Theme.textMuted)
                    }
                    ForEach(dayMemos, id: \.persistentModelID) { memo in
                        if memo.transcriptStatus != .done {
                            slimRow(memo)   // in-flight = a quiet row, never a card (review-1)
                        } else {
                            card(memo, kick: memo.recordedAt.formatted(date: .omitted, time: .shortened), warmKick: true)
                        }
                    }
                }
            }
            .frame(maxWidth: 780, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24).padding(.horizontal, 30)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(MemoCloudStore.container == nil && injectedMemos == nil
                 ? "Turn on iCloud sync in Settings to journal your synced notes."
                 : "Your notes appear here as they sync.")
                .font(.system(size: 12.5)).foregroundStyle(Theme.textSecondary)
        }
        .padding(.top, 8)
    }

    private var dayHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(calendar.isDateInToday(selectedDay)
                 ? "\(selectedDay.formatted(.dateTime.weekday(.wide).day().month(.wide))) · today"
                 : selectedDay.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                .font(.system(size: 13.5, weight: .bold))
            Spacer()
            let n = LookbackProvider.memos(for: memos, onDay: selectedDay).count
            Text("\(n) note\(n == 1 ? "" : "s")")
                .font(.system(size: 11)).foregroundStyle(Theme.textMuted)
        }
        .padding(.top, 14)
    }

    private var mapColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Places").font(.system(size: 17, weight: .bold))
                Spacer()
                Button {
                    mapMode = false
                } label: {
                    Label("Back to Looking back", systemImage: "xmark")
                        .font(.system(size: 11)).foregroundStyle(Theme.textMuted)
                }
                .buttonStyle(.plain)
            }
            Map(position: $camera) {
                ForEach(PlaceCluster.merged(clusters, span: span)) { cluster in
                    Annotation(cluster.name, coordinate: cluster.coordinate) {
                        pin(cluster)
                    }
                }
            }
            .mapStyle(.standard)
            .onMapCameraChange(frequency: .onEnd) { context in span = context.region.span }
            .frame(height: 330)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            if let place = selectedPlace {
                HStack(alignment: .firstTextBaseline) {
                    Text(place.name).font(.system(size: 13.5, weight: .bold))
                    Spacer()
                    Text("\(place.memos.count) notes · newest first")
                        .font(.system(size: 11)).foregroundStyle(Theme.textMuted)
                }
                .padding(.top, 10)
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(place.memos.prefix(20), id: \.persistentModelID) { memo in
                            card(memo,
                                 kick: LookbackProvider.journalDate(memo).formatted(date: .abbreviated, time: .shortened),
                                 warmKick: true)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 24).padding(.horizontal, 30)
    }

    /// Does this (possibly merged) pin show the selected place? Merged pins carry
    /// compound "a+b" ids, so exact id equality goes false the moment the user
    /// zooms out — match on the id COMPONENT instead (2026-07-16 device finding:
    /// the selection highlight silently vanished across a merge).
    private func selectedPlaceShownBy(_ cluster: PlaceCluster) -> Bool {
        guard let sel = selectedPlace else { return false }
        return cluster.id.split(separator: "+").contains(Substring(sel.id))
    }

    private func pin(_ cluster: PlaceCluster) -> some View {
        let isOn = selectedPlaceShownBy(cluster)
        return Text("\(cluster.memos.count)")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(isOn ? Theme.accent : .white)
            .padding(.horizontal, 7)
            .frame(minWidth: 24, minHeight: 24)
            .background(Circle().fill(isOn ? Color.white : Theme.accent))
            .overlay(Circle().strokeBorder(Theme.accent, lineWidth: isOn ? 2.5 : 0))
            .shadow(color: Theme.accent.opacity(0.45), radius: 5, y: 2)
            .onTapGesture { selectedPlace = cluster }
    }

    // ── Cards ──────────────────────────────────────────────────────────

    private func card(_ memo: Memo, kick: String, warmKick: Bool) -> some View {
        Button { openInQueue(memo) } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(kick.uppercased())
                        .font(.system(size: 10, weight: .bold)).tracking(0.4)
                        .foregroundStyle(warmKick ? Theme.textMuted : Theme.accent)
                    Spacer()
                    Text(LookbackProvider.journalDate(memo).formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 10.5)).foregroundStyle(Theme.textMuted)
                }
                Text(cardTitle(memo))
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary).lineLimit(1)
                if memo.locked {
                    (Text(Image(systemName: "lock.fill")) + Text(" Locked note"))
                        .font(.system(size: 12)).foregroundStyle(Theme.textMuted)
                } else if !snippet(memo).isEmpty {
                    Text(snippet(memo))
                        .font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                        .lineLimit(2)
                }
                HStack(spacing: 10) {
                    importanceDots(memo)
                    if let place = memo.metadata?.location?.placeName {
                        Text(place).font(.system(size: 10.5)).foregroundStyle(Theme.textMuted)
                            .padding(.horizontal, 8).padding(.vertical, 1.5)
                            .background(Theme.hairline.opacity(0.05), in: Capsule())
                    }
                    if memo.duration > 0 {
                        Text(Duration.seconds(memo.duration).formatted(.time(pattern: .minuteSecond)))
                            .font(.system(size: 10.5)).foregroundStyle(Theme.textMuted)
                    }
                    Spacer()
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.hairline.opacity(0.07), lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func slimRow(_ memo: Memo) -> some View {
        HStack(spacing: 8) {
            Circle().fill(Theme.amber)
                .frame(width: 7, height: 7)
                .shadow(color: Theme.amber.opacity(0.7), radius: 4)
            Text("Voice note · transcribing…")
                .font(.system(size: 11.5)).foregroundStyle(Theme.textSecondary)
            Spacer()
            Text(memo.recordedAt.formatted(date: .omitted, time: .shortened))
                .font(.system(size: 11)).foregroundStyle(Theme.textMuted)
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .overlay(RoundedRectangle(cornerRadius: 9)
            .stroke(Theme.hairline.opacity(0.07), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
    }

    private func importanceDots(_ memo: Memo) -> some View {
        let lit = SignificanceScale.step(for: memo.significance)
        return HStack(spacing: 2.5) {
            ForEach(1...SignificanceScale.stepCount, id: \.self) { i in
                Circle()
                    .fill(i <= lit ? Theme.accent : Theme.hairline.opacity(0.12))
                    .frame(width: 5, height: 5)
            }
        }
    }

    private func cardTitle(_ memo: Memo) -> String {
        if memo.locked { return memo.title ?? "Locked note" }
        if let t = memo.title, !t.isEmpty { return t }
        let first = (memo.transcript ?? "")
            .components(separatedBy: .newlines).first?
            .trimmingCharacters(in: .whitespaces) ?? ""
        return first.isEmpty ? "Voice note" : String(first.prefix(80))
    }

    private func snippet(_ memo: Memo) -> String {
        let raw = memo.annotationText ?? memo.transcript ?? ""
        let cleaned = raw.replacingOccurrences(of: #"\[\[img_\d+\]\]"#,
                                               with: "", options: .regularExpression)
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)
        return String(cleaned.prefix(180))
    }

    private func openInQueue(_ memo: Memo) {
        onOpenInQueue(memo.id.uuidString)
    }
}

// ── Queue | Journal mode switch (mock v2, sidebar top) ─────────────────

struct SurfaceSwitch: View {
    @Bindable var model: AppModel

    var body: some View {
        HStack(spacing: 3) {
            segment("Queue", .queue)
            segment(SharedCopy.reviewTitle, .journal)
        }
        .padding(3)
        .background(Theme.hairline.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }

    private func segment(_ label: String, _ surface: AppModel.MainSurface) -> some View {
        let isOn = model.surface == surface
        return Button { model.surface = surface } label: {
            Text(label)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(isOn ? Theme.textPrimary : Theme.textMuted)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .background(isOn ? Theme.surface : .clear, in: RoundedRectangle(cornerRadius: 6))
                .shadow(color: isOn ? .black.opacity(0.3) : .clear, radius: 2, y: 1)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label) surface")
    }
}

// ── Mini month grid (dot density per day, today ring, selected fill) ───

private struct MiniMonthGrid: View {
    let month: Date
    let counts: [Int: (count: Int, hot: Bool)]
    @Binding var selectedDay: Date
    var onPick: () -> Void = {}

    private var calendar: Calendar { .current }

    var body: some View {
        let days = gridDays()
        VStack(spacing: 2) {
            HStack(spacing: 0) {
                ForEach(weekdaySymbols(), id: \.self) { wd in
                    Text(wd).font(.system(size: 8.5, weight: .semibold))
                        .foregroundStyle(Theme.textMuted)
                        .frame(maxWidth: .infinity)
                }
            }
            ForEach(0..<days.count / 7, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { col in
                        dayCell(days[row * 7 + col])
                    }
                }
            }
        }
    }

    @ViewBuilder private func dayCell(_ day: Date?) -> some View {
        if let day {
            let n = calendar.component(.day, from: day)
            let inMonth = calendar.isDate(day, equalTo: month, toGranularity: .month)
            let isToday = calendar.isDateInToday(day)
            let isSelected = calendar.isDate(day, inSameDayAs: selectedDay)
            let stat = inMonth ? counts[n] : nil
            Button {
                selectedDay = day
                onPick()
            } label: {
                VStack(spacing: 2) {
                    Text("\(n)")
                        .font(.system(size: 10.5, weight: isToday ? .bold : .regular))
                        .foregroundStyle(inMonth
                            ? (isToday || isSelected ? Theme.textPrimary : Theme.textSecondary)
                            : Theme.textMuted.opacity(0.4))
                    Circle()
                        .fill(Theme.accent.opacity(dotOpacity(stat)))
                        .frame(width: dotSize(stat), height: dotSize(stat))
                        .frame(height: 6)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 3)
                .background(isSelected ? Theme.accent.opacity(0.18) : .clear,
                            in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(isToday ? Theme.accent : .clear, lineWidth: 1.5))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            Color.clear.frame(maxWidth: .infinity).frame(height: 26)
        }
    }

    private func dotSize(_ stat: (count: Int, hot: Bool)?) -> CGFloat {
        guard let stat, stat.count > 0 else { return 0 }
        return stat.count >= 4 ? 6 : stat.count >= 2 ? 5 : 4
    }

    private func dotOpacity(_ stat: (count: Int, hot: Bool)?) -> Double {
        guard let stat, stat.count > 0 else { return 0 }
        return stat.hot ? 1 : stat.count >= 2 ? 0.8 : 0.45
    }

    /// The displayed grid: leading/trailing days padded to full weeks (nil = blank).
    private func gridDays() -> [Date?] {
        guard let interval = calendar.dateInterval(of: .month, for: month) else { return [] }
        let first = interval.start
        let weekday = calendar.component(.weekday, from: first)
        let leading = (weekday - calendar.firstWeekday + 7) % 7
        let dayCount = calendar.range(of: .day, in: .month, for: month)?.count ?? 30
        var out: [Date?] = Array(repeating: nil, count: leading)
        for d in 0..<dayCount {
            out.append(calendar.date(byAdding: .day, value: d, to: first))
        }
        while out.count % 7 != 0 { out.append(nil) }
        return out
    }

    private func weekdaySymbols() -> [String] {
        let syms = calendar.veryShortWeekdaySymbols   // Sun-first
        let shift = calendar.firstWeekday - 1
        return Array(syms[shift...] + syms[..<shift])
    }
}
