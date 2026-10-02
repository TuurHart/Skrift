import SwiftUI

/// The One-note / N-notes chooser for 2+ voice notes that arrive through the Files importer or
/// an AirDrop / Open-in burst (C68 / C145). Same two cards as the share sheet's chooser; every
/// word comes from the shared `AudioImportChoice`.
struct AudioPickChoiceSheet: View {
    let pending: AudioPickBridge.Pending
    var onConfirm: (AudioImportChoice) -> Void
    var onCancel: () -> Void

    @State private var choice: AudioImportChoice = .default

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Add \(pending.clipCount) voice notes")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.skText)
                Text("How should they land?")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.skTextDim)
            }

            HStack(spacing: 8) {
                card(.oneNote)
                card(.separateNotes)
            }

            Button { onConfirm(choice) } label: {
                Text(choice.confirmTitle(clipCount: pending.clipCount))
                    .font(.system(size: 14.5, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Color.skAccent, in: .rect(cornerRadius: 12, style: .continuous))
            }
            .accessibilityIdentifier("audio-pick-confirm")

            Button(action: onCancel) {
                Text("Cancel")
                    .font(.system(size: 15)).foregroundStyle(Color.skTextDim)
                    .frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .accessibilityIdentifier("audio-pick-cancel")
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.skBg)
        .presentationDetents([.height(300)])
        .accessibilityIdentifier("audio-pick-sheet")
    }

    private func card(_ option: AudioImportChoice) -> some View {
        let selected = choice == option
        return Button { choice = option } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .top) {
                    Text(option.title(clipCount: pending.clipCount))
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundStyle(Color.skText)
                    Spacer(minLength: 4)
                    Circle()
                        .strokeBorder(selected ? Color.skAccent : Color.skTextFaint, lineWidth: 1.5)
                        .background(Circle().fill(selected ? Color.skAccent : .clear).padding(3))
                        .frame(width: 14, height: 14)
                }
                Text(option.subtitle)
                    .font(.system(size: 10.5))
                    .foregroundStyle(selected ? Color.skTextDim : Color.skTextFaint)
                    .multilineTextAlignment(.leading)
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .topLeading)
            .background(selected ? Color.skAccent.opacity(0.09) : Color.skSurface,
                        in: .rect(cornerRadius: 13, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(selected ? Color.skAccent.opacity(0.55) : Color.skTextFaint.opacity(0.3),
                                  lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(option == .oneNote ? "audio-pick-combine" : "audio-pick-split")
    }
}
