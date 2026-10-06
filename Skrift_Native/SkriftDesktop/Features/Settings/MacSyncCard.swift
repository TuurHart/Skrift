import SwiftUI
import AppKit

/// The body of Settings → Sync (Q327, D182, mock `Q162-mac-icloud-state.html`, Mac Settings tab):
/// a status row, the amber alert when signed out / couldn't start, the Mac's one switch (label
/// unchanged, "CloudKit sync with the Mac"), and the list of what that switch gates in place of
/// the old paragraph of help.
struct MacSyncCard: View {
    let state: MacSyncState
    let failureDetail: String
    @Binding var switchOn: Bool
    /// Snapshots draw "On"/"Off" text (ImageRenderer can't draw an AppKit switch).
    let interactive: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            statusRow
            if let alert = state.alertText { alertCard(alert) }
            switchRow
                .padding(.top, 11)
                .overlay(alignment: .top) { Rectangle().fill(Theme.hairline.opacity(0.07)).frame(height: 0.5) }
            if state == .off {
                Text(MacSyncState.offText)
                    .font(.system(size: 11.5)).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            gateList
            Text(SharedCopy.syncSameAccount)
                .font(.system(size: 10.5)).foregroundStyle(Theme.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var statusRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "icloud").font(.system(size: 13)).foregroundStyle(Theme.accent)
            Text("iCloud").font(.system(size: 12)).foregroundStyle(Theme.textPrimary)
            Spacer()
            HStack(spacing: 6) {
                if state == .syncing { ProgressView().controlSize(.mini).scaleEffect(0.8) }
                Text(state.rowText)
                    .font(.system(size: 12, weight: state.rowIsWarning ? .semibold : .regular))
                    .foregroundStyle(state.rowIsWarning ? Theme.amber : Theme.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("settings.sync.row")
    }

    private func alertCard(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(text)
                .font(.system(size: 11.5)).foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if state == .failed {
                Text(failureDetail)
                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(Theme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            alertButton(state == .signedOut ? "Open iCloud Settings…" : "Reopen Skrift") {
                state == .signedOut ? Self.openICloudSettings() : Self.relaunch()
            }
        }
        .padding(.horizontal, 11).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.amber.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.amber.opacity(0.35), lineWidth: 1))
        .accessibilityIdentifier("settings.sync.alert")
    }

    private func alertButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Theme.amber)
                .padding(.horizontal, 11).frame(minHeight: 30)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.amber.opacity(0.35), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var switchRow: some View {
        HStack {
            Text("CloudKit sync with the Mac").font(.system(size: 12)).foregroundStyle(Theme.textPrimary)
            Spacer()
            if interactive {
                Toggle("", isOn: $switchOn).labelsHidden().toggleStyle(.switch).controlSize(.small)
                    .accessibilityIdentifier("settings.sync.switch")
            } else {
                Text(switchOn ? "On" : "Off").font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private var gateList: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(MacSyncState.gates.enumerated()), id: \.offset) { _, gate in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(Self.arrow(gate.0)).font(.system(size: 10)).foregroundStyle(Theme.textMuted)
                        .frame(width: 14, alignment: .leading)
                    Text(gate.1).font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                        .strikethrough(!switchOn, color: Theme.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        // VoiceOver reads the one sentence the list expands (Q108: single-sourced copy).
        .accessibilityElement(children: .combine)
        .accessibilityLabel(SharedCopy.syncWhatSyncs)
    }

    private static func arrow(_ d: MacSyncState.Direction) -> String {
        switch d {
        case .incoming: return "↓"
        case .outgoing: return "↑"
        case .both:     return "↔"
        }
    }

    /// System Settings → Apple Account → iCloud (the pane id still resolves on macOS 15).
    private static func openICloudSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preferences.AppleIDPrefPane") {
            NSWorkspace.shared.open(url)
        }
    }

    /// The CloudKit store is built once per launch, so "try again" means a fresh process. A second
    /// instance started while this one runs would hand over and exit (SkriftDesktopApp), so a
    /// detached shell reopens the bundle a moment AFTER this process has quit.
    private static func relaunch() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", Bundle.main.bundleURL.path]
        try? p.run()
        NSApp.terminate(nil)
    }
}
