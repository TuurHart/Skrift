import SwiftUI

/// The bookmark-removal pill: "Removed 1 bookmark at 12:34" + Undo (C269/R82). Same
/// look as `TagUndoToastView` (black capsule, accent Undo button) with free text.
struct BookmarkRemovedToast: Identifiable {
    let id = UUID()
    let text: String
    let undo: () -> Void
}

struct BookmarkRemovedToastView: View {
    let toast: BookmarkRemovedToast
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(toast.text)
                .font(.system(size: 13)).foregroundStyle(Color.white)
            Button("Undo", action: onUndo)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Color.skAccent, in: .capsule)
                .accessibilityIdentifier("bookmark-undo")
        }
        .padding(.leading, 16).padding(.trailing, 6).padding(.vertical, 6)
        .background(Color.black.opacity(0.85), in: .capsule)
        .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
        .fixedSize()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("bookmark-removed-toast")
    }
}
