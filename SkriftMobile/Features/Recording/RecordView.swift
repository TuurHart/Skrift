import SwiftUI

/// Phase 2 **placeholder** record screen — plain and functional (timer, level
/// meter, record/stop, pause/resume, cancel). The designed version comes in the
/// visual-polish pass; don't treat this layout as final.
struct RecordView: View {
    @StateObject private var service = RecordingService()
    @Environment(\.dismiss) private var dismiss
    private let saver = MemoSaver()

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            Text(timeString)
                .font(.system(size: 52, weight: .light, design: .monospaced))
                .monospacedDigit()
                .accessibilityIdentifier("record-timer")

            LevelMeter(level: service.level)
                .frame(height: 56)
                .padding(.horizontal, 24)

            Spacer()

            if service.isRecording {
                Button(service.isPaused ? "Resume" : "Pause", action: togglePause)
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("pause-button")
            }

            Button(action: handleRecordTap) {
                ZStack {
                    Circle().stroke(.red, lineWidth: 4).frame(width: 84, height: 84)
                    if service.isRecording {
                        RoundedRectangle(cornerRadius: 6).fill(.red).frame(width: 30, height: 30)
                    } else {
                        Circle().fill(.red).frame(width: 68, height: 68)
                    }
                }
            }
            .accessibilityIdentifier("record-button")
            .accessibilityLabel(service.isRecording ? "Stop recording" : "Start recording")

            Button("Cancel") {
                service.cancel()
                dismiss()
            }
            .accessibilityIdentifier("cancel-record")
            .padding(.top, 8)

            Spacer()
        }
        .padding()
    }

    private var timeString: String {
        let total = Int(service.elapsed)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private func handleRecordTap() {
        if service.isRecording {
            if let result = service.stop() {
                saver.save(tempURL: result.url, duration: result.duration)
            }
            dismiss()
        } else {
            try? service.start()
        }
    }

    private func togglePause() {
        service.isPaused ? service.resume() : service.pause()
    }
}

/// Minimal symmetric bar meter driven by the smoothed input level.
struct LevelMeter: View {
    let level: Float

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<13, id: \.self) { index in
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: 5, height: height(for: index))
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.easeOut(duration: 0.08), value: level)
        .accessibilityIdentifier("level-meter")
    }

    private func height(for index: Int) -> CGFloat {
        let center = 6.0
        let distance = abs(Double(index) - center) / center   // 0 center → 1 edge
        let envelope = 1.0 - 0.6 * distance
        return max(4, CGFloat(Double(level) * 52 * envelope))
    }
}
