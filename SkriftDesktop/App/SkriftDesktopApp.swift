import SwiftUI
import SwiftData
import FluidAudio  // Phase 0 proof: FluidAudio (ASR) links + builds for macOS arm64.

@main
struct SkriftDesktopApp: App {
    // The phone's sync target — local HTTP + Bonjour. Names/health served now;
    // upload wires in Phase 2b.
    private let syncServer: SyncServer = LocalHTTPServer(handlers: SyncHandlers(namesStore: .shared))

    init() {
        try? syncServer.start()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .defaultSize(width: 900, height: 600)
        .modelContainer(for: PipelineFile.self)
    }
}

struct ContentView: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("Skrift Desktop")
                .font(.largeTitle).bold()
                .accessibilityIdentifier("welcome.title")
            Text("Native rewrite — Phase 0 toolchain spike")
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("welcome.subtitle")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}
