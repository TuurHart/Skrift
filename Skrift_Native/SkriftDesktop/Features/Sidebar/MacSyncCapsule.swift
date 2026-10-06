import SwiftUI

/// The notes-list iCloud capsule (Q327, D182, mock `Q162-mac-icloud-state.html` placement A):
/// a slot under the filter chips that exists ONLY while sync is broken, off or signed out.
/// Amber for signed out / couldn't start, grey for switched off. Tapping it opens Settings at Sync.
struct MacSyncCapsule: View {
    let state: MacSyncState
    var action: () -> Void = {}

    var body: some View {
        if let text = state.capsuleText {
            let warn = state.capsuleIsWarning
            HStack {
                Spacer(minLength: 0)
                Button(action: action) {
                    HStack(spacing: 7) {
                        Image(systemName: "icloud.slash").font(.system(size: 11))
                        Text(text).lineLimit(1)
                        Image(systemName: "chevron.right").font(.system(size: 8, weight: .semibold)).opacity(0.7)
                    }
                    .font(.system(size: 11.5))
                    .foregroundStyle(warn ? Theme.amber : Theme.textSecondary)
                    .padding(.horizontal, 13).padding(.vertical, 6)
                    .background(warn ? Theme.amber.opacity(0.12) : Theme.chip, in: Capsule())
                    .overlay(Capsule().stroke(warn ? Theme.amber.opacity(0.35) : Theme.hairline.opacity(0.08), lineWidth: 1))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("sidebar.sync-capsule")
                .accessibilityLabel(text)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8).padding(.top, 8)
        }
    }
}
