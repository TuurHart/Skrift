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
    @AppStorage(PrefKey.appTheme) private var appTheme = PrefKey.appThemeDefault
    /// 📦 Holds a `.skriftbook` that arrived over AirDrop / Files / Messages until
    /// the user says yes to it.
    @StateObject private var bookImport = BookImportBridge.shared
    /// Holds 2+ voice notes (Files pick / AirDrop burst) until the user answers One note / N notes.
    @StateObject private var audioPick = AudioPickBridge.shared
    #if DEBUG
    /// Q313: holds the app root back while `-perfLibrary` seeds its store (first launch only).
    @StateObject private var perfLibrary = PerfLibraryLaunch.shared
    #endif

    init() {
        let repo = NotesRepository.shared
        #if DEBUG
        // Test/screenshot seeders: compiled out of Release, so a production launch never
        // fetches the memo list or reads a seed flag.
        DemoDataSeeder.seedIfRequested(repo)
        NamesSeeder.seedIfRequested()
        DestinationSettings.resetIfRequested()
        PortfolioVault.seedIfRequested()
        #endif
        repository = repo
        #if DEBUG
        // Q313: `-perfLibrary` seeds its separate store off the main thread (a no-op otherwise).
        PerfLibraryLaunch.shared.begin(container: repo.container, isUsable: repo.isUsable)
        // The synthetic corpus (test-fixtures/corpus): `-corpus <path>` seeds it into THIS
        // store — the v2 rewrite's change detector. Idempotent by memo id.
        if let corpus = CorpusSeed.launchPath {
            let outcome = (try? CorpusSeed.seed(from: corpus, into: repo.context,
                                                recordingsDirectory: AppPaths.recordingsDirectory,
                                                names: NamesStore.shared)).map(String.init(describing:))
            DevLog.log(outcome ?? "corpus: seed FAILED at \(corpus.path)")
        }
        if LaunchFlags.forceEditConflict {
            // MemosListView's own @Query(MemoEditHead) + onChange(initial: true) refreshes
            // EditConflictWatch from these heads once the list appears — no manual kick here.
            EditConflicts.debugForceConflict(in: repo.context)
        }
        #endif

        // The shared embedder logs through an app-wired sink (it moved to
        // Shared/RetrievalEngine and can't see DevLog directly).
        GemmaEmbedder.log = { DevLog.log($0) }

        // Trash retention: permanently remove memos whose purge clock ran out
        // (audio + photo + sidecar files included) before any UI shows them.
        // v3-gated (2026-07-23): the clock is `trashSeenAt` — days the user
        // actually had the app open with the note in the trash — so this stays
        // safe on background launches (BGTask / silent push) too: a deletion
        // that synced in while the phone sat closed can never purge unseen.
        repo.purgeExpiredTrash()

        // App Intents (Control Center / Siri / Live Activity Stop) run in this
        // process and call these performers, which signal the record UI via the
        // bridge. Set at launch so a cold launch via an intent finds them ready.
        StartRecordingIntent.performer = { await MainActor.run { RecordingIntentBridge.shared.requestStart() } }
        ResumeAudiobookIntent.performer = { await MainActor.run { AudiobookSession.shared.resumeLastPlayed() } }
        StopRecordingIntent.performer = { await MainActor.run { RecordingIntentBridge.shared.requestStop() } }
        NewNoteIntent.performer = { await MainActor.run { QuickNoteBridge.shared.requestNew() } }

        // Register the whole-book background-transcribe handler before the scene
        // connects (BGTaskScheduler requires registration at launch).
        BookBackgroundScheduler.register()

        // Polish on this iPad (wave 1): installs the on-demand engine on capable
        // pads; a no-op everywhere else (PolishCenter stays unavailable and no
        // polish UI appears).
        PolishBootstrap.installEngineIfSupported()

        // In-app feedback (Q299): the floating button + sheet (FeedbackKit, app id skrift).
        FeedbackKitWiring.start()
    }

    var body: some Scene {
        WindowGroup {
            // A store that failed to open shows a plain "couldn't open your notes" screen
            // INSTEAD of the app: none of the launch tasks below run against a placeholder store.
            if let failure = repository.startFailure {
                StoreStartFailureView(failure: failure)
                    .preferredColorScheme(colorScheme)
                    .tint(.skAccent)
            } else {
                launchContent
            }
        }
        // Hardware-keyboard shortcuts (iPad / Mac Catalyst). Inert on the phone
        // (no hardware keyboard), so the phone is unchanged. Each just nudges a
        // bridge singleton the views already observe (chords: Shared/UI/AppShortcuts) — ⇧⌘N/⌘F also hop to Notes
        // first so the recorder/search land in view.
        .commands {
            CommandGroup(after: .newItem) {
                Button("Record") {
                    TabSelectionBridge.shared.select(.notes)
                    RecordingIntentBridge.shared.requestStart()
                }
                .keyboardShortcut(AppShortcuts.record)
            }
            CommandMenu("View") {
                Button("Search Notes") {
                    TabSelectionBridge.shared.select(.notes)
                    SearchFocusBridge.shared.requestFocus()
                }
                .keyboardShortcut(AppShortcuts.search)
                Divider()
                Button("Notes")    { TabSelectionBridge.shared.select(.notes) }
                    .keyboardShortcut(AppShortcuts.tabNotes)
                Button("Books")    { TabSelectionBridge.shared.select(.books) }
                    .keyboardShortcut(AppShortcuts.tabBooks)
                Button("Review")   { TabSelectionBridge.shared.select(.journal) }
                    .keyboardShortcut(AppShortcuts.tabReview)
                Button("Settings") { TabSelectionBridge.shared.select(.settings) }
                    .keyboardShortcut(AppShortcuts.tabSettings)
            }
        }
    }

    @ViewBuilder private var launchContent: some View {
        #if DEBUG
        if perfLibrary.isSeeding {
            PerfSeedingView(launch: perfLibrary)
        } else {
            appRoot
        }
        #else
        appRoot
        #endif
    }

    @ViewBuilder private var appRoot: some View {
            RootView()
                .modelContainer(repository.container)
                .preferredColorScheme(colorScheme)
                .tint(.skAccent)
                .onOpenURL { AppURLHandler.receive($0) }
                // 2+ voice notes from Files / AirDrop / Open-in: the One-note / N-notes
                // question (C68 / C145), hosted at the root like the book offer.
                .sheet(item: $audioPick.pending) { pending in
                    AudioPickChoiceSheet(
                        pending: pending,
                        onConfirm: { choice, route in
                            audioPick.pending = nil
                            Task { await AppURLHandler.resolve(pending.urls, choice: choice, route: route) }
                        },
                        onCancel: { audioPick.pending = nil })
                }
                // 📦 A book someone shared can arrive while ANY screen is up, so
                // the offer is hosted at the root rather than in the library.
                .sheet(item: $bookImport.pending) { BookImportSheet(pending: $0) }
                .alert("Couldn't open that book",
                       isPresented: $bookImport.failure.isPresent) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(bookImport.failure ?? "")
                }
                // Clear any Live Activity orphaned by a kill mid-recording (iOS
                // keeps the banner alive after the process dies).
                .task { RecordingActivityManager.shared.reapOrphans() }
                // Drain the capture inbox whenever the app becomes active: covers
                // both cold launch and every background→foreground transition. The
                // share extension writes inbox entries into the App Group container;
                // we convert them to Memos here and delete the entries after save —
                // see Services/Capture/CaptureInbox.swift for the crash-safety model.
                .task { await CaptureInboxDrainer.drain(into: repository) }
                // Reconcile CloudKit-mirrored media (Phase 1c): write any synced
                // MemoAsset blobs that arrived from another device to disk, and
                // capture any local audio/photos that have no asset yet (incl.
                // migrating pre-1c memos). Idempotent; mirrors the inbox drainer's
                // launch + foreground cadence below.
                // (The corpus sweeps — dedupe, asset capture, photo OCR discovery, Fading,
                // reminders — start from the recovery task below, once the recording-recovery
                // sweep has finished, and run OFF the main thread: Q316, `LaunchSweeps`.)
                // Reconcile the names/people DB across devices (Phase 1e): merge the
                // CloudKit-synced carrier with the local names.json via the same
                // NamesMerge the Mac sync uses. Idempotent; launch + foreground.
                .task { NamesCloudSync.run(repository) }
                // Sync the custom-vocabulary list across devices (Phase 1f), LWW.
                .task { VocabularyCloudSync.run(repository) }
                // Sync the polish prompts (iPad v2) — one voice across the Mac's
                // batch polisher and the iPad's on-demand one, whole-blob LWW.
                .task { PolishPromptsCloudSync.run(repository) }
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
                // C99: rebuild any take a kill/force-quit left behind as a
                // note FIRST (it lands `.transcribing`), then the transcription
                // recovery below transcribes it — one task, so they never race.
                //
                // Q316: this task also owns the order. Recording recovery runs FIRST and
                // alone; only then do the corpus sweeps start (off the main thread, they
                // do not block this task), and the transcription recovery's discovery runs
                // off-main too. FadingSweep is the v3 open-gate: this task only runs with
                // the UI scene attached, i.e. a human open.
                .task {
                    if LaunchFlags.seedTranscript == nil {
                        await MemoSaver().recoverInterruptedRecordings()
                    }
                    LaunchSweeps.launch(repository)
                    if LaunchFlags.seedTranscript == nil {
                        await MemoSaver().recoverStuckTranscriptions(
                            sweeps: LaunchSweeps.sweepActor(for: repository))
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
                        // Every foreground is an open (v3, 2026-07-23): a phone
                        // resumed after weeks suspended must stamp purge clocks
                        // + sweep exactly like a cold launch. Idempotent.
                        // Time/open-gated, not corpus-derived — must run on EVERY
                        // foreground regardless of the R94 gate below: FadingSweep
                        // stamps trash-seen purge clocks purely by wall-clock time
                        // (a note trashed without any other edit must still get
                        // seen), ReminderScheduler reconciles due dates that pass
                        // just from time elapsing, and the inbox drainer is what
                        // TURNS a pending capture into a memo — gating it on "did
                        // the memo count change" would never let a new capture in.
                        //
                        // Q316: `LaunchSweeps.foreground` runs FadingSweep + reminders
                        // every time and the corpus sweeps only when the gate says the
                        // corpus moved, all off the main thread. The gate was marked at
                        // launch, so the first foreground no longer repeats the launch pass.
                        Task { await CaptureInboxDrainer.drain(into: repository) }
                        // P8 retrieval index — inert until the Journal UI's consent
                        // flow enables it AND the model is on disk (no surprise 295 MB).
                        JournalIndexService.shared.sweepSoon(repository)

                        // R94/C281: dupes, on-disk↔CloudKit asset capture and the photo-text
                        // index are pure re-derivations of the memo corpus, and so are the
                        // names/vocab/audiobook cloud reconciles below — safe to skip on a
                        // foreground where nothing changed since the last check.
                        // LaunchWorkGate's mark advances on this ONE call (inside
                        // `foreground`), so it stays a single call per foreground.
                        if LaunchSweeps.foreground(repository).gated {
                            NamesCloudSync.run(repository)
                            VocabularyCloudSync.run(repository)
                            Task { await AudiobookCloudSync.reconcile(repository: repository) }
                        }
                    } else if newPhase == .background {
                        // If a whole-book transcribe is in flight, ask iOS to let it
                        // continue in the background (best overnight on a charger).
                        BookBackgroundScheduler.scheduleIfNeeded()
                    }
                }
    }

    @Environment(\.scenePhase) private var scenePhase

    // The palette is dark-first (explicit dark surfaces), so "auto"/"light" are
    // best-effort until a light palette lands; default stays dark.
    private var colorScheme: ColorScheme? { ThemePreference.colorScheme(appTheme) }   // shared with the Mac (Q172)
}

