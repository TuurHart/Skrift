import SwiftUI

/// Full-month calendar (mock screen 2): dot density per day, today ring,
/// tap a day → its notes below. Pure `createdAt`/`recordedAt` math.
struct JournalCalendarView: View {
    private let repository = NotesRepository.shared
    @State private var memos: [Memo] = []
    @State private var month = Date()
    @State private var selectedDay: Int?

    private let calendar = Calendar.current

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                JournalCard {
                    VStack(spacing: 10) {
                        monthHeader
                        MonthGrid(month: month,
                                  counts: LookbackProvider.dayCounts(for: memos, month: month),
                                  selectedDay: selectedDay, compact: false,
                                  onTap: { selectedDay = ($0 == selectedDay) ? nil : $0 })
                    }
                }
                if let day = selectedDay, let date = date(day: day) {
                    dayList(date: date)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(Color.skBg)
        .navigationTitle(month.formatted(.dateTime.month(.wide).year()))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { memos = repository.allMemos() }
    }

    private var monthHeader: some View {
        HStack {
            Button { step(-1) } label: {
                Image(systemName: "chevron.left").font(.system(size: 13, weight: .semibold))
            }
            Spacer()
            Text(month.formatted(.dateTime.month(.wide).year()))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.skText)
            Spacer()
            Button { step(1) } label: {
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold))
            }
        }
        .foregroundStyle(Color.skAccent)
    }

    private func step(_ by: Int) {
        if let next = calendar.date(byAdding: .month, value: by, to: month) {
            month = next
            selectedDay = nil
        }
    }

    private func date(day: Int) -> Date? {
        var comps = calendar.dateComponents([.year, .month], from: month)
        comps.day = day
        return calendar.date(from: comps)
    }

    private func dayList(date: Date) -> some View {
        let dayMemos = LookbackProvider.memos(for: memos, onDay: date)
        return VStack(alignment: .leading, spacing: 8) {
            Text("\(date.formatted(.dateTime.weekday(.wide).day().month(.wide))) · \(dayMemos.count) note\(dayMemos.count == 1 ? "" : "s")")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.skTextFaint)
                .textCase(.uppercase)
                .padding(.leading, 4)
            if dayMemos.isEmpty {
                Text("Nothing recorded this day.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.skTextFaint)
                    .padding(.leading, 4)
            } else {
                JournalCard {
                    VStack(spacing: 10) {
                        ForEach(dayMemos, id: \.id) { JournalMemoRow(memo: $0, showTime: true) }
                    }
                }
            }
        }
    }
}

/// Month grid shared by the Journal home (compact) and the Calendar screen.
struct MonthGrid: View {
    let month: Date
    let counts: [Int: (count: Int, hot: Bool)]
    let selectedDay: Int?
    let compact: Bool
    let onTap: ((Int) -> Void)?

    private let calendar = Calendar.current

    var body: some View {
        let cells = makeCells()
        VStack(spacing: 2) {
            HStack(spacing: 2) {
                ForEach(weekdaySymbols(), id: \.self) { s in
                    Text(s)
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(Color.skTextFaint)
                        .frame(maxWidth: .infinity)
                }
            }
            ForEach(0..<(cells.count / 7), id: \.self) { row in
                HStack(spacing: 2) {
                    ForEach(0..<7, id: \.self) { col in
                        dayCell(cells[row * 7 + col])
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func dayCell(_ day: Int?) -> some View {
        let height: CGFloat = compact ? 26 : 34
        if let day {
            let info = counts[day]
            let isToday = calendar.isDate(Date(), equalTo: month, toGranularity: .month)
                && calendar.component(.day, from: Date()) == day
            VStack(spacing: 1) {
                Text("\(day)")
                    .font(.system(size: 9.5, weight: isToday ? .bold : .regular))
                    .foregroundStyle(day == selectedDay || isToday ? Color.skText : Color.skTextDim)
                HStack(spacing: 1.5) {
                    ForEach(0..<min(info?.count ?? 0, 3), id: \.self) { _ in
                        Circle()
                            .fill(info?.hot == true ? Color.skAccent : Color.skAccent.opacity(0.45))
                            .frame(width: 3, height: 3)
                    }
                }
                .frame(height: 3)
            }
            .frame(maxWidth: .infinity, minHeight: height)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(day == selectedDay ? Color.skElev : .clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(isToday ? Color.skAccent : .clear, lineWidth: 1.5)
            )
            .contentShape(Rectangle())
            .onTapGesture { onTap?(day) }
        } else {
            Color.clear.frame(maxWidth: .infinity, minHeight: height)
        }
    }

    /// Day numbers padded with leading/trailing nils to full weeks.
    private func makeCells() -> [Int?] {
        guard let interval = calendar.dateInterval(of: .month, for: month),
              let dayRange = calendar.range(of: .day, in: .month, for: month)
        else { return [] }
        let firstWeekday = calendar.component(.weekday, from: interval.start)
        let lead = (firstWeekday - calendar.firstWeekday + 7) % 7
        var cells: [Int?] = Array(repeating: nil, count: lead)
        cells += dayRange.map { Optional($0) }
        while cells.count % 7 != 0 { cells.append(nil) }
        return cells
    }

    private func weekdaySymbols() -> [String] {
        let symbols = calendar.veryShortWeekdaySymbols
        let shift = calendar.firstWeekday - 1
        return Array(symbols[shift...] + symbols[..<shift])
    }
}
