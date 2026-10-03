import XCTest
import SwiftData

/// Q241 (C115, cleanup-audit P54): six suspected bugs, each proved by a test or logged in BUGS.md.
/// Bugs 1 and 3 live on the phone side (1 already covered by `SourceKindRealShapeTests`; 3 in
/// the phone's `Q241SweepTests`). This file holds the Mac-reachable ones: 2, 4, 5, 6.
@MainActor
final class Q241SuspectedBugsTests: XCTestCase {

    private func cloudContainer() throws -> ModelContainer {
        try ModelContainer(for: Memo.self, MemoAsset.self,
                           configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
    }

    // MARK: (2) a typed note's marker survives a typed `memo.metadata = ...` write

    /// `NoteBodyView.insertPhoto` does `var meta = memo.metadata ?? MemoMetadata(); ...;
    /// memo.metadata = meta`. `MemoMetadata` does not model `mediaSource`, so the marker used to
    /// be dropped and the typed note read as an Apple Note.
    func testAddingAPhotoToATypedNoteKeepsItTyped() throws {
        let ctx = ModelContext(try cloudContainer())
        let memo = try Memo.newTyped(into: ctx)
        XCTAssertEqual(SourceKind.of(memo), .typedNote)

        var meta = memo.metadata ?? MemoMetadata()
        meta.imageManifest = [ImageManifestEntry(filename: "photo_x_001.jpg", offsetSeconds: 0)]
        memo.metadata = meta

        XCTAssertEqual(memo.metadata?.imageManifest?.count, 1)
        XCTAssertEqual(SourceKind.of(memo), .typedNote, "the typed marker must survive a MemoMetadata write")
    }

    /// The Mac video marker `mediaSource: "video"` is the same shape of key.
    func testATypedMetadataWriteKeepsAMacVideoMarker() throws {
        let memo = Memo(audioFilename: "v.m4a", recordedAt: Date(), transcript: "words", transcriptStatus: .done)
        memo.metadataData = try JSONSerialization.data(withJSONObject: ["mediaSource": "video"])
        var meta = memo.metadata ?? MemoMetadata()
        meta.steps = 9
        memo.metadata = meta
        XCTAssertEqual(SourceKind.of(memo), .video)
    }

    /// A write that models its own source wins; clearing metadata clears the marker.
    func testAnExplicitSourceTypeStillWins() throws {
        let memo = Memo(audioFilename: "v.m4a", recordedAt: Date(), transcript: "w", transcriptStatus: .done)
        memo.metadata = MemoMetadata(sourceType: MemoMetadata.Source.video)
        XCTAssertEqual(SourceKind.of(memo), .video)
        memo.metadata = nil
        XCTAssertNil(memo.metadataData)
    }

    // MARK: (4) a Mac-imported Apple Note markdown arrives unrated

    func testAnImportedMarkdownNoteIsUnrated() async throws {
        let work = makeTempDir(); defer { try? FileManager.default.removeItem(at: work) }
        let ctx = ModelContext(try ModelContainer(for: PipelineFile.self,
                                                  configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
        let md = work.appendingPathComponent("Groceries.md")
        try "# Groceries\n\nmilk and eggs".write(to: md, atomically: true, encoding: .utf8)
        let pf = try await IngestService(outputDir: work.appendingPathComponent("out"))
            .ingestFile(md, into: ctx)
        let row = try XCTUnwrap(pf)
        XCTAssertTrue(row.isLocalImport, "every other Mac import stamps isLocalImport (D159)")
        XCTAssertFalse(NoteConsent.isRated(row), "an import is not judged by being added")
    }

    /// A note arriving through the recording side keeps the recording flag, never both.
    func testAMarkdownNoteFromARecordingSideIngestIsNotAnImport() async throws {
        let work = makeTempDir(); defer { try? FileManager.default.removeItem(at: work) }
        let ctx = ModelContext(try ModelContainer(for: PipelineFile.self,
                                                  configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
        let md = work.appendingPathComponent("n.md")
        try "hello".write(to: md, atomically: true, encoding: .utf8)
        let made = try await IngestService(outputDir: work.appendingPathComponent("out"),
                                           isLocalRecording: true).ingestFile(md, into: ctx)
        let row = try XCTUnwrap(made)
        XCTAssertTrue(row.isLocalRecording)
        XCTAssertFalse(row.isLocalImport)
    }

    // MARK: (5) memos fetched through the sidebar's fresh context persist their mutation

    /// `SidebarView.refreshCloudMemos` fetches through a fresh `ModelContext(cloud)`; the memos
    /// belong to that context, so `toggleLock`/`deleteQuiet` must save THAT context. They used
    /// to save `mainContext`, which had no change, so the write never reached the store.
    func testMutatingASnapshotMemoAndSavingTheSnapshotPersists() throws {
        let container = try cloudContainer()
        let seed = ModelContext(container)
        let memo = Memo(audioFilename: "", recordedAt: Date(), transcript: "hello", transcriptStatus: .done)
        let id = memo.id
        seed.insert(memo)
        try seed.save()

        let snap = CloudMemoSnapshot(container: container)
        let row = try XCTUnwrap(snap.memos.first { $0.id == id })
        row.deletedAt = Date()
        snap.save()

        let fresh = try ModelContext(container).fetch(FetchDescriptor<Memo>()).first { $0.id == id }
        XCTAssertNotNil(fresh?.deletedAt, "the soft delete must reach the store")
    }

    /// The bug itself, for the record: a memo from a throwaway context saved via `mainContext`.
    func testSavingMainContextDoesNotPersistAThrowawayContextsMemo() throws {
        let container = try cloudContainer()
        let seed = ModelContext(container)
        let memo = Memo(audioFilename: "", recordedAt: Date(), transcript: "hello", transcriptStatus: .done)
        let id = memo.id
        seed.insert(memo)
        try seed.save()
        let row = try XCTUnwrap((try? ModelContext(container).fetch(FetchDescriptor<Memo>()))?.first { $0.id == id })
        row.deletedAt = Date()
        try? container.mainContext.save()
        let fresh = try ModelContext(container).fetch(FetchDescriptor<Memo>()).first { $0.id == id }
        XCTAssertNil(fresh?.deletedAt, "mainContext never saw the change (why the sidebar saves its snapshot)")
    }

    // MARK: (6) the open Settings sheet must not write stale cloud-owned fields back

    func testAnEditInAStaleSettingsSheetKeepsWhatARunnerWroteToDisk() throws {
        let dir = makeTempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = SettingsStore(fileURL: dir.appendingPathComponent("settings.json"))

        var opened = AppSettings()
        opened.customVocabulary = ["Skrift"]
        opened.customVocabularyModifiedAt = Date(timeIntervalSince1970: 100)
        store.save(opened)
        let sheetBase = store.load()          // the open sheet's copy
        var sheet = sheetBase

        // a CloudKit runner lands a newer vocab list + language while the sheet is open
        var runner = store.load()
        runner.customVocabulary = ["Skrift", "Tuur"]
        runner.customVocabularyModifiedAt = Date(timeIntervalSince1970: 200)
        runner.transcriptionMultilingual = true
        runner.transcriptionLanguageModifiedAt = Date(timeIntervalSince1970: 200)
        store.save(runner)

        // the user edits an unrelated field in the stale sheet and the autosave fires
        sheet.authorName = "Tuur"
        store.saveEdit(from: sheetBase, to: sheet)

        let disk = store.load()
        XCTAssertEqual(disk.authorName, "Tuur", "the user's edit lands")
        XCTAssertEqual(disk.customWords, ["Skrift", "Tuur"], "the runner's vocab survives")
        XCTAssertEqual(disk.customVocabularyModifiedAt, Date(timeIntervalSince1970: 200))
        XCTAssertTrue(disk.transcriptionIsMultilingual, "the runner's language survives")
    }

    func testAnEditToACloudOwnedFieldStillWins() throws {
        let dir = makeTempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = SettingsStore(fileURL: dir.appendingPathComponent("settings.json"))
        let base = store.load()
        var sheet = base
        sheet.customVocabulary = ["Alpha"]
        sheet.customVocabularyModifiedAt = Date(timeIntervalSince1970: 300)
        store.saveEdit(from: base, to: sheet)
        XCTAssertEqual(store.load().customWords, ["Alpha"])
        XCTAssertEqual(store.load().customVocabularyModifiedAt, Date(timeIntervalSince1970: 300))
    }
}
