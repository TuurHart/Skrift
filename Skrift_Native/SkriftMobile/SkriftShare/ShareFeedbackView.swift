import SwiftUI

/// Terminal feedback states of the share extension (mock `share-ingest-wave1.html`
/// state 4, signed 2026-07-10):
/// - **Saved ✓** — every successful share flashes proof before the sheet closes
///   (the old instant close looked identical to a failure);
/// - **Couldn't save** — failures used to close silently and the item was just
///   *gone*; now they say so, with a retry when one is possible;
/// - **Can't import** — unknown payloads used to fall into an EMPTY text sheet
///   whose Save minted a husk note (A16); now they get an honest dead end;
/// - **Already in Skrift** — the same bytes were shared before (C127, Q440): that
///   note is the share, nothing new is saved.
struct ShareFeedbackView: View {
    enum Kind {
        case saved(summary: String)
        case error(message: String, canRetry: Bool)
        case unsupported(detail: String)
        case alreadyInSkrift
    }

    let kind: Kind
    let onRetry: () -> Void
    let onClose: () -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            ShareTheme.backdrop
                .ignoresSafeArea()
            card
        }
        .preferredColorScheme(.dark)
    }

    private var card: some View {
        VStack(spacing: 0) {
            icon
                .padding(.top, 26)
                .padding(.bottom, 12)
            Text(title)
                .font(.system(size: 15.5, weight: .bold))
                .foregroundStyle(Color.skText)
                .padding(.bottom, 5)
            Text(subtitle)
                .font(.system(size: 12))
                .foregroundStyle(Color.skTextDim)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .padding(.bottom, 18)
            buttons
                .padding(.bottom, 18)
        }
        .frame(maxWidth: .infinity)
        .shareSheetSurface()
        .accessibilityIdentifier("share-feedback-\(a11yKind)")
    }

    // MARK: - Pieces

    @ViewBuilder private var icon: some View {
        switch kind {
        case .saved:
            stateCircle(color: .green) {
                Image(systemName: "checkmark")
                    .font(.system(size: 20, weight: .bold))
            }
        case .error:
            stateCircle(color: .red) {
                Image(systemName: "exclamationmark")
                    .font(.system(size: 20, weight: .bold))
            }
        case .unsupported:
            stateCircle(color: Color.skTextDim) {
                Image(systemName: "nosign")
                    .font(.system(size: 19, weight: .semibold))
            }
        case .alreadyInSkrift:
            stateCircle(color: Color.skAccent) {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 19, weight: .semibold))
            }
        }
    }

    private func stateCircle(color: Color, @ViewBuilder content: () -> some View) -> some View {
        Circle()
            .fill(color.opacity(0.14))
            .frame(width: 52, height: 52)
            .overlay(content().foregroundStyle(color))
    }

    private var title: String {
        switch kind {
        case .saved: return "Saved to Skrift"
        case .error: return "Couldn't save this"
        case .unsupported: return "Skrift can't import this"
        case .alreadyInSkrift: return "Already in Skrift"
        }
    }

    private var subtitle: String {
        switch kind {
        case .saved(let summary):
            return summary + "\nSkrift opens on it next time"
        case .error(let message, _):
            return message + "\nNothing was saved."
        case .unsupported(let detail):
            return detail
        case .alreadyInSkrift:
            return "You shared this file before, so it's the same note.\nNothing new was saved."
        }
    }

    @ViewBuilder private var buttons: some View {
        switch kind {
        case .saved:
            // Auto-dismisses (~0.9 s) — no buttons; the flash IS the receipt.
            EmptyView()
        case .error(_, let canRetry):
            HStack(spacing: 8) {
                feedbackButton("Cancel", prominent: false, action: onClose)
                    .accessibilityIdentifier("share-feedback-cancel")
                if canRetry {
                    feedbackButton("Try again", prominent: true, action: onRetry)
                        .accessibilityIdentifier("share-feedback-retry")
                }
            }
            .padding(.horizontal, 16)
        case .unsupported, .alreadyInSkrift:
            feedbackButton("Close", prominent: false, action: onClose)
                .frame(maxWidth: 140)
                .accessibilityIdentifier("share-feedback-close")
        }
    }

    private func feedbackButton(_ label: String, prominent: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13.5, weight: .bold))
                .foregroundStyle(prominent ? .white : Color.skTextDim)
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .background(prominent ? Color.skAccent : Color.white.opacity(0.06),
                            in: .rect(cornerRadius: 12, style: .continuous))
        }
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