/// App shell. The root is a tab bar (audiobook reading-mode redesign 2026-06-19):
/// Notes · Library · Highlights(soon) · Settings — see `AppTabView`. Record
/// presents over the Notes tab, Memo detail pushes from a card. First launch shows
/// onboarding.
struct RootView: View {
    @State private var needsOnboarding = RootView.shouldOnboard()

    /// Screenshot routes (Debug only): open a seeded memo straight into its detail.
    private static var seededRoute: AnyView? {
        #if DEBUG
        if LaunchFlags.seedNameLinking {
            // The seeded "Studio afternoon" memo, into the in-place name-linking surface.
            return AnyView(NavigationStack { MemoDetailView(initialID: DemoDataSeeder.nameLinkingMemoID) })
        } else if LaunchFlags.seedPolished {
            // The seeded polished memo (Phase 4 display).
            return AnyView(NavigationStack { MemoDetailView(initialID: DemoDataSeeder.polishedMemoID) })
        } else if LaunchFlags.journalMemoDemo {
            // The seeded pricing memo's detail — the P8 Related card in the footer
            // (combine with -seedJournal -mockJournalIndex).
            return AnyView(NavigationStack { MemoDetailView(initialID: DemoDataSeeder.journalPricingMemoID) })
        }
        #endif
        return nil
    }

    var body: some View {
        if let seeded = Self.seededRoute {
            seeded
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
        #if DEBUG
        // Q313: the perf library never registers for CloudKit's silent pushes.
        if !PerfLibrary.isActive { UIApplication.shared.registerForRemoteNotifications() }
        #else
        UIApplication.shared.registerForRemoteNotifications()
        #endif
        // Reminder taps → open the memo; foreground reminders still banner.
        UNUserNotificationCenter.current().delegate = ReminderScheduler.delegate
        return true
    }
}
