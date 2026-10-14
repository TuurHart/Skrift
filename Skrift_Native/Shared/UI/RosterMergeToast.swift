import SwiftUI

/// Shows "Merged into John Smith" (C254/R62) when a same-name add folds into an existing person,
/// in the host's existing capsule-toast look. Hosts: the phone Names list + note page, the Mac
/// Settings sheet (the Mac main window uses its own `ProcessingCoordinator.flash` toast).
private struct RosterMergeToastModifier: ViewModifier {
    let fill: Color
    let alignment: Alignment
    @State private var message: String?
    @State private var token = 0

    func body(content: Content) -> some View {
        content
            .overlay(alignment: alignment) {
                if let message {
                    Text(message)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(fill, in: Capsule())
                        .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
                        .fixedSize()
                        .padding(alignment == .top ? .top : .bottom, 16)
                        .transition(.opacity)
                        .accessibilityIdentifier("roster-merge-toast")
                }
            }
            .animation(.easeInOut(duration: 0.2), value: message)
            .onReceive(NotificationCenter.default.publisher(for: .namesMergedDuplicate)
                .receive(on: RunLoop.main)) { note in
                guard let line = RosterMergeNotice.message(from: note) else { return }
                token += 1
                let mine = token
                message = line
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(2.5))
                    if token == mine { message = nil }
                }
            }
    }
}

extension View {
    /// Overlay the same-name merge notice (see `RosterMergeToastModifier`).
    func rosterMergeToast(fill: Color, alignment: Alignment) -> some View {
        modifier(RosterMergeToastModifier(fill: fill, alignment: alignment))
    }
}
