import SwiftUI

/// The question for audio that arrives through the Files importer or an AirDrop / Open-in burst:
/// One note / N notes for 2+ voice notes (C68 / C145), and Audiobook / Voice note when a clip
/// runs an hour or more (C79, Q150). Same cards as the share sheet's choosers; every word comes
/// from the shared `AudioImportChoice` / `LongAudioRoute`.
struct AudioPickChoiceSheet: View {
    let pending: AudioPickBridge.Pending
    var onConfirm: (AudioImportChoice, LongAudioRoute) -> Void
    var onCancel: () -> Void

    @State private var choice: AudioImportChoice = .default
    @State private var route: LongAudioRoute = .default

    /// Several clips and they are going to become notes: ask One note / N notes.
    private var asksNoteCount: Bool {
        AudioImportChoice.needsChoice(clipCount: pending.clipCount) && !(pending.hasLongClip && route == .audiobook)
    }

    private var effectiveRoute: LongAudioRoute { pending.hasLongClip ? route : .voiceNote }

    private var headline: String {
        if pending.clipCount > 1 { return "Add \(pending.clipCount) voice notes" }
        return pending.hasLongClip ? "This one is long" : "Add a voice note"
    }

    private var subline: String {
        pending.hasLongClip ? "An hour or more. Where should it go?" : "How should they land?"
    }

    private var confirmTitle: String {
        if pending.hasLongClip && route == .audiobook { return route.confirmTitle }
        if asksNoteCount { return choice.confirmTitle(clipCount: pending.clipCount) }
        return LongAudioRoute.voiceNote.confirmTitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(headline)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.skText)
                Text(subline)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.skTextDim)
            }

            if pending.hasLongClip {
                HStack(spacing: 8) {
                    card(title: LongAudioRoute.audiobook.title, subtitle: LongAudioRoute.audiobook.subtitle,
                         selected: route == .audiobook, id: "capture-choice-books") { route = .audiobook }
                    card(title: LongAudioRoute.voiceNote.title, subtitle: LongAudioRoute.voiceNote.subtitle,
                         selected: route == .voiceNote, id: "capture-choice-memo") { route = .voiceNote }
                }
            }

            if asksNoteCount {
                HStack(spacing: 8) {
                    card(title: AudioImportChoice.oneNote.title(clipCount: pending.clipCount),
                         subtitle: AudioImportChoice.oneNote.subtitle,
                         selected: choice == .oneNote, id: "audio-pick-combine") { choice = .oneNote }
                    card(title: AudioImportChoice.separateNotes.title(clipCount: pending.clipCount),
                         subtitle: AudioImportChoice.separateNotes.subtitle,
                         selected: choice == .separateNotes, id: "audio-pick-split") { choice = .separateNotes }
                }
            }

            Button { onConfirm(choice, effectiveRoute) } label: {
                Text(confirmTitle)
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
        .presentationDetents([.height(detentHeight)])
        .accessibilityIdentifier("audio-pick-sheet")
    }

    /// One row of cards is 300; both questions at once add a second row.
    private var detentHeight: CGFloat { pending.hasLongClip && asksNoteCount ? 384 : 300 }

    private func card(title: String, subtitle: String, selected: Bool, id: String,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .top) {
                    Text(title)
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundStyle(Color.skText)
                    Spacer(minLength: 4)
                    Circle()
                        .strokeBorder(selected ? Color.skAccent : Color.skTextFaint, lineWidth: 1.5)
                        .background(Circle().fill(selected ? Color.skAccent : .clear).padding(3))
                        .frame(width: 14, height: 14)
                }
                Text(subtitle)
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
        .accessibilityIdentifier(id)
    }
}
