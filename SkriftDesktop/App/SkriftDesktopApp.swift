import SwiftUI
import SwiftData
import FluidAudio  // Phase 0 proof: FluidAudio (ASR) links + builds for macOS arm64.

/// One shared SwiftData container for both the UI (`@Query`) and the sync server's
/// background upload/list contexts.
enum SharedStore {
    static let container: ModelContainer = {
        do { return try ModelContainer(for: PipelineFile.self) }
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
        RunFile.runIfRequested()
        #endif
        let upload = UploadService()
        let handlers = SyncHandlers(
            namesStore: .shared,
            listFilesJSON: {
                let ctx = ModelContext(SharedStore.container)
                let files = (try? ctx.fetch(FetchDescriptor<PipelineFile>())) ?? []
                return (try? JSONEncoder().encode(files.map(\.dto))) ?? Data("[]".utf8)
            },
            handleUpload: { req in
                guard let boundary = MultipartParser.boundary(fromContentType: req.contentType) else {
                    return .status(400, "Expected multipart/form-data")
                }
                let parts = MultipartParser.parse(req.body, boundary: boundary)
                let ctx = ModelContext(SharedStore.container)
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
