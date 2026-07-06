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
        // cloudKitDatabase: .none is REQUIRED, not cosmetic: this is the LOCAL pipeline store
        // and PipelineFile has @Attribute(.unique) id, which CloudKit forbids. Once the app
        // gained the CloudKit entitlement (for the separate MemoCloudStore), the DEFAULT
        // .automatic started resolving to "CloudKit on" here too → ModelContainer init
        // fatal-errors on the unique constraint. .none pins this store local regardless.
        let config = ModelConfiguration(url: AppPaths.storeFile, cloudKitDatabase: .none)
        do { return try ModelContainer(for: PipelineFile.self, configurations: config) }
        catch { fatalError("Failed to create ModelContainer: \(error)") }
    }()
}

@main
struct SkriftDesktopApp: App {
    // Registers for CloudKit silent push at launch (MAC_CLOUDKIT_PLAN.md 8d) — the macOS
    // mirror of the phone's AppDelegate. Without it the Mac's NSPersistentCloudKitContainer
    // syncs LAZILY (minutes); with it, a synced memo lands in seconds, even unfocused.
    @NSApplicationDelegateAdaptor(MacAppDelegate.self) private var appDelegate

    // The phone's sync target — local HTTP + Bonjour (plan §4).
    private let syncServer: SyncServer

    init() {
        #if DEBUG
        Snapshot.renderIfRequested()
        RunFile.runChunkSimIfRequested()
        RunFile.runReadAlongCheckIfRequested()
        RunFile.runAsrBenchIfRequested()
        RunFile.runAsrSweepIfRequested()
        RunFile.runParagraphDemoIfRequested()
        RunFile.runAudioDateProbeIfRequested()
        RunFile.runVoiceLoopIfRequested()
        RunFile.runProcessFileIfRequested()
        RunFile.runIfRequested()
        #endif
        // Apply the saved theme to the AppKit layer at launch so EVERY system-drawn
        // control (text-field placeholders, carets, menus) matches — they follow
        // NSApp.appearance, not SwiftUI's colorScheme. RootView keeps it in sync on
        // change; "auto" (nil) follows the system.
        AppTheme.applyToApp()
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
                // ENFORCE the "never on main" invariant the deadlock-freedom of
                // this `.sync` depends on: if a future refactor ever routes a
                // handler onto the main queue, this fires a clear crash instead
                // of a silent deadlock (the comment above was the only guard).
                dispatchPrecondition(condition: .notOnQueue(.main))
                return DispatchQueue.main.sync {
                    MainActor.assumeIsolated {
                        let ctx = SharedStore.container.mainContext
                        // Exclude soft-deleted (Recently Deleted) files — the phone
                        // must not re-see a note the user trashed on the Mac.
                        let all = (try? ctx.fetch(FetchDescriptor<PipelineFile>())) ?? []
                        let live = all.filter { $0.deletedAt == nil }
                        return (try? JSONEncoder().encode(live.map(\.dto))) ?? Data("[]".utf8)
                    }
                }
            },
            handleUpload: { req in
                guard let boundary = MultipartParser.boundary(fromContentType: req.contentType) else {
                    return .status(400, "Expected multipart/form-data")
                }
                let parts = MultipartParser.parse(req.body, boundary: boundary)
                dispatchPrecondition(condition: .notOnQueue(.main))
                // Phase 1 — write the audio/images/sidecars to disk OFF the main
                // actor (a memo can be many MB; doing this inside the main-sync below
                // would stall the UI). Only the light SwiftData insert/save is marshaled.
                let prepared: [UploadService.PreparedUpload]
                do {
                    prepared = try upload.prepare(parts: parts)
                } catch {
                    return .json(UploadResponseDTO(success: false, files: [],
                                                   message: "Upload failed", errors: [String(describing: error)]),
                                 status: 500)
                }
                // Phase 2 — SwiftData only, on the main actor with the UI's mainContext.
                return DispatchQueue.main.sync {
                    MainActor.assumeIsolated {
                        let ctx = SharedStore.container.mainContext
                        do {
                            let created = try upload.commit(prepared, into: ctx)
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
        // Bonjour/HTTP is the legacy LAN path — OFF by default now that names + memos sync over
        // CloudKit. Only advertise/serve it when the user explicitly re-enables the fallback.
        if SettingsStore.shared.load().bonjourFallbackEnabled {
            try? syncServer.start()
        }

        // CloudKit-Mac client (MAC_CLOUDKIT_PLAN.md 8d): register the launch/foreground/import
        // reconcile triggers + run the launch sweep. Inert (no-op) unless the user opted into
        // `cloudKitMacSync` — the Bonjour server above stays the default path, and the two
        // coexist (MemoCloudIngest dedups a memo seen via both transports).
        MemoCloudReconciler.start()

        // Pre-warm the custom-vocabulary booster at launch when the user has
        // custom words. The booster is NON-BLOCKING (it skips the first,
        // model-loading transcribe), so without this the first processed file
        // goes unboosted while the ~97 MB CTC model loads. The device bug
        // "custom vocab never corrected" (2026-06-13) was exactly this — the
        // booster was never warm when transcription ran. Idempotent; off the
        // main thread; harmless under headless `-runfile` (which prewarms itself).
        let vocabWords = SettingsStore.shared.load().customWords
        if !vocabWords.isEmpty {
            Task.detached(priority: .utility) { await VocabularyBooster.shared.prewarm(words: vocabWords) }
        }
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

/// Registers for remote notifications so CloudKit silent pushes wake the app + drive a prompt
/// import (then `MemoCloudReconciler`'s eventChangedNotification observer ingests). Mirrors the
/// phone's `AppDelegate`. Requires the Push Notifications capability (writes `aps-environment`,
/// enables the App ID) — already added; registration no-ops otherwise, so it's safe regardless.
/// NSPersistentCloudKitContainer creates + owns the CloudKit subscription; once registered, the
/// system delivers its silent pushes and the container imports — no manual push handling needed.
final class MacAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.registerForRemoteNotifications()
    }

    func application(_ application: NSApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        print("[Push] registered for remote notifications (\(deviceToken.count)-byte token)")
    }

    func application(_ application: NSApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("[Push] failed to register: \(error.localizedDescription)")
    }
}
