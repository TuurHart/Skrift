import SwiftUI

// MARK: - Date filter sheet (Q66/D148 option A — the chip row carries Sort,
// Unsynced and the four statuses now; Date is the only filter left that still
// needs its own surface — a Recorded/Added field pick + From/To range, same
// content the old Sort & Filter sheet's Date section held).

struct DateFilterSheet: View {
    @Binding var filter: MemoFilter
    @Environment(\.dismiss) var dismiss

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
                if filter.dateActive {
                    Button("Clear dates", role: .destructive) { filter.from = nil; filter.to = nil }
                }
            }
            .navigationTitle("Date")
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
