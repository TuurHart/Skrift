import SwiftUI

/// Q405 / D207: the capture screens' pinned "Record your thoughts" button. Plain solid accent
/// fill (the app's primary-button colour, no gradient), white label + mic glyph. Book-quote,
/// PDF and article capture all use this one view; callers add their own accessibility id,
/// `.disabled` and `.opacity`.
struct RecordThoughtsButton: View {
    var busy: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if busy {
                    ProgressView().controlSize(.small).frame(width: 34, height: 34)
                } else {
                    Image(systemName: "mic")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(.white.opacity(0.18), in: .circle)
                }
                Text(busy ? "Preparing\u{2026}" : "Record your thoughts")
                    .font(.system(size: 14.5, weight: .bold))
                    .foregroundStyle(.white)
                Spacer(minLength: 0)
            }
            .padding(EdgeInsets(top: 13, leading: 16, bottom: 13, trailing: 16))
            .background(Color.skAccent, in: .rect(cornerRadius: 14, style: .continuous))
        }
    }
}
