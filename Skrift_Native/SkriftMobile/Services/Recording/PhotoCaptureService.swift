import AVFoundation
import Combine
import Foundation
import UIKit

/// Captures timestamped photos during recording. Each capture records the photo's
/// recording-time offset (paused time excluded — supplied by the caller). On save
/// these become the `imageManifest` and drive `[[img_NNN]]` marker placement.
///
/// In **mock mode** (`-seedTranscript`) it skips the camera entirely (the Simulator
/// has none) and writes a tiny placeholder JPEG, so the capture→offset→manifest
/// pipeline is UI-testable. Real capture is device-owed.
@MainActor
final class PhotoCaptureService: NSObject, ObservableObject {
    @Published private(set) var capturedCount = 0
    @Published private(set) var isReady = false

    let mock: Bool
    let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let sessionQueue = DispatchQueue(label: "skrift.camera.session")
    private var captured: [(url: URL, offset: Double)] = []
    private var pendingOffsets: [Double] = []
    private var videoDevice: AVCaptureDevice?
    private var lastCaptureAt: Date?

    init(mock: Bool = LaunchFlags.seedTranscript != nil) {
        self.mock = mock
        super.init()
    }

    func configure() {
        guard !mock else {
            isReady = true
            return
        }
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.session.beginConfiguration()
            self.session.sessionPreset = .photo
            if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
               let input = try? AVCaptureDeviceInput(device: device),
               self.session.canAddInput(input) {
                self.session.addInput(input)
                self.videoDevice = device
            }
            if self.session.canAddOutput(self.photoOutput) {
                self.session.addOutput(self.photoOutput)
            }
            self.session.commitConfiguration()
            self.session.startRunning()
            Task { @MainActor in self.isReady = true }
        }
    }

    func stop() {
        guard !mock else { return }
        sessionQueue.async { [weak self] in self?.session.stopRunning() }
    }

    /// Set the optical/digital zoom factor (e.g. 0.5/1/2). Device-only; clamped
    /// to the camera's supported range. No-op in the camera-less mock.
    func setZoom(_ factor: CGFloat) {
        guard !mock else { return }
        sessionQueue.async { [weak self] in
            guard let device = self?.videoDevice else { return }
            do {
                try device.lockForConfiguration()
                let clamped = max(device.minAvailableVideoZoomFactor, min(factor, device.maxAvailableVideoZoomFactor))
                device.videoZoomFactor = clamped
                device.unlockForConfiguration()
            } catch {}
        }
    }

    func capture(offsetSeconds: Double) {
        // Debounce: a single shutter tap was firing twice on device.
        let now = Date()
        if let last = lastCaptureAt, now.timeIntervalSince(last) < 0.6 { return }
        lastCaptureAt = now

        if mock {
            let url = AppPaths.recordingsDirectory.appendingPathComponent("cap_\(UUID().uuidString).jpg")
            let image = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { ctx in
                UIColor.darkGray.setFill()
                ctx.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
            }
            if let data = image.jpegData(compressionQuality: 0.6) {
                try? data.write(to: url)
                captured.append((url, offsetSeconds))
                capturedCount = captured.count
            }
            return
        }
        pendingOffsets.append(offsetSeconds)
        photoOutput.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
    }

    /// Hand off the captured photos and clear internal state.
    func takeAll() -> [(url: URL, offset: Double)] {
        let out = captured
        captured.removeAll()
        capturedCount = 0
        return out
    }

    func discardAll() {
        for item in captured { try? FileManager.default.removeItem(at: item.url) }
        captured.removeAll()
        capturedCount = 0
    }
}

extension PhotoCaptureService: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        guard error == nil, let data = photo.fileDataRepresentation() else { return }
        let url = AppPaths.recordingsDirectory.appendingPathComponent("cap_\(UUID().uuidString).jpg")
        try? data.write(to: url)
        Task { @MainActor in
            let offset = self.pendingOffsets.isEmpty ? 0 : self.pendingOffsets.removeFirst()
            self.captured.append((url, offset))
            self.capturedCount = self.captured.count
        }
    }
}
