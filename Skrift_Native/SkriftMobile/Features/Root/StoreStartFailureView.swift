import SwiftUI

/// Full-screen state shown instead of the app when the notes store failed to open.
/// No button touches data: the only honest action is to reopen the app.
struct StoreStartFailureView: View {
    let failure: StoreStartFailure

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 44))
                    .foregroundStyle(Color.skAccent)
                    .accessibilityHidden(true)
                Text(failure.title)
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)
                Text(failure.hint)
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Text(failure.errorText)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
                    .accessibilityIdentifier("storeStartFailure.error")
            }
            .padding(24)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier("storeStartFailure.screen")
    }
}
