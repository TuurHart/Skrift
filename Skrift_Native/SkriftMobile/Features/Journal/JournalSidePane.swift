import SwiftUI

/// Review's standing right pane at regular width (mock `ipad-app.html` m4/m4b,
/// the signed journal-desktop §2 built out): the phone's calendar + places
/// cards, promoted out of the river into their own column — always visible,
/// not gated by whether the river itself has cards. `JournalHomeView` passes
/// the SAME live `memos` it feeds the river (one source, two presentations,
/// zero new data logic).
///
/// Two modes, swapped in place — the river (`JournalHomeView`'s left column)
/// never moves:
/// - `.calendar` (default): month grid (`MonthGrid`, reused verbatim from
///   `JournalCalendarView`) + the selected day's notes + a Places list
///   (`PlaceCluster.build`, the same grouping the map uses).
/// - map mode: `JournalMapCanvas` (the phone's owned-camera map, b89/b90
///   contract, unchanged) — reached by tapping "Places" (opens unfocused) or
///   a specific place row (dives straight to that place), with "⨯ back to
///   calendar" returning to calendar mode.
struct JournalSidePane: View {
    let memos: [Memo]

    @State private var month = Date()
    @State private var selectedDay: Int? = Calendar.current.component(.day, from: Date())
    @State private var mapMode = false
    @State private var mapFocus: PlaceCluster?

    private let calendar = Calendar.current

    private var places: [PlaceCluster] { PlaceCluster.build(from: memos) }

    var body: some View {
        Group {
            if mapMode {
                mapPane
            } else {
                calendarPane
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.skBg)
    }

    // ── calendar mode ──

    private var calendarPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                monthHeader
                MonthGrid(month: month,
                          counts: LookbackProvider.dayCounts(for: memos, month: month),
                          selectedDay: selectedDay, compact: false,
                          onTap: { selectedDay = ($0 == selectedDay) ? nil : $0 })
                    .padding(.top, 12)
                if let day = selectedDay, let date = dayDate(day) {
                    dayLabel(date)
                    dayRows(date)
                }
                if !places.isEmpty {
                    placesHeader
                    VStack(spacing: 2) {
                        ForEach(places) { placeRow($0) }
                    }
                }
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 20)
        }
        .accessibilityIdentifier("ipad-journal-pane-calendar")
    }

    private var monthHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(month.formatted(.dateTime.month(.wide).year()))
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Color.skText)
            Spacer()
            HStack(spacing: 16) {
                Button { stepMonth(-1) } label: {
                    Image(systemName: "chevron.left").font(.system(size: 12, weight: .semibold))
                }
                .accessibilityIdentifier("ipad-journal-month-prev")
                Button { stepMonth(1) } label: {
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold))
                }
                .accessibilityIdentifier("ipad-journal-month-next")
            }
            .foregroundStyle(Color.skTextFaint)
        }
    }

    private func stepMonth(_ by: Int) {
        if let next = calendar.date(byAdding: .month, value: by, to: month) {
            month = next
            selectedDay = nil
        }
    }

    private func dayDate(_ day: Int) -> Date? {
        var comps = calendar.dateComponents([.year, .month], from: month)
        comps.day = day
        return calendar.date(from: comps)
    }

    private func dayLabel(_ date: Date) -> some View {
        let suffix = calendar.isDateInToday(date) ? " · today" : ""
        return Text(date.formatted(.dateTime.weekday(.wide).day().month(.wide)) + suffix)
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(Color.skTextFaint)
            .textCase(.uppercase)
            .padding(.top, 20)
            .padding(.bottom, 7)
    }

    @ViewBuilder
    private func dayRows(_ date: Date) -> some View {
        let dayMemos = LookbackProvider.memos(for: memos, onDay: date)
        if dayMemos.isEmpty {
            Text("Nothing recorded this day.")
                .font(.system(size: 12))
                .foregroundStyle(Color.skTextFaint)
        } else {
            VStack(spacing: 7) {
                ForEach(dayMemos, id: \.id) { JournalDayRow(memo: $0) }
            }
        }
    }

    /// "Places" section label — also the map's unfocused entry (mirrors the
    /// phone's `placesCard` "Map ›" trailing idiom).
    private var placesHeader: some View {
        Button {
            mapFocus = nil
            mapMode = true
        } label: {
            HStack {
                SectionLabel("PLACES")
                Spacer()
                Text("Map ›")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.skTextFaint)
            }
            .padding(.top, 20)
            .padding(.bottom, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("ipad-journal-places-header")
    }

    private func placeRow(_ place: PlaceCluster) -> some View {
        Button {
            mapFocus = place
            mapMode = true
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.skAccent)
                Text(place.name)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Color.skTextDim)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text("\(place.memos.count)")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Color.skTextFaint)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("ipad-journal-place-row-\(place.id)")
    }

    // ── map mode ──

    private var mapPane: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Places")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color.skText)
                Spacer()
                Button {
                    mapMode = false
                    mapFocus = nil
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .semibold))
                        Text("back to calendar")
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(Color.skTextFaint)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("ipad-journal-map-back")
            }
            .padding(.horizontal, 26)
            .padding(.top, 20)
            .padding(.bottom, 10)
            JournalMapCanvas(initialFocus: mapFocus)
        }
        .accessibilityIdentifier("ipad-journal-pane-map")
    }
}

/// One selected-day row in the side pane (mock m4 `.dayrow`): glyph + title +
/// time — lighter than `JournalMemoRow` (no snippet/meta/location), since the
/// day heading above already establishes context. Same source-glyph taxonomy
/// as the Notes list (`SourceKind`); tap pushes the SAME `UUID` destination
/// the river's cards use.
private struct JournalDayRow: View {
    let memo: Memo
    var body: some View {
        JournalCard {
            NavigationLink(value: memo.id) {
                HStack(spacing: 10) {
                    Image(systemName: SourceKind.of(memo).glyph)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.skTextFaint)
                        .frame(width: 16)
                    Text(memo.displayTitle)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Color.skText)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(LookbackProvider.journalDate(memo).formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 10.5))
                        .foregroundStyle(Color.skTextFaint)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .accessibilityIdentifier("ipad-journal-day-row-\(memo.id)")
    }
}
