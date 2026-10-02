import SwiftUI

/// The strip Date opens under the chip row (Q66/D148, mock A: "a small strip
/// under the row, not a sheet"). An optional field picker (Recorded / Added on
/// both apps since Q105; `fixedLabel` is kept for a caller with one date), then a
/// From and a To pill. An unset pill arms its bound to today on tap; a set one
/// shows a compact DatePicker and a clear button. Clear drops both.
extension View {
    /// Q66 (mock A's `.scrollrow` mask): the chip row's trailing 15% fades out,
    /// the cue that more chips sit past the edge and the row swipes sideways.
    func chipRowFade() -> some View {
        mask(LinearGradient(stops: [.init(color: .black, location: 0.85),
                                    .init(color: .clear, location: 1)],
                            startPoint: .leading, endPoint: .trailing))
    }
}

struct DateRangeStrip: View {
    let style: ChipRowStyle
    @Binding var from: Date?
    @Binding var to: Date?
    var fieldLabels: [String] = []
    var fieldIndex: Binding<Int> = .constant(0)
    var fixedLabel: String? = nil

    var body: some View {
        HStack(spacing: 6) {
            if fieldLabels.count > 1 {
                HStack(spacing: 0) {
                    ForEach(fieldLabels.indices, id: \.self) { i in
                        let on = fieldIndex.wrappedValue == i
                        Text(fieldLabels[i])
                            .font(.system(size: 11, weight: on ? .semibold : .regular))
                            .foregroundStyle(on ? style.accent : style.dim)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(on ? style.accent.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 6))
                            .contentShape(Rectangle())
                            .onTapGesture { fieldIndex.wrappedValue = i }
                            .accessibilityIdentifier("date-field-\(fieldLabels[i])")
                    }
                }
            } else if let fixedLabel {
                Text(fixedLabel).font(.system(size: 11)).foregroundStyle(style.dim)
            }
            pill("From", date: $from, arm: Calendar.current.startOfDay(for: Date()), id: "date-from")
            pill("To", date: $to, arm: Date(), id: "date-to")
            if from != nil || to != nil {
                Button("Clear") { from = nil; to = nil }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(style.accent)
                    .accessibilityIdentifier("date-clear")
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func pill(_ label: String, date: Binding<Date?>, arm: Date, id: String) -> some View {
        if let d = date.wrappedValue {
            HStack(spacing: 2) {
                Text(label).font(.system(size: 11)).foregroundStyle(style.accent).fixedSize()
                DatePicker(label, selection: Binding(get: { d }, set: { date.wrappedValue = $0 }),
                           displayedComponents: .date)
                    .labelsHidden()
                    #if os(iOS)
                    // The compact picker ignores `.font`; shrink it to chip scale and
                    // give the layout the shrunk size (scaleEffect alone keeps the big frame).
                    .fixedSize()
                    .scaleEffect(0.82)
                    .frame(width: 108, height: 26)
                    #else
                    .datePickerStyle(.field).controlSize(.small)
                    #endif
                Button { date.wrappedValue = nil } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 11))
                }
                .buttonStyle(.plain).foregroundStyle(style.dim)
                .accessibilityLabel("Clear \(label) date")
            }
            .accessibilityIdentifier(id)
        } else {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(style.dim)
                .padding(.horizontal, 9).padding(.vertical, 4)
                .overlay(RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(style.dim.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
                .contentShape(Rectangle())
                .onTapGesture { date.wrappedValue = arm }
                .accessibilityIdentifier(id)
        }
    }
}
