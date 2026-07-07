import SwiftUI
import UserNotifications
import SwiftData
import UIKit

@main
struct SkriftApp: App {
    private let repository: NotesRepository
    // Registers for remote notifications so CloudKit's silent pushes wake the app and
    // NSPersistentCloudKitContainer syncs in seconds (even backgrounded) — see AppDelegate.
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage("appTheme") private var appTheme = "dark"

    init() {
        let repo = NotesRepository.shared
        DemoDataSeeder.seedIfRequested(repo)
        NamesSeeder.seedIfRequested()
        repository = repo

        // Trash retention: permanently remove memos deleted ≥ 2 weeks ago
        // (audio + photo + sidecar files included) before any UI shows them.
        repo.purgeExpiredTrash()

        // App Intents (Control Center / Siri / Live Activity Stop) run in this
        // process and call these performers, which signal the record UI via the
        // bridge. Set at launch so a cold launch via an intent finds them ready.
        StartRecordingIntent.performer = { await MainActor.run { RecordingIntentBridge.shared.requestStart() } }
        ResumeAudiobookIntent.performer = { await MainActor.run { AudiobookSession.shared.resumeLastPlayed() } }
        StopRecordingIntent.performer = { await MainActor.run { RecordingIntentBridge.shared.requestStop() } }

        // Register the whole-book background-transcribe handler before the scene
        // connects (BGTaskScheduler requires registration at launch).
        BookBackgroundScheduler.register()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .modelContainer(repository.container)
                .preferredColorScheme(colorScheme)
                .tint(.skAccent)
                .onOpenURL { AppURLHandler.handle($0) }
                // Clear any Live Activity orphaned by a kill mid-recording (iOS
                // keeps the banner alive after the process dies).
                .task { RecordingActivityManager.shared.reapOrphans() }
                // Drain the capture inbox whenever the app becomes active: covers
                // both cold launch and every background→foreground transition. The
                // share extension writes inbox entries into the App Group container;
                // we convert them to Memos here and delete the entries after save —
                // see Services/Capture/CaptureInbox.swift for the crash-safety model.
                .task { CaptureInboxDrainer.drain(into: repository) }
                // Reconcile CloudKit-mirrored media (Phase 1c): write any synced
                // MemoAsset blobs that arrived from another device to disk, and
                // capture any local audio/photos that have no asset yet (incl.
                // migrating pre-1c memos). Idempotent; mirrors the inbox drainer's
                // launch + foreground cadence below.
                .task {
                    AssetMaterializer.run(repository)
                    PhotoTextIndexer.run(repository)
                    ReminderScheduler.run(repository)
                }
                // Reconcile the names/people DB across devices (Phase 1e): merge the
                // CloudKit-synced carrier with the local names.json via the same
                // NamesMerge the Mac sync uses. Idempotent; launch + foreground.
                .task { NamesCloudSync.run(repository) }
                // Sync the custom-vocabulary list across devices (Phase 1f), LWW.
                .task { VocabularyCloudSync.run(repository) }
                // Reconcile opted-in audiobooks (Phase 1h): upload a freshly-synced
                // book's audio + pull any that arrived from another device (raw-CloudKit
                // transfer). No-op when nothing's synced. Idempotent; launch + foreground.
                .task { await AudiobookCloudSync.reconcile(repository: repository) }
                // Recover any recording orphaned mid-transcription by a process
                // kill: a fire-and-forget transcription Task can't survive app
                // suspension, so a cold-launch auto-record stopped before the
                // model loaded (then backgrounded) strands the memo at
                // `.transcribing` forever (2026-06-16 device bug). Any memo still
                // `.transcribing` at launch is orphaned by definition — re-run it.
                // Skipped on the seeded sim/UI-test path (no Neural Engine).
                .task {
                    if LaunchFlags.seedTranscript == nil {
                        await MemoSaver().recoverStuckTranscriptions()
                    }
                }
                // Recover any diarization orphaned mid-identify: "Split speakers" runs
                // in a fire-and-forget Task that dies if the user backgrounds the app
                // while it's identifying speakers (2026-06-21 device bug). Any memo
                // still marked in-flight at launch is re-diarized. Sim/UI-test skip.
                .task {
                    if LaunchFlags.seedTranscript == nil {
                        await MemoSaver().recoverStuckDiarizations()
                    }
                }
                // Pre-warm the custom-vocabulary booster when the user has custom
                // words, so the FIRST recording this session is boosted. The
                // booster is non-blocking (it skips the first, model-loading
                // transcribe) — the device bug "custom vocab never corrected"
                // (2026-06-13) was that it was never warm when a memo transcribed.
                // Skipped on the seeded sim/UI-test path (no Neural Engine).
                .task {
                    if LaunchFlags.seedTranscript == nil {
                        let words = CustomVocabularyStore.words()
                        if !words.isEmpty {
                            await VocabularyBooster.shared.prewarm(words: words)
                        }
                    }
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        CaptureInboxDrainer.drain(into: repository)
                        AssetMaterializer.run(repository)
                        PhotoTextIndexer.run(repository)
                        ReminderScheduler.run(repository)
                        NamesCloudSync.run(repository)
                        VocabularyCloudSync.run(repository)
                        Task { await AudiobookCloudSync.reconcile(repository: repository) }
                        // P8 retrieval index — inert until the Journal UI's consent
                        // flow enables it AND the model is on disk (no surprise 295 MB).
                        JournalIndexService.shared.sweepSoon(repository)
                    } else if newPhase == .background {
                        // If a whole-book transcribe is in flight, ask iOS to let it
                        // continue in the background (best overnight on a charger).
                        BookBackgroundScheduler.scheduleIfNeeded()
                    }
                }
        }
    }

    @Environment(\.scenePhase) private var scenePhase

    // The palette is dark-first (explicit dark surfaces), so "auto"/"light" are
    // best-effort until a light palette lands; default stays dark.
    private var colorScheme: ColorScheme? {
        switch appTheme {
        case "light": return .light
        case "auto": return nil
        default: return .dark
        }
    }
}

