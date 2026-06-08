import SwiftUI
import SwiftData
import AppKit
import FluidAudio  // Phase 0 proof: FluidAudio (ASR) links + builds for macOS arm64.

/// One shared SwiftData container for both the UI (`@Query`) and the sync server's
/// background upload/list contexts.
enum SharedStore {
    static let container: ModelContainer = {
        // Explicit store path so dev ("Skrift Dev") and prod ("Skrift") keep
        // SEPARATE SwiftData stores (AppPaths.storeFile is suffixed per build).
        let config = ModelConfiguration(url: AppPaths.storeFile)
        do { return try ModelContainer(for: PipelineFile.self, configurations: config) }
        catch { fatalError("Failed to create ModelContainer: \(error)") }
    }()
}

@main
struct SkriftDesktopApp: App {
    // The phone's sync target — local HTTP + Bonjour (plan §4).
    private let syncServer: SyncServer

    init() {
        #if DEBUG
        Snapshot.renderIfRequested()
        RunFile.runAudioDateProbeIfRequested()
        RunFile.runIfRequested()
        #endif
        // The app is dark-only (Theme tokens). Force dark appearance so EVERY
        // system-drawn control — text-field placeholders, carets, menus — renders
        // light-on-dark. Per-field foregroundStyle only fixed typed text; placeholders
        // were still following the system appearance (the recurring "black text").
        NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
        let upload = UploadService()
        let handlers = SyncHandlers(
            namesStore: .shared,
            // SwiftData isn't thread-safe across contexts. These handlers run on the
            // Bonjour server's background queue, while the UI mutates `mainContext`
            // on the main thread — concurrent writes risk store corruption. Marshal
            // all SwiftData access onto the main actor and use the SAME mainContext
            // the UI observes (so phone uploads also appear live via @Query). The
            // sync is deadlock-free: these never run on the main queue. The CPU-heavy
            // multipart parse stays off-main; only the DB touch is marshaled.
            listFilesJSON: {
                DispatchQueue.main.sync {
                    MainActor.assumeIsolated {
                        let ctx = SharedStore.container.mainContext
                        let files = (try? ctx.fetch(FetchDescriptor<PipelineFile>())) ?? []
                        return (try? JSONEncoder().encode(files.map(\.dto))) ?? Data("[]".utf8)
                    }
                }
            },
            handleUpload: { req in
                guard let boundary = MultipartParser.boundary(fromContentType: req.contentType) else {
                    return .status(400, "Expected multipart/form-data")
                }
                let parts = MultipartParser.parse(req.body, boundary: boundary)
                return DispatchQueue.main.sync {
                    MainActor.assumeIsolated {
                        let ctx = SharedStore.container.mainContext
                        do {
                            let created = try upload.ingest(parts: parts, into: ctx)
                            return .json(UploadResponseDTO(success: true, files: created.map(\.dto),
                                                           message: "Uploaded \(created.count) file(s)", errors: nil))
                        } catch {
                            return .json(UploadResponseDTO(success: false, files: [],
                                                           message: "Upload failed", errors: [String(describing: error)]),
                                         status: 500)
                        }
                    }
                }
            },
            transcriptionReady: { TranscriptionService.shared.isModelReadySync }
        )
        self.syncServer = LocalHTTPServer(handlers: handlers)
        try? syncServer.start()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .defaultSize(width: 1180, height: 780)
        .windowStyle(.hiddenTitleBar)
        .modelContainer(SharedStore.container)
    }
}
