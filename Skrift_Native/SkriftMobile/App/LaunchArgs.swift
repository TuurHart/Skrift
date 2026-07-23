import Foundation

/// Launch-argument parsing, mirroring the Pike Companion test harness. Accepts
/// both `-key value` and `-key=value` forms.
extension Array where Element == String {
    func boolFlag(_ key: String) -> Bool {
        contains { $0 == key || $0.hasPrefix("\(key)=") }
    }

    func stringValue(_ key: String) -> String? {
        if let i = firstIndex(of: key), i + 1 < count { return self[i + 1] }
        if let raw = first(where: { $0.hasPrefix("\(key)=") }) {
            return String(raw.dropFirst("\(key)=".count))
        }
        return nil
    }

    func intValue(_ key: String) -> Int? { stringValue(key).flatMap(Int.init) }
}

/// Test seams the app reads at launch (`MOBILE_NATIVE_REWRITE_PLAN.md` §5). The
/// Simulator has no Neural Engine and FluidAudio pulls ~600MB, so UI tests SEED
/// state via these flags rather than running real ASR.
enum LaunchFlags {
    private static var args: [String] { ProcessInfo.processInfo.arguments }

    /// Fresh in-memory SwiftData store per launch — deterministic UI tests, and
    /// the demo seeder runs every time (the persistent store would otherwise
    /// survive across runs and the idempotent seeder would skip).
    static var inMemoryStore: Bool { args.boolFlag("-inMemoryStore") }
    static var seedDemoMemos: Bool { args.boolFlag("-seedDemoMemos") }
    /// iPad screenshot rig: at regular width, select the first Notes row at
    /// launch so the split view's detail pane renders deterministically.
    static var selectFirstMemo: Bool { args.boolFlag("-selectFirstMemo") }
    /// Seed a memo whose photo contains rendered text but is NOT yet OCR'd —
    /// the photo-search end-to-end fixture (launch sweep must index it).
    static var seedPhotoTextMemo: Bool { args.boolFlag("-seedPhotoTextMemo") }
    /// Seed ONE long memo (long transcript + an image marker) so a UI test can
    /// scroll content UNDER the glass player bar and screenshot the refraction.
    static var seedLongMemo: Bool { args.boolFlag("-seedLongMemo") }
    /// Show the conversation-mode design mock (static; no real diarization).
    static var conversationMock: Bool { args.boolFlag("-conversationMock") }
    /// Seed ONE memo whose transcript is a `**Name:**` conversation, to verify the real
    /// detail view renders speaker turns (`SpeakerTurnsView`).
    static var seedConversationMemo: Bool { args.boolFlag("-seedConversationMemo") }
    /// Seed ONE video-import memo with a real LANDSCAPE (16:9) frame thumbnail (a
    /// centered circle — distorts to an ellipse if the thumbnail squishes aspect),
    /// so a UI test can screenshot-verify the video source glyph + thumbnail aspect.
    static var seedVideoMemo: Bool { args.boolFlag("-seedVideoMemo") }
    /// Seed back-dated memos with locations for the Journal tab (Looking-back
    /// cards, calendar dot density, place clusters) — screenshot verification.
    static var seedJournal: Bool { args.boolFlag("-seedJournal") }
    /// Open the Journal tab on launch (screenshot/UITest routing, like the
    /// seed-and-open flags above).
    static var openJournal: Bool { args.boolFlag("-openJournal") }
    /// Open a specific root tab on launch: "notes" / "books" / "journal" /
    /// "settings" — per-tab screenshot verification of the global mini-player.
    static var openTab: String? { args.stringValue("-openTab") }
    /// Seed a synthetic audiobook (generated silent audio) + open it as a PAUSED
    /// session, so the GLOBAL mini-player capsule exists in the Simulator — the
    /// capsule was un-screenshotable before this (a real book is device-only),
    /// which is exactly how the build-40 FAB/capsule overlap shipped unseen.
    static var seedAudiobook: Bool { args.boolFlag("-seedAudiobook") }
    /// Seed the synthetic book WITHOUT arming a session — the Notes
    /// "Continue listening" card state (card-at-rest / pill-when-live).
    static var seedAudiobookIdle: Bool { args.boolFlag("-seedAudiobookIdle") }
    /// Device-verify hook (📖 rounds 5–7): open the most recently played REAL
    /// book as a PAUSED session on launch — fires the same book-open
    /// `alignIfNeeded` a library tap would (re-adopt + schema re-align run
    /// headlessly, devlog-traceable) without hands on the phone. Run via
    /// `devicectl device process launch … -resumeBook`.
    static var resumeBook: Bool { args.boolFlag("-resumeBook") }
    /// Decorate the seeded book with transcript-DETECTED chapters incl. a
    /// "Book 2" separator — the multi-work chapters-sheet state (screenshot
    /// verification of the section-header treatment).
    static var seedDetectedChapters: Bool { args.boolFlag("-seedDetectedChapters") }
    /// Present the Chapters/Bookmarks sheet full-screen over the seeded book
    /// on launch — a deterministic sheet render without UI-test taps.
    static var showTOCSheet: Bool { args.boolFlag("-showTOCSheet") }
    /// Present the unified "Text" sheet over the seeded book on launch
    /// (mock book-text-unified.html) — same deterministic-render idea.
    static var showTextSheet: Bool { args.boolFlag("-showTextSheet") }
    /// Present the A0 "Give this book text" import prompt over the seeded book.
    static var showTextPrompt: Bool { args.boolFlag("-showTextPrompt") }
    /// Open the Settings tab on launch (screenshot routing).
    static var openSettings: Bool { args.boolFlag("-openSettings") }
    /// Run the journal index on MockEmbedder + an in-memory store (no model
    /// assets) so search-Related/threads are demoable on the sim / UI tests.
    static var mockJournalIndex: Bool { args.boolFlag("-mockJournalIndex") }
    /// Pre-fill the memos-list search on launch (screenshot the Related section
    /// without typing).
    static var initialSearch: String? { args.stringValue("-initialSearch") }
    /// Open the P8 thread view for the seeded pricing memo (screenshot route;
    /// combine with -seedJournal -mockJournalIndex).
    static var threadDemo: Bool { args.boolFlag("-threadDemo") }
    /// Open the seeded pricing memo's DETAIL (the P8 Related card; combine
    /// with -seedJournal -mockJournalIndex).
    static var journalMemoDemo: Bool { args.boolFlag("-journalMemoDemo") }
    static var seedDemoNames: Bool { args.boolFlag("-seedDemoNames") }
    /// Seed the name-linking demo (the mock's "Studio afternoon" memo + 4 people: two
    /// Jacks → ambiguous, Hendri → linked, Rose → suggested) and open its detail directly,
    /// so the in-place name-linking surface can be screenshot-verified on the Simulator.
    static var seedNameLinking: Bool { args.boolFlag("-seedNameLinking") }
    /// Seed a polished memo (raw um-filled transcript + a Mac `MemoEnhancement`:
    /// copy-edit/title/summary) + the name roster, and open its detail — so the Phase-4
    /// polished-text display can be screenshot-verified.
    static var seedPolished: Bool { args.boolFlag("-seedPolished") }
    /// Wipe the local names.json at launch so a conversation/voice test starts from a
    /// known-empty names slate (names.json persists across sim runs, unlike the SwiftData
    /// store — `-inMemoryStore` doesn't reset it). Used by the diarization-split and
    /// voice-enroll UI tests.
    static var resetNames: Bool { args.boolFlag("-resetNames") }
    /// Force the first-run onboarding on (the onboarding UI test). Existing tests
    /// pass `-inMemoryStore` and auto-skip onboarding without it.
    static var forceOnboarding: Bool { args.boolFlag("-forceOnboarding") }
    static var skipOnboarding: Bool { args.boolFlag("-skipOnboarding") }
    /// Inject a deterministic transcript instead of running FluidAudio (the
    /// Simulator has no Neural Engine). Its presence also puts recording in mock
    /// mode (no mic, no permission prompt) so the record→save→transcribe flow is
    /// hermetically UI-testable.
    static var seedTranscript: String? { args.stringValue("-seedTranscript") }

    /// DEBUG surgical-recovery hook (P0 2026-07-10): rewrite ONE memo's enhancement
    /// copy-edit from a base64 launch argument (newline-safe), stamping fresh
    /// provenance so CloudKit LWW propagates the restore to every device. Run via
    /// `devicectl device process launch … -restoreEnhancementMemo <uuid>
    /// -restoreEnhancementBody <base64>` — only with the draft-target fix installed.
    static var restoreEnhancement: (memoID: UUID, copyedit: String)? {
        guard let id = args.stringValue("-restoreEnhancementMemo").flatMap(UUID.init(uuidString:)),
              let b64 = args.stringValue("-restoreEnhancementBody"),
              let data = Data(base64Encoded: b64),
              let text = String(data: data, encoding: .utf8), !text.isEmpty else { return nil }
        return (id, text)
    }
}