/// App shell. The root is a tab bar (audiobook reading-mode redesign 2026-06-19):
/// Notes · Library · Highlights(soon) · Settings — see `AppTabView`. Record
/// presents over the Notes tab, Memo detail pushes from a card. First launch shows
/// onboarding.
struct RootView: View {
    @State private var needsOnboarding = RootView.shouldOnboard()

    var body: some View {
        if LaunchFlags.conversationMock {
            ConversationMockView()           // design mock (screenshot only)
        } else if LaunchFlags.seedNameLinking {
            // Screenshot route: open the seeded "Studio afternoon" memo straight into the
            // in-place name-linking surface.
            NavigationStack { MemoDetailView(initialID: DemoDataSeeder.nameLinkingMemoID) }
        } else if LaunchFlags.seedPolished {
            // Screenshot route: open the seeded polished memo (Phase 4 display).
            NavigationStack { MemoDetailView(initialID: DemoDataSeeder.polishedMemoID) }
        } else if LaunchFlags.threadDemo {
            // Screenshot route: the P8 thread for the seeded pricing memo
            // (combine with -seedJournal -mockJournalIndex).
            ThreadView(seedID: DemoDataSeeder.journalPricingMemoID)
        } else if LaunchFlags.journalMemoDemo {
            // Screenshot route: the seeded pricing memo's detail — the P8
            // Related card in the footer (combine with -seedJournal -mockJournalIndex).
            NavigationStack { MemoDetailView(initialID: DemoDataSeeder.journalPricingMemoID) }
        } else if needsOnboarding {
            OnboardingView {
                UserDefaults.standard.set(true, forKey: "onboardingComplete")
                withAnimation(Theme.Motion.spring) { needsOnboarding = false }
            }
        } else {
            AppTabView()
        }
    }

    private static func shouldOnboard() -> Bool {
        if LaunchFlags.skipOnboarding { return false }
        if LaunchFlags.forceOnboarding { return true }
        if LaunchFlags.inMemoryStore { return false }   // UI tests auto-skip
        return !UserDefaults.standard.bool(forKey: "onboardingComplete")
    }
}

/// Registers for remote notifications at launch so CloudKit's silent pushes (standalone
/// Phase 1) wake the app and `NSPersistentCloudKitContainer` syncs within seconds —
/// even backgrounded — instead of on its lazy periodic schedule. The container creates
/// the CloudKit subscription itself; this just gets the app delivered the pushes.
///
/// Requires the **Push Notifications** capability (added once in Xcode → Signing &
/// Capabilities, which also writes `aps-environment` to the entitlements) + the
/// `remote-notification` background mode (project.yml). On the Simulator registration
/// no-ops; no effect until the capability is present, so this is safe to ship now.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UIApplication.shared.registerForRemoteNotifications()
        // Reminder taps → open the memo; foreground reminders still banner.
        UNUserNotificationCenter.current().delegate = ReminderScheduler.delegate
        return true
    }
}
