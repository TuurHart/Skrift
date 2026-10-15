import SwiftUI

/// The share extension's full screens where nothing new is saved (Q464, mock
/// `mocks/Q455-share-sheet.html`), in the sheet's calm look:
/// - **Already in Skrift** — the same bytes were shared before (C127): the note it already is,
///   drawn as a notes-list row, and Done;
/// - **Can't import** — the standard iOS empty state (C75: never a husk);
/// - **Couldn't save** — a failed write, the same empty state with Try again;
/// - **Saved** — only the book hand-off (no sheet) still flashes this before closing; every
///   other save shows its receipt in place on the sheet.
struct ShareFeedbackView: View {
    enum Kind {
        case saved(summary: String)
        case error(message: String, canRetry: Bool)
        case unsupported(detail: String)
        /// The note these bytes became: its title and its list line, when the app has seen it.
        case alreadyInSkrift(title: String?, line: String?)
    }

    let kind: Kind
    let onRetry: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ShareNavBar {
                if case .error(_, true) = kind {
                    Button("Cancel", action: onClose)
                        .buttonStyle(ShareNavButtonStyle(kind: .glass))
                        .accessibilityIdentifier("share-feedback-cancel")
                }
            } trailing: {
                trailing
            }
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.skBg.ignoresSafeArea())
        .accessibilityIdentifier("share-feedback-\(a11yKind)")
    }

    @ViewBuilder private var trailing: some View {
        switch kind {
        case .saved:
            HStack(spacing: 5) {
                Image(systemName: "checkmark").font(.system(size: 14, weight: .bold))
                Text("Saved")
            }
            .modifier(StaticNavButton(kind: .done))
        case .error(_, let canRetry):
            if canRetry {
                Button("Try again", action: onRetry)
                    .buttonStyle(ShareNavButtonStyle(kind: .primary))
                    .accessibilityIdentifier("share-feedback-retry")
            } else {
                doneButton
            }
        case .unsupported, .alreadyInSkrift:
            doneButton
        }
    }

    private var doneButton: some View {
        Button("Done", action: onClose)
            .buttonStyle(ShareNavButtonStyle(kind: .glass))
            .accessibilityIdentifier("share-feedback-close")
    }

    @ViewBuilder private var content: some View {
        switch kind {
        case .alreadyInSkrift(let title, let line):
            VStack(alignment: .leading, spacing: 8) {
                Text("ALREADY IN SKRIFT")
                    .font(.system(size: 13))
                    .tracking(0.26)
                    .foregroundStyle(Color.skTextDim)
                    .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 4)
                    .accessibilityAddTraits(.isHeader)
                ShareCard {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title ?? "A note in Skrift")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Color.skText)
                            .lineLimit(1)
                        Text(line ?? "Waiting for Skrift to open")
                            .font(.system(size: 15))
                            .foregroundStyle(Color.skTextDim)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("share-already-row")
                }
                ShareFooter(text: "You shared this file before, so it's the same note. Nothing new was saved.")
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
        case .saved(let summary):
            emptyState(symbol: "checkmark.circle", tint: .skGreen, title: "Saved to Skrift",
                       detail: summary + ". Skrift opens on it next time.")
        case .error(let message, _):
            emptyState(symbol: "exclamationmark.triangle", tint: .skTextFaint, title: "Couldn't save this",
                       detail: message + " Nothing was saved.")
        case .unsupported(let detail):
            emptyState(symbol: "nosign", tint: .skTextFaint, title: "Skrift can't import this", detail: detail)
        }
    }

    /// The standard iOS empty state: a grey symbol, one title, one line.
    private func emptyState(symbol: String, tint: Color, title: String, detail: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 50, weight: .regular))
                .foregroundStyle(tint)
                .padding(.bottom, 6)
                .accessibilityHidden(true)
            Text(title)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Color.skText)
                .multilineTextAlignment(.center)
            Text(detail)
                .font(.system(size: 15))
                .foregroundStyle(Color.skTextDim)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 40)
        .padding(.bottom, 120)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var a11yKind: String {
        switch kind {
        case .saved: return "saved"
        case .error: return "error"
        case .unsupported: return "unsupported"
        case .alreadyInSkrift: return "already"
        }
    }
}

/// A nav-bar badge that looks like the button but takes no taps (the green Saved).
private struct StaticNavButton: ViewModifier {
    let kind: ShareNavButtonStyle.Kind
    func body(content: Content) -> some View {
        content
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .frame(minWidth: 44, minHeight: 44)
            .background(Color.skGreen, in: .capsule)
    }
}
