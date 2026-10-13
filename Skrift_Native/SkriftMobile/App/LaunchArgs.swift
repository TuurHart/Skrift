import Foundation

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
    /// Q313 (DEBUG): open the SEPARATE never-synced `perf.store` (CloudKit off) seeded once with
    /// ~2,000 generated notes, with its own names/vocab/recordings. Every CloudKit side channel is
    /// inert under it. See `PerfLibrary` (Shared/Model) and `PerfLibraryLaunch`.
    static var perfLibrary: Bool { args.boolFlag("-perfLibrary") }
    /// Seed a memo whose photo contains rendered text but is NOT yet OCR'd —
    /// the photo-search end-to-end fixture (launch sweep must index it).
    static var seedPhotoTextMemo: Bool { args.boolFlag("-seedPhotoTextMemo") }
    /// Q359 (DEBUG): ONE note with three paragraphs and a photo between 1 and 2, for the
    /// long-press-move-a-photo screenshot.
    static var seedPhotoMoveMemo: Bool { args.boolFlag("-seedPhotoMoveMemo") }
    /// Seed ONE long memo (long transcript + an image marker) so a UI test can
    /// scroll content UNDER the glass player bar and screenshot the refraction.
    static var seedLongMemo: Bool { args.boolFlag("-seedLongMemo") }
    /// Q329 (DEBUG): seed ONE audiobook quote capture whose quote has been EDITED (a word
    /// deleted, one inserted) and open its detail — the D183 "a quote is text" screenshot route.
    static var seedQuoteMemo: Bool { args.boolFlag("-seedQuoteMemo") }
    /// Seed ONE memo whose transcript is a `**Name:**` conversation, to verify the real
    /// detail view renders speaker turns (`SpeakerTurnsView`).
    static var seedConversationMemo: Bool { args.boolFlag("-seedConversationMemo") }
    /// With -seedDemoMemos: demo memo 2 links to demo memo 1, so the harbor note has a LINKED FROM row.
    static var seedLinkedPair: Bool { args.boolFlag("-seedLinkedPair") }
    /// Seed ONE video-import memo with a real LANDSCAPE (16:9) frame thumbnail (a
    /// centered circle — distorts to an ellipse if the thumbnail squishes aspect),
    /// so a UI test can screenshot-verify the video source glyph + thumbnail aspect.
    static var seedVideoMemo: Bool { args.boolFlag("-seedVideoMemo") }
    /// Q391 (DEBUG): ONE note holding every block of mock Q384 — text, a LARGE video (a short
    /// real .mov), a photo, a DXF card and a PDF card (`NoteAttachmentFixture`). With
    /// `-seedAttachmentLarge` every block starts large (Set All to Large).
    static var seedAttachmentMemo: Bool { args.boolFlag("-seedAttachmentMemo") }
    static var seedAttachmentLarge: Bool { args.boolFlag("-seedAttachmentLarge") }
    /// Seed back-dated memos with locations for the Journal tab (Looking-back
    /// cards, calendar dot density, place clusters) — screenshot verification.
    static var seedJournal: Bool { args.boolFlag("-seedJournal") }
    /// Open a specific root tab on launch: "notes" / "books" / "journal" /
    /// "settings" — per-tab screenshot verification of the global mini-player.
    static var openTab: String? { args.stringValue("-openTab") }
    /// Seed a synthetic audiobook (generated silent audio) + open it as a PAUSED
    /// session, so the GLOBAL mini-player capsule exists in the Simulator — the
    /// capsule was un-screenshotable before this (a real book is device-only),
    /// which is exactly how the build-40 FAB/capsule overlap shipped unseen.
    static var seedAudiobook: Bool { args.boolFlag("-seedAudiobook") }
    /// Q352: four seeded books (two with capture notes) for the Library shelf screenshot.
    static var seedLibraryShelf: Bool { args.boolFlag("-seedLibraryShelf") }
    /// Q356 (DEBUG): with `-seedLibraryShelf`, "Send to a note" on the first book and open that note
    /// (the link-card screenshot).
    static var showSentNote: Bool { args.boolFlag("-showSentNote") }
    /// Q354: two PDFs on the Library shelf; `-showPDFReader` opens one on page 4 with text selected,
    /// `-showPDFToast` raises the "Added to Library" toast. Screenshots only.
    static var seedLibraryPDF: Bool { args.boolFlag("-seedLibraryPDF") }
    static var showPDFReader: Bool { args.boolFlag("-showPDFReader") }
    static var showPDFToast: Bool { args.boolFlag("-showPDFToast") }
    /// Q355 (DEBUG): two articles on the shelf (no network: the text is built in); `-showArticleReader`
    /// opens one with a sentence selected, `-showArticleCapture` opens Add note on it,
    /// `-showArticleToast` raises the "No article text on that page" toast. Screenshots only.
    static var seedLibraryArticle: Bool { args.boolFlag("-seedLibraryArticle") }
    static var showArticleReader: Bool { args.boolFlag("-showArticleReader") }
    static var showArticleCapture: Bool { args.boolFlag("-showArticleCapture") }
    static var showArticleToast: Bool { args.boolFlag("-showArticleToast") }
    /// `-showArticleNote` saves the mock's quote as a capture note on "Local-first software" and opens it.
    static var showArticleNote: Bool { args.boolFlag("-showArticleNote") }
    /// Q353 (DEBUG): one seeded podcast episode (kind `episode`, Het Uur) opened as a paused session
    /// for the Episode-player screenshot.
    static var seedEpisode: Bool { args.boolFlag("-seedEpisode") }
    /// Q353 (DEBUG): present the full player over the open session on launch (render-only hook).
    static var showPlayer: Bool { args.boolFlag("-showPlayer") }
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
    /// DEBUG render hook: the real `BookShelfTile` in every state (uploading %, re-align, …).
    static var showBookTileGallery: Bool { args.boolFlag("-showBookTileGallery") }
    /// DEBUG render hook: also present the D127 "notes from this book" sheet over the gallery.
    static var showBookNotesSheet: Bool { args.boolFlag("-showBookNotesSheet") }
    /// Run the journal index on MockEmbedder + an in-memory store (no model
    /// assets) so search-Related/threads are demoable on the sim / UI tests.
    static var mockJournalIndex: Bool { args.boolFlag("-mockJournalIndex") }
    /// Pre-fill the memos-list search on launch (screenshot the Related section
    /// without typing).
    static var initialSearch: String? { args.stringValue("-initialSearch") }
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
    /// Q382 (DEBUG): with `-seedPolished`, DON'T open its detail as a root route — land on the
    /// list so a UI test taps the row and the note is PUSHED (the back button + tab bar are real).
    static var routeViaList: Bool { args.boolFlag("-routeViaList") }
    /// Wipe the local names.json at launch so a conversation/voice test starts from a
    /// known-empty names slate (names.json persists across sim runs, unlike the SwiftData
    /// store — `-inMemoryStore` doesn't reset it). Used by the diarization-split and
    /// voice-enroll UI tests.
    static var resetNames: Bool { args.boolFlag("-resetNames") }
    /// Force the first-run onboarding on (the onboarding UI test). Existing tests
    /// pass `-inMemoryStore` and auto-skip onboarding without it.
    static var forceOnboarding: Bool { args.boolFlag("-forceOnboarding") }
    static var skipOnboarding: Bool { args.boolFlag("-skipOnboarding") }
    /// Install the canned polish engine (DEBUG) so the Simulator can render the
    /// Process surfaces the real gate hides there — the header's "Process N",
    /// its "Processing 2 of 5" run state, the note bar's determinate line.
    static var fakePolishEngine: Bool { args.boolFlag("-fakePolishEngine") }
    /// …and make that engine claim its model is missing, for the download state.
    static var fakePolishNeedsDownload: Bool { args.boolFlag("-fakePolishNeedsDownload") }
    /// Open the Date strip on launch (screenshot rig — the sim's
    /// rotated tap space makes tapping a chip unreliable headless). Q66: the
    /// old Sort & Filter sheet is gone; Date opens a strip under the row.
    static var showFilterSheet: Bool { args.boolFlag("-showFilterSheet") }
    /// Inject a deterministic transcript instead of running FluidAudio (the
    /// Simulator has no Neural Engine). Its presence also puts recording in mock
    /// mode (no mic, no permission prompt) so the record→save→transcribe flow is
    /// hermetically UI-testable.
    static var seedTranscript: String? { args.stringValue("-seedTranscript") }
    /// Q39 screenshot/UI-test seam: manufacture ONE edit conflict on the first seeded memo
    /// (`EditConflicts.debugForceConflict`) so the prompt/banner/pill can be captured
    /// against `mocks/Q4-edit-conflict.html` without two real devices going apart.
    static var forceEditConflict: Bool { args.boolFlag("-forceEditConflict") }
}
