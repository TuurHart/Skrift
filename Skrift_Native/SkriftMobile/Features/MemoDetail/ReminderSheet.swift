import SwiftUI

/// Set / change / clear a note's reminder (chunk 7). Quick presets + a full
/// picker; writing `remindAt` syncs the DATA everywhere, and each device's
/// `ReminderScheduler` derives its local alarm from it.
struct ReminderSheet: View {
    @Bindable var memo: Memo
    var onChanged: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var pickerDate: Date = ReminderPresets.thisEvening(from: Date()) ?? Date().addingTimeInterval(3600)
    @State private var deniedAuth = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.skBg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if let current = memo.remindAt {
                            currentRow(current)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            SectionLabel("QUICK")
                            presetRow("This evening", date: ReminderPresets.thisEvening(from: Date()))
                            presetRow("Tomorrow morning", date: ReminderPresets.tomorrowMorning(from: Date()))
                            presetRow("Next week", date: ReminderPresets.nextWeek(from: Date()))
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            SectionLabel("PICK A TIME")
                            DatePicker("", selection: $pickerDate, in: Date()...,
                                       displayedComponents: [.date, .hourAndMinute])
                                .datePickerStyle(.graphical)
                                .tint(.skAccent)
                                .background(Color.skSurface, in: .rect(cornerRadius: 13, style: .continuous))
                            Button { set(pickerDate) } label: {
                                Text("Remind me then")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(Color.skAccent, in: .rect(cornerRadius: 12, style: .continuous))
                            }
                            .accessibilityIdentifier("reminder-set-picked")
                        }

                        if deniedAuth {
                            Text("Notifications are off for Skrift — the reminder is saved and will sync, but this phone can't ring. Enable them in Settings → Notifications.")
                                .font(.system(size: 12.5))
                                .foregroundStyle(Color.skTextDim)
                        }
                    }
                    .padding(Theme.Space.margin)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .navigationTitle("Remind me")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func currentRow(_ current: Date) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "bell.fill").font(.system(size: 13)).foregroundStyle(Color.skAccent)
            VStack(alignment: .leading, spacing: 2) {
                Text(current > Date() ? "Reminds you" : "Reminded")
                    .font(.system(size: 11.5)).foregroundStyle(Color.skTextDim)
                Text(current.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.skText)
            }
            Spacer()
            Button { clear() } label: {
                Text("Remove")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(hex: 0xE5604B))
            }
            .accessibilityIdentifier("reminder-remove")
        }
        .padding(12)
        .background(Color.skSurface, in: .rect(cornerRadius: 13, style: .continuous))
        .overlay(RoundedRectangle.sk(13).stroke(Color.skBorder, lineWidth: 1))
    }

    @ViewBuilder private func presetRow(_ label: String, date: Date?) -> some View {
        if let date {
            Button { set(date) } label: {
                HStack {
                    Text(label).font(.system(size: 14.5)).foregroundStyle(Color.skText)
                    Spacer()
                    Text(date.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 12.5)).foregroundStyle(Color.skTextDim)
                }
                .padding(.horizontal, 12).padding(.vertical, 11)
                .background(Color.skSurface, in: .rect(cornerRadius: 11, style: .continuous))
                .overlay(RoundedRectangle.sk(11).stroke(Color.skBorder, lineWidth: 1))
            }
            .accessibilityIdentifier("reminder-preset-\(label)")
        }
    }

    private func set(_ date: Date) {
        memo.remindAt = date
        memo.markEdited()
        onChanged()
        Task {
            let granted = await ReminderScheduler.requestAuthorization()
            deniedAuth = !granted
            ReminderScheduler.run(NotesRepository.shared)
            if granted { dismiss() }
        }
    }

    private func clear() {
        memo.remindAt = nil
        memo.markEdited()
        onChanged()
        ReminderScheduler.run(NotesRepository.shared)
        dismiss()
    }
}

/// Preset date math, pure for tests: evening = 18:00 today (nil once past),
/// tomorrow = 09:00, next week = 09:00 seven days out.
enum ReminderPresets {
    static func thisEvening(from now: Date, calendar: Calendar = .current) -> Date? {
        guard let at = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: now),
              at > now else { return nil }
        return at
    }

    static func tomorrowMorning(from now: Date, calendar: Calendar = .current) -> Date? {
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) else { return nil }
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow)
    }

    static func nextWeek(from now: Date, calendar: Calendar = .current) -> Date? {
        guard let day = calendar.date(byAdding: .day, value: 7, to: now) else { return nil }
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day)
    }
}
