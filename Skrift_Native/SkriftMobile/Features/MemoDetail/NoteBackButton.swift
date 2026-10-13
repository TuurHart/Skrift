import SwiftUI
import UIKit

/// Q382 (mock Q350): the phone note's top bar keeps "‹ Notes" while typing. The system back
/// button draws a bare chevron here (the list hides its own bar, so there is no title to borrow),
/// so the note hides it and draws this one, then hands the edge-swipe back to UIKit.
struct NoteBackButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .semibold))
                Text("Notes")
                    .font(.system(size: 17))
            }
            .foregroundStyle(Color.skAccent)
            .frame(height: 34)
        }
        .accessibilityIdentifier("note-back-button")
        .accessibilityLabel("Back to Notes")
    }
}

/// Hiding the system back button also switches off the edge-swipe pop. This puts it back, but
/// only while there is a screen to pop to (a root route would otherwise freeze on the swipe).
struct SwipeBackRestorer: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Restorer { Restorer() }
    func updateUIViewController(_ vc: Restorer, context: Context) {}

    final class Restorer: UIViewController, UIGestureRecognizerDelegate {
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            navigationController?.interactivePopGestureRecognizer?.delegate = self
            navigationController?.interactivePopGestureRecognizer?.isEnabled = true
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            (navigationController?.viewControllers.count ?? 0) > 1
        }
    }
}
