import SwiftUI
import SwiftData
import AppKit

/// One shared SwiftData container for the UI (`@Query`) and the background ingest /
/// reconcile contexts.
enum SharedStore {
    static let container: ModelContainer = {
        #if DEBUG
        // Q37: `-isolatedRun` — see MemoCloudStore's twin flag — keeps the local
        // pipeline store in memory too, so a corpus-seeded eyeball run never writes
        // into the real Dev pipeline store on disk.
        if LaunchArgs.isolatedRun {
            let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
            do { return try ModelContainer(for: PipelineFile.self, configurations: config) }
            catch { fatalError("Failed to create isolated ModelContainer: \(error)") }
        }
        #endif
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

    init() {
        #if DEBUG
        Snapshot.renderIfRequested()
        RunFile.runChunkSimIfRequested()
        RunFile.runReadAlongCheckIfRequested()
        RunFile.runAsrBenchIfRequested()
        RunFile.runAsrSweepIfRequested()
        RunFile.runVaultExportIfRequested()
        RunFile.runProcessFileIfRequested()
        RunFile.runIngestFileIfRequested()
        RunFile.runRecordIngestIfRequested()
        RunFile.runTrashFileIfRequested()
        RunFile.runRateFileIfRequested()
        RunFile.runFlagMemoIfRequested()
        RunFile.runRateToRowIfRequested()
        RunFile.runAlignCheckIfRequested()
        RunFile.runIfRequested()
        #endif
        // SECOND-INSTANCE GUARD — two processes on one SwiftData store race it
        // (was only a "quit the app first" discipline rule). Normal GUI launches
        // only: headless modes pass arguments and XCTest sets its env; both keep
        // their own lifecycle. The existing instance is activated instead.
        if ProcessInfo.processInfo.arguments.count == 1,
           !LaunchArgs.isXCTest {
            let others = NSRunningApplication.runningApplications(
                withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
                .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
            if let existing = others.first {
                existing.activate()
                exit(0)
            }
        }

        // Apply the saved theme to the AppKit layer at launch so EVERY system-drawn
        // control (text-field placeholders, carets, menus) matches — they follow
        // NSApp.appearance, not SwiftUI's colorScheme. RootView keeps it in sync on
        // change; "auto" (nil) follows the system.
        AppTheme.applyToApp()

        // CloudKit-Mac client (MAC_CLOUDKIT_PLAN.md 8d): register the launch/foreground/import
        // reconcile triggers + run the launch sweep. A no-op when the user switched
        // `cloudKitMacSync` off (it defaults ON). CloudKit is the ONLY phone↔Mac transport
        // (the Bonjour/HTTP server is retired) — it carries memos, names, and vocabulary.
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
        .commands {
            // Q126: the phone's ☑ on the Mac. Only the focused note's text view answers.
            CommandMenu("Format") {
                Button("Checklist") {
                    NSApp.sendAction(#selector(SelfSizingTextView.toggleChecklist(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])
            }
            // Q125 (D125) + Q284 (D169): Cmd+F finds in the open note while a note's text view has
            // focus (the responder chain answers), and focuses the list search everywhere else.
            CommandGroup(after: .textEditing) {
                Button(NoteFindBar.Verb.show.title) {
                    if NoteFindBar.noteTextHasFocus { NoteFindBar.send(.show) } else { MacShortcutAction.search.post() }
                }
                .keyboardShortcut(AppShortcuts.search)
                Button(NoteFindBar.Verb.next.title) { NoteFindBar.send(.next) }
                    .keyboardShortcut("g", modifiers: .command)
                Button(NoteFindBar.Verb.previous.title) { NoteFindBar.send(.previous) }
                    .keyboardShortcut("g", modifiers: [.command, .shift])
            }
            // D169: New note replaces the WindowGroup's "New Window" (single-window app) so Cmd+N
            // is ONE binding, working from Review too; Record is its Shift sibling.
            CommandGroup(replacing: .newItem) {
                Button("New Note") { MacShortcutAction.newNote.post() }
                    .keyboardShortcut(AppShortcuts.newNote)
            }
            CommandMenu("Record") {
                Button("Start / Stop Recording") { MacShortcutAction.record.post() }
                    .keyboardShortcut(AppShortcuts.record)
            }
            CommandGroup(before: .toolbar) {
                Button("Notes") { MacShortcutAction.notes.post() }
                    .keyboardShortcut(AppShortcuts.macNotes)
                Button("Review") { MacShortcutAction.review.post() }
                    .keyboardShortcut(AppShortcuts.macReview)
                Divider()
            }
        }
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
