import SwiftUI
import AVFoundation
import CoreLocation

/// First-run onboarding (mockup4): permissions (mic/camera, location/motion),
/// pair a Mac (Bonjour), and the one-time transcription-model download. None of
/// it blocks — "Get started" always proceeds; steps are best-effort. Real
/// permission grants + the 494 MB model download are device-owed.
struct OnboardingView: View {
    let onDone: () -> Void

    @StateObject private var discovery = MacDiscovery()
    @State private var mediaGranted = false
    @State private var locationRequested = false
    @State private var paired = MacConnection.load() != nil
    @ObservedObject private var modelStatus = ModelLoadStatus.shared
    @State private var modelRequested = false
    private let locationManager = CLLocationManager()

    var body: some View {
        ZStack {
            Color.skBg.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                logo.padding(.top, 14)
                Text("Welcome to Skrift")
                    .font(.system(size: 26, weight: .bold)).foregroundStyle(Color.skText)
                    .padding(.top, 18)
                Text("Record voice memos, transcribed on-device, synced to your Mac. A couple of quick steps:")
                    .font(.subheadline).foregroundStyle(Color.skTextDim)
                    .padding(.top, 8)

                VStack(spacing: 10) {
                    stepCard(icon: "mic.fill", title: "Microphone & Camera", desc: "To record and snap photos") {
                        if mediaGranted { doneBadge } else { allowButton("allow-media", action: requestMedia) }
                    }
                    stepCard(icon: "location.fill", title: "Location & Motion", desc: "Tags memos with place, weather, steps") {
                        if locationRequested { doneBadge } else { allowButton("allow-location", action: requestLocation) }
                    }
                    stepCard(icon: "desktopcomputer", title: "Pair your Mac", desc: pairDesc) {
                        if paired { doneBadge } else if discovery.macs.first != nil {
                            Button("Connect", action: connectMac)
                                .font(.system(size: 12.5, weight: .bold)).foregroundStyle(Color.skAccent)
                                .accessibilityIdentifier("onboard-connect")
                        } else {
                            Text("Searching…").font(.system(size: 12.5)).foregroundStyle(Color.skTextFaint)
                        }
                    }
                    stepCard(icon: "arrow.down.circle.fill", title: "Transcription model", desc: modelDesc) {
                        if modelStatus.ready {
                            doneBadge
                        } else if let progress = modelStatus.downloadProgress {
                            ProgressView(value: progress)
                                .progressViewStyle(.linear)
                                .frame(width: 64).tint(.skAccent)
                        } else if modelRequested {
                            ProgressView().controlSize(.small).tint(.skAccent)
                        } else {
                            Button("Get", action: downloadModel)
                                .font(.system(size: 12.5, weight: .bold)).foregroundStyle(Color.skAccent)
                        }
                    }
                }
                .padding(.top, 22)

                Spacer()

                Button(action: onDone) {
                    Text("Get started")
                        .font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 15)
                        .background(Color.skAccent, in: .rect(cornerRadius: Theme.Radius.card, style: .continuous))
                        .shadow(color: .skAccent.opacity(0.4), radius: 10, y: 6)
                }
                .accessibilityIdentifier("get-started-button")
                .padding(.bottom, 26)
            }
            .padding(.horizontal, 22)
        }
        .onAppear { discovery.start() }
        .onDisappear { discovery.stop() }
    }

    private var logo: some View {
        RoundedRectangle.sk(16)
            .fill(LinearGradient(colors: [.skAccent, Color(hex: 0x9d8bff)], startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: 60, height: 60)
            .overlay(Text("S").font(.system(size: 30, weight: .black)).foregroundStyle(.white))
    }

    private func stepCard<Trailing: View>(icon: String, title: String, desc: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16)).foregroundStyle(Color.skAccentText)
                .frame(width: 36, height: 36)
                .background(Color.skAccentSoft, in: .rect(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 14.5, weight: .semibold)).foregroundStyle(Color.skText)
                Text(desc).font(.system(size: 12)).foregroundStyle(Color.skTextFaint)
            }
            Spacer()
            trailing()
        }
        .padding(.horizontal, 13).padding(.vertical, 12)
        .background(Color.skSurface, in: .rect(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle.sk(14).stroke(Color.skBorder, lineWidth: 1))
    }

    private var doneBadge: some View {
        Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).foregroundStyle(Color.skGreen)
    }

    private func allowButton(_ id: String, action: @escaping () -> Void) -> some View {
        Button("Allow", action: action)
            .font(.system(size: 12.5, weight: .bold)).foregroundStyle(Color.skAccent)
            .accessibilityIdentifier(id)
    }

    private var pairDesc: String {
        if let conn = MacConnection.load() { return "Connected · \(conn.host)" }
        if let mac = discovery.macs.first { return "Found “\(mac.name)” on your Wi-Fi" }
        return "On the same Wi-Fi as your Mac"
    }

    private var modelDesc: String {
        if modelStatus.ready { return "Ready · on-device" }
        if let p = modelStatus.downloadProgress { return "Downloading · 494 MB · \(Int(p * 100))%" }
        return "494 MB · one-time, on-device"
    }

    // MARK: - Actions (best-effort; real grants are device-owed)

    private func requestMedia() {
        Task {
            _ = await AVAudioApplication.requestRecordPermission()
            _ = await AVCaptureDevice.requestAccess(for: .video)
            mediaGranted = true
        }
    }

    private func requestLocation() {
        locationManager.requestWhenInUseAuthorization()
        locationRequested = true
    }

    private func connectMac() {
        guard let mac = discovery.macs.first else { return }
        Task {
            if let conn = await discovery.resolve(mac) { conn.save(); paired = true }
        }
    }

    private func downloadModel() {
        modelRequested = true
        // Progress + ready come from ModelLoadStatus (driven by TranscriptionService).
        Task { try? await TranscriptionService.shared.ensureLoaded() }
    }
}
