import SwiftUI

/// Phase 2–3 **placeholder** record screen — plain and functional (camera, timer,
/// level meter, record/stop, pause/resume, shutter, cancel). The designed version
/// comes in the visual-polish pass; don't treat this layout as final.
struct RecordView: View {
    @StateObject private var service = RecordingService()
    @StateObject private var camera = PhotoCaptureService()
    @Environment(\.dismiss) private var dismiss
    private let saver = MemoSaver()

    var body: some View {
        VStack(spacing: 20) {
            cameraArea
                .frame(maxWidth: .infinity)
                .frame(height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal)

            Text(timeString)
                .font(.system(size: 48, weight: .light, design: .monospaced))
                .monospacedDigit()
                .accessibilityIdentifier("record-timer")

            LevelMeter(level: service.level)
                .frame(height: 44)
                .padding(.horizontal, 24)

            if service.isRecording {
                HStack(spacing: 20) {
                    Button(service.isPaused ? "Resume" : "Pause", action: togglePause)
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("pause-button")

                    Button {
                        camera.capture(offsetSeconds: service.elapsed)
                    } label: {
                        Image(systemName: "camera.fill").font(.title2)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("shutter-button")
                }

                Text("\(camera.capturedCount) photo\(camera.capturedCount == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("photo-count")
            }

            Spacer()

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
                camera.discardAll()
                dismiss()
            }
            .accessibilityIdentifier("cancel-record")
            .padding(.bottom, 8)
        }
        .padding(.vertical)
        .onAppear { camera.configure() }
        .onDisappear { camera.stop() }
    }

    @ViewBuilder private var cameraArea: some View {
        if camera.mock {
            ZStack {
                Rectangle().fill(Color.black.opacity(0.85))
                Image(systemName: "camera.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.white.opacity(0.4))
            }
            .accessibilityIdentifier("camera-placeholder")
        } else {
            CameraPreviewView(session: camera.session)
        }
    }

    private var timeString: String {
        let total = Int(service.elapsed)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private func handleRecordTap() {
        if service.isRecording {
            if let result = service.stop() {
                saver.save(tempURL: result.url, duration: result.duration, photos: camera.takeAll())
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
        return max(4, CGFloat(Double(level) * 44 * envelope))
    }
}
