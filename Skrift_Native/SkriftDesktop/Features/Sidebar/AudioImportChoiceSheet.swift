import SwiftUI

/// Files that arrived together and are waiting on the C68 chooser. One value per drop / Import
/// pick, so the sheet is `.sheet(item:)`-driven and a second drop can't stack a second sheet.
struct PendingAudioImport: Identifiable {
    let id = UUID()
    let urls: [URL]
    let clipCount: Int
    /// Removes the temp folder of a Photos file-promise drop once the files are copied (or the
    /// sheet is cancelled). nil for Finder / Import-panel picks, which point at the user's files.
    var cleanup: (() -> Void)? = nil
}

/// The Mac form of the phone's share-sheet chooser (`ShareSheetView.chooser`, C68/C145):
/// "One note" (default — clips stitched in order, one transcript) or "N notes". Wording comes
/// from the shared `AudioImportChoice`, so the two apps cannot drift apart. The phone's cards
/// are the signed-off design; this is the same two cards in a small native sheet.
struct AudioImportChoiceSheet: View {
    let clipCount: Int
    var onConfirm: (AudioImportChoice) -> Void
    var onCancel: () -> Void

    @State private var choice: AudioImportChoice = .default

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Add \(clipCount) voice notes")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("How should they land?")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
            }

            HStack(spacing: 8) {
                card(.oneNote)
                card(.separateNotes)
            }

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("audio-choice-cancel")
                Button(choice.confirmTitle(clipCount: clipCount)) { onConfirm(choice) }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .accessibilityIdentifier("audio-choice-confirm")
            }
        }
        .padding(20)
        .frame(width: 420)
        .background(Theme.bg)
    }

    private func card(_ option: AudioImportChoice) -> some View {
        let selected = choice == option
        return Button { choice = option } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top) {
                    Text(option.title(clipCount: clipCount))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer(minLength: 4)
                    Circle()
                        .strokeBorder(selected ? Theme.accent : Theme.hairline.opacity(0.4), lineWidth: 1.5)
                        .background(Circle().fill(selected ? Theme.accent : .clear).padding(3))
                        .frame(width: 14, height: 14)
                }
                Text(option.subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 74, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 9).fill(selected ? Theme.accentSoft : Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: 9)
                .strokeBorder(selected ? Theme.accent : Theme.hairline.opacity(0.2), lineWidth: selected ? 1.5 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(option == .oneNote ? "audio-choice-combine" : "audio-choice-split")
    }
}
