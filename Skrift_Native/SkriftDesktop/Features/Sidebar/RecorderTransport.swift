import SwiftUI

/// The sidebar's live-take transport (Q328, signed mock `mocks/Q289-mac-recorder-pause.html`,
/// D182): discard x on the left, dot, elapsed, meter, pause / resume, stop. Paused drains the
/// red (chip fill, hollow still dot, grey time) and swaps the meter for the word "Paused".
/// The x asks "Discard this recording?" in a popover anchored to it.
///
/// A pure value view (every fact a parameter) so `-snapshot-recorder` can render each state
/// without a microphone; `SidebarView` feeds it from the live session.
struct RecorderTransport: View {
    var elapsedLabel: String
    var meter: RecordingCore.Meter
    var isPaused: Bool
    /// `.starting`: no file yet, so x and pause are inert (Stop stays, as before).
    var controlsEnabled: Bool = true
    @Binding var isAsking: Bool
    var onAskDiscard: () -> Void
    var onKeep: () -> Void
    var onDiscard: () -> Void
    var onTogglePause: () -> Void
    var onStop: () -> Void

    @State private var pulse = false

    var body: some View {
        HStack(spacing: 8) {
            discardButton
            dot
            Text(elapsedLabel)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(isPaused ? Theme.textSecondary : Theme.destructive)
                .monospacedDigit()
                .frame(minWidth: 30, alignment: .leading)
            if isPaused {
                Text("Paused")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(alignment: .center, spacing: 2) {
                    ForEach(0..<meter.width, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Theme.destructive.opacity(0.55))
                            .frame(height: 16 * meter.height(at: i))
                    }
                }
                .frame(height: 16)
            }
            pauseButton
            stopButton
        }
        .padding(.horizontal, 11).padding(.vertical, 9)
        .frame(height: 40)
        .background(isPaused ? Theme.chip : Theme.destructive.opacity(0.11),
                    in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10)
            .stroke(isPaused ? Theme.hairline.opacity(0.10) : Theme.destructive.opacity(0.3), lineWidth: 1))
        .onAppear { pulse = true }
        .onDisappear { pulse = false }
    }

    @ViewBuilder private var dot: some View {
        if isPaused {
            Circle().strokeBorder(Theme.textMuted, lineWidth: 1.5).frame(width: 9, height: 9)
        } else {
            Circle().fill(Theme.destructive).frame(width: 9, height: 9)
                .opacity(pulse ? 0.35 : 1)
                .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: pulse)
        }
    }

    private var discardButton: some View {
        Button(action: onAskDiscard) {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(isAsking ? Theme.destructive : Theme.textSecondary)
                .frame(width: 22, height: 22)
                .background(isAsking ? Theme.destructive.opacity(0.16) : Theme.hairline.opacity(0.07),
                            in: RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .disabled(!controlsEnabled)
        .help("Discard recording")
        .accessibilityLabel("Discard recording")
        .accessibilityIdentifier("sidebar.record.discard")
        .popover(isPresented: $isAsking, arrowEdge: .bottom) {
            RecorderDiscardPopover(elapsedLabel: elapsedLabel, onKeep: onKeep, onDiscard: onDiscard)
        }
    }

    private var pauseButton: some View {
        Button(action: onTogglePause) {
            Image(systemName: isPaused ? "play.fill" : "pause.fill")
                .font(.system(size: 10))
                .foregroundStyle(Theme.destructive)
                .frame(width: 22, height: 22)
                .background(Theme.destructive.opacity(0.16), in: RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .disabled(!controlsEnabled)
        .help(isPaused ? "Resume" : "Pause")
        .accessibilityLabel(isPaused ? "Resume" : "Pause")
        .accessibilityIdentifier("sidebar.record.pause")
    }

    private var stopButton: some View {
        Button(action: onStop) {
            RoundedRectangle(cornerRadius: 1.5).fill(.white).frame(width: 8, height: 8)
                .frame(width: 22, height: 22)
                .background(Theme.destructive, in: RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .help("Stop and save")
        .accessibilityLabel("Stop and save")
        .accessibilityIdentifier("sidebar.record.stop")
    }
}

/// The question itself. Keep is the default (Return) and Esc; Discard is red and never the
/// default (D182). Also drawn on its own by `-snapshot-recorder`, since a popover window
/// does not render in a headless image.
struct RecorderDiscardPopover: View {
    var elapsedLabel: String
    var onKeep: () -> Void
    var onDiscard: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Discard this recording?")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
            Text("\(elapsedLabel) of audio and the words so far are deleted. You can’t undo this.")
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 7) {
                Button(action: onDiscard) {
                    Text("Discard")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Theme.destructive)
                        .frame(maxWidth: .infinity, minHeight: 30)
                        .background(Theme.destructive.opacity(0.11), in: RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("sidebar.record.discard.confirm")
                Button(action: onKeep) {
                    Text("Keep")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 30)
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("sidebar.record.discard.keep")
            }
            .padding(.top, 9)
        }
        .padding(.horizontal, 13).padding(.top, 13).padding(.bottom, 12)
        .frame(width: 232)
        .background(Theme.surface)
        // Esc closes a popover, which the binding turns into Keep — the same verb.
    }
}
