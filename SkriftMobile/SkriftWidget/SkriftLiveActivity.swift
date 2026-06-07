import ActivityKit
import SkriftShared
import SwiftUI
import WidgetKit

// Skrift tokens (the widget target can't see the app's DesignSystem; the few
// colors are inlined). accent #7c6bf5, red #ef4444, amber #f59e0b, pill #15161d.
private enum SK {
    static let accent = Color(red: 0.486, green: 0.420, blue: 0.961)
    static let red = Color(red: 0.937, green: 0.267, blue: 0.267)
    static let amber = Color(red: 0.961, green: 0.620, blue: 0.043)
    static let pill = Color(red: 0.082, green: 0.086, blue: 0.114)
    static let recordURL = URL(string: "skrift://record")
}

/// Recording Live Activity (Lock Screen banner + Dynamic Island). Display-only in
/// 8a — the whole surface deep-links to `skrift://record` to bring the app
/// forward; the interactive Stop button (a `StopRecordingIntent`) arrives in 8b.
struct SkriftLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RecordingActivityAttributes.self) { context in
            lockScreen(context.state)
                .activityBackgroundTint(SK.pill)
                .activitySystemActionForegroundColor(.white)
                .widgetURL(SK.recordURL)
        } dynamicIsland: { context in
            let paused = context.state.status == .paused
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        Waveform(size: 16, paused: paused)
                        Text(paused ? "Paused" : "Recording")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    timer(context.state).font(.system(size: 13, weight: .semibold, design: .monospaced))
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.caption.isEmpty ? "Listening…" : context.state.caption)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.45))
                        .lineLimit(1)
                        .truncationMode(.head)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } compactLeading: {
                Waveform(size: 14, paused: paused)
            } compactTrailing: {
                Circle().fill(paused ? SK.amber : SK.red).frame(width: 8, height: 8)
            } minimal: {
                Waveform(size: 14, paused: paused)
            }
            .keylineTint(SK.accent)
            .widgetURL(SK.recordURL)
        }
    }

    private func lockScreen(_ state: RecordingActivityAttributes.ContentState) -> some View {
        let paused = state.status == .paused
        return HStack(spacing: 12) {
            Waveform(size: 22, paused: paused).frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    timer(state).font(.system(size: 14, weight: .semibold, design: .monospaced))
                    if paused {
                        Text("· Paused").font(.system(size: 13, weight: .semibold)).foregroundStyle(SK.amber)
                    }
                }
                Text(state.caption.isEmpty ? "Listening…" : state.caption)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Circle().fill(paused ? SK.amber : SK.red).frame(width: 10, height: 10)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    /// Live count-up timer; freezes at `pausedAt` while paused.
    @ViewBuilder private func timer(_ state: RecordingActivityAttributes.ContentState) -> some View {
        Text(timerInterval: state.startedAt...Date.distantFuture,
             pauseTime: state.pausedAt, countsDown: false)
            .foregroundStyle(state.status == .paused ? SK.amber : .white.opacity(0.9))
            .monospacedDigit()
    }
}

/// Self-animating waveform (TimelineView — `.symbolEffect` isn't reliable in a
/// widget). Amber + still while paused, accent + moving while recording.
private struct Waveform: View {
    let size: CGFloat
    var paused: Bool = false
    private let bars = 5

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.08, paused: paused)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: max(1, size * 0.09)) {
                ForEach(0..<bars, id: \.self) { i in
                    let phase = t * 4 + Double(i) * 0.6
                    let norm = paused ? 0.5 : 0.45 + 0.55 * (sin(phase) * 0.5 + 0.5)
                    Capsule()
                        .fill((paused ? SK.amber : SK.accent).opacity(paused ? 0.5 : 0.9))
                        .frame(width: max(1.5, size * 0.13), height: size * CGFloat(norm))
                }
            }
            .frame(width: size * 1.4, height: size, alignment: .center)
        }
    }
}
