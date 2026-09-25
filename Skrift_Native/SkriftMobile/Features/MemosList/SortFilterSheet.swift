import SwiftUI

// MARK: - Sort & Filter sheet

struct SortFilterSheet: View {
    @Binding var sort: MemoSort
    @Binding var filter: MemoFilter
    /// The Unrated CHIP owns "not rated" at regular width, so the sheet hides that
    /// one toggle on the iPad; the phone (no chips) keeps it. Place + Photos are
    /// gone from BOTH now (Tuur 2026-07-23: "we don't even need to filter by photos
    /// or place" — place lives on the Review screen). Sort + Unsynced + Date on both.
    var showNotRated = true
    @Environment(\.dismiss) var dismiss

    // Optional-date bindings: a toggle enables the bound (today by default), the
    // DatePicker then adjusts it; toggling off clears back to nil (no filter).
    var fromEnabled: Binding<Bool> {
        Binding(get: { filter.from != nil },
                set: { filter.from = $0 ? Calendar.current.startOfDay(for: Date()) : nil })
    }
    var toEnabled: Binding<Bool> {
        Binding(get: { filter.to != nil }, set: { filter.to = $0 ? Date() : nil })
    }
    var fromBinding: Binding<Date> {
        Binding(get: { filter.from ?? Date() }, set: { filter.from = $0 })
    }
    var toBinding: Binding<Date> {
        Binding(get: { filter.to ?? Date() }, set: { filter.to = $0 })
    }

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
                    if showNotRated {
                        Toggle("Not rated", isOn: $filter.notRatedOnly)
                            .accessibilityIdentifier("filter-notrated")
                    }
                    Toggle("Unsynced only", isOn: $filter.unsyncedOnly)
                        .accessibilityIdentifier("filter-unsynced")
                }
                Section {
                    Picker("Date field", selection: $filter.dateField) {
                        ForEach(MemoDateField.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("filter-date-field")
                    Toggle("From", isOn: fromEnabled)
                    if filter.from != nil {
                        DatePicker("From date", selection: fromBinding, displayedComponents: .date)
                            .labelsHidden()
                    }
                    Toggle("To", isOn: toEnabled)
                    if filter.to != nil {
                        DatePicker("To date", selection: toBinding, displayedComponents: .date)
                            .labelsHidden()
                    }
                } header: {
                    Text("Date")
                } footer: {
                    Text("Filter by when each note was \(filter.dateField == .added ? "added to Skrift" : "recorded").")
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
        // Bigger than the cramped medium box (Tuur 2026-07-23: "this could be
        // bigger… doesn't have to be this weird small shape").
        .presentationDetents([.large])
    }
}
