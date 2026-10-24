import XCTest
@testable import SkriftMobile

/// ObsidianPublisher over the SHARED `VaultWriter` (2026-07-26): the picked folder IS
/// the destination (no `Skrift/` prefix, no source subfolders), naming/edit-guard/
/// atomicity identical to the Mac's, photos become real embeds, audio exports.
/// Tests run against a temp directory (no real vault / security scope).
final class ObsidianPublisherTests: XCTestCase {
    private var sandbox: URL!
    /// What the user picks in the folder picker.
    private var picked: URL!
    /// Where Skrift actually writes — the resolved home inside the pick.
    private var vaultRoot: URL!
    private var ledger: ExportLedger!

    override func setUpWithError() throws {
        sandbox = FileManager.default.temporaryDirectory.appendingPathComponent("skrift-pub-\(UUID().uuidString)")
        // The folder the USER picks. Since 2026-08-14 Skrift resolves that into the folder it
        // owns (`VaultLayout.home`) — for a plain folder like this one, `<pick>/Skrift` — so
        // `home` below is where files actually land. Naming the pick "vault" rather than
        // "Skrift" keeps the nesting behaviour under test rather than accidentally skipped.
        picked = sandbox.appendingPathComponent("vault")
        try FileManager.default.createDirectory(at: picked, withIntermediateDirectories: true)
        vaultRoot = VaultLayout.home(forPicked: picked)
        // Tests that plant a file BEFORE the first publish (a foreign collision, a hand
        // edit) write straight into the home, which the writer would otherwise create later.
        try FileManager.default.createDirectory(at: vaultRoot, withIntermediateDirectories: true)
        ledger = ExportLedger(fileURL: sandbox.appendingPathComponent("ledger.json"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: sandbox)
    }

    private func publisher(people: [Person] = [],
                           photos: [String: Data] = [:],
                           audio: Data? = nil) -> ObsidianPublisher {
        ObsidianPublisher(vaultProvider: { self.picked }, manageScope: false,
                          author: "Tiuri", peopleProvider: { people },
                          photosProvider: { _ in photos },
                          audioProvider: { _ in audio },
                          ledgerOverride: ledger)
    }

    // ── the streamlined layout ──

    /// THE doctrine change from the never-shipped v1: the picked folder IS the
    /// destination. Tuur already keeps a Skrift folder in his vault — the old
    /// hardcoded prefix would have nested `Skrift/Skrift/` inside it.
    func testWritesAtTheRootOfTheFolderSkriftOwns() throws {
        let memo = Memo(title: "My Idea", transcript: "Body text.")
        guard case let .written(rel) = try publisher().publish(memo) else {
            return XCTFail("expected .written")
        }
        XCTAssertEqual(rel, "My Idea.md", "no Skrift/ prefix, no source subfolder, no id suffix")
        let text = try String(contentsOf: vaultRoot.appendingPathComponent(rel), encoding: .utf8)
        XCTAssertTrue(text.contains("title: \"My Idea\""))
        XCTAssertTrue(text.contains("skriftID: \(memo.id.uuidString)"), "stamped — the plugin contract")
    }

    func testIdempotentSkipWhenUnchanged() throws {
        let memo = Memo(title: "Note", transcript: "Body.")
        _ = try publisher().publish(memo)
        XCTAssertEqual(try publisher().publish(memo), .skippedUnchanged)
    }

    func testRenameKeepsSamePathAndOverwrites() throws {
        let memo = Memo(title: "Original", transcript: "Body.")
        guard case let .written(first) = try publisher().publish(memo) else { return XCTFail() }
        memo.title = "Renamed Title"
        guard case let .written(second) = try publisher().publish(memo) else {
            return XCTFail("a content change must re-write")
        }
        XCTAssertEqual(first, second, "rename keeps the original file path (single owner per file)")
        XCTAssertTrue(try String(contentsOf: vaultRoot.appendingPathComponent(second), encoding: .utf8)
            .contains("title: \"Renamed Title\""))
    }

    func testNoVault() throws {
        let p = ObsidianPublisher(vaultProvider: { nil }, manageScope: false,
                                  author: "T", peopleProvider: { [] }, ledgerOverride: ledger)
        XCTAssertEqual(try p.publish(Memo(transcript: "x")), .noVault)
    }

    // ── the edit guard (now the shared engine's) ──

    func testUserEditIsNotClobbered() throws {
        let memo = Memo(title: "Note", transcript: "Original body.")
        guard case let .written(rel) = try publisher().publish(memo) else { return XCTFail() }
        let file = vaultRoot.appendingPathComponent(rel)
        let edited = try String(contentsOf: file, encoding: .utf8) + "\nMy own thought, added in Obsidian.\n"
        try edited.write(to: file, atomically: true, encoding: .utf8)
        memo.transcript = "A different, updated body."
        XCTAssertEqual(try publisher().publish(memo), .userEdited(relativePath: rel))
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), edited, "the user's edit must survive")
    }

    /// A WHOLESALE replacement (no stamp left) reads as a file Skrift can't claim —
    /// blocked, never overwritten. Stricter than v1, which only compared hashes.
    func testWholesaleReplacementIsNeverTouched() throws {
        let memo = Memo(title: "Note", transcript: "Body.")
        guard case let .written(rel) = try publisher().publish(memo) else { return XCTFail() }
        let file = vaultRoot.appendingPathComponent(rel)
        try "My own note now.\n".write(to: file, atomically: true, encoding: .utf8)
        memo.transcript = "changed"
        XCTAssertEqual(try publisher().publish(memo), .blocked(relativePath: rel))
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "My own note now.\n")
    }

    func testUntouchedFileStillUpdates() throws {
        let memo = Memo(title: "Note", transcript: "Body.")
        guard case let .written(rel) = try publisher().publish(memo) else { return XCTFail() }
        memo.transcript = "Updated body."
        XCTAssertEqual(try publisher().publish(memo), .written(relativePath: rel))
        XCTAssertTrue(try String(contentsOf: vaultRoot.appendingPathComponent(rel), encoding: .utf8)
            .contains("Updated body."))
    }

    /// THE INBOX DOCTRINE (Tuur, 2026-07-26): a note FILED out of where we wrote it is
    /// reported, never re-created. The v1 behaviour (respawn on the next publish) would have
    /// resurrected every note he files into PARA, forever.
    ///
    /// "Filed" here means MOVED. This comment used to read "filed (or deleted on purpose)",
    /// treating the two as one case — see the test below for why they are not.
    func testAFiledAwayNoteIsReportedNotRespawned() throws {
        let memo = Memo(title: "Note", transcript: "Body.")
        guard case let .written(rel) = try publisher().publish(memo) else { return XCTFail() }

        let file = vaultRoot.appendingPathComponent(rel)
        let filed = file.deletingLastPathComponent().appendingPathComponent("PARA", isDirectory: true)
        try FileManager.default.createDirectory(at: filed, withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: file, to: filed.appendingPathComponent(file.lastPathComponent))

        XCTAssertEqual(try publisher().publish(memo), .movedAway(relativePath: rel))
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    /// DELETED is not filed. Nothing under the folder carries the note's stamp any more, so
    /// there is nothing to step aside for — and refusing forever is a dead end (2026-08-28:
    /// Tuur deleted his test exports, edited the note, re-exported, and Skrift said "left
    /// where you put it" with no way back).
    func testANoteWhoseFileWasDeletedIsWrittenAgain() throws {
        let memo = Memo(title: "Note", transcript: "Body.")
        guard case let .written(rel) = try publisher().publish(memo) else { return XCTFail() }
        try FileManager.default.removeItem(at: vaultRoot.appendingPathComponent(rel))

        XCTAssertEqual(try publisher().publish(memo), .written(relativePath: rel))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: vaultRoot.appendingPathComponent(rel).path))
    }

    /// A hand-authored note with the same title survives; the memo takes the
    /// deterministic id-suffixed name beside it.
    func testForeignTitleCollisionIsRespected() throws {
        let theirs = "# Weekly review\n\nMine.\n"
        try theirs.write(to: vaultRoot.appendingPathComponent("Weekly review.md"), atomically: true, encoding: .utf8)
        let memo = Memo(title: "Weekly review", transcript: "Body.")
        guard case let .written(rel) = try publisher().publish(memo) else { return XCTFail() }
        XCTAssertEqual(rel, "Weekly review \(memo.id.uuidString.prefix(8)).md")
        XCTAssertEqual(try String(contentsOf: vaultRoot.appendingPathComponent("Weekly review.md"), encoding: .utf8), theirs)
    }

    // ── photos + audio (the v1 gaps, closed) ──

    func testPhotoMarkersBecomeEmbedsAndImagesLand() throws {
        let memo = Memo.make(transcript: "Look at this. [[img_001]] More words.",
                             metadata: MemoMetadata(tags: [], imageManifest: [
                                ImageManifestEntry(filename: "IMG_9001.jpg", offsetSeconds: 1)]))
        memo.title = "Photo note"
        let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0])
        guard case let .written(rel) = try publisher(photos: ["IMG_9001.jpg": jpeg]).publish(memo) else {
            return XCTFail()
        }
        let text = try String(contentsOf: vaultRoot.appendingPathComponent(rel), encoding: .utf8)
        XCTAssertTrue(text.contains("![[Photo note_001.jpg]]"), "marker converted to a real embed")
        XCTAssertFalse(text.contains("[[img_001]]"), "no literal marker survives")
        XCTAssertEqual(try Data(contentsOf: vaultRoot.appendingPathComponent("Images/Photo note_001.jpg")), jpeg)
    }

    func testAudioExportsBesideTheNote() throws {
        let memo = Memo(audioFilename: "memo_x.m4a", title: "Spoken", transcript: "Body.")
        let blob = Data([0x00, 0x01, 0x02])
        guard case .written = try publisher(audio: blob).publish(memo) else { return XCTFail() }
        XCTAssertEqual(try Data(contentsOf: vaultRoot.appendingPathComponent("Recordings/Spoken.m4a")), blob)
    }

    /// Blobs are heavy — an unchanged note must not even fetch them.
    func testUnchangedNoteFetchesNoBlobs() throws {
        let memo = Memo(audioFilename: "memo_x.m4a", title: "Spoken", transcript: "Body.")
        _ = try publisher(audio: Data([0x00])).publish(memo)
        var fetched = false
        var p = publisher()
        p.audioProvider = { _ in fetched = true; return Data([0x00]) }
        XCTAssertEqual(try p.publish(memo), .skippedUnchanged)
        XCTAssertFalse(fetched, "the cheap equivalence check must run before any blob fetch")
    }

    // ── marker conversion mechanics ──

    func testConvertPhotoMarkersResolvesThroughTheManifest() {
        let manifest = [ImageManifestEntry(filename: "a.jpg", offsetSeconds: 0),
                        ImageManifestEntry(filename: "b.png", offsetSeconds: 5)]
        let (out, resolved) = ExportV2Test.convertPictures(
            "One [[img_002]] two [[img_001]] dangling [[img_009]].", manifest: manifest, stem: "Note")
        XCTAssertEqual(out, "One ![[Note_002.png]] two ![[Note_001.jpg]] dangling .")
        XCTAssertEqual(resolved.map(\.0), ["b.png", "a.jpg"])
        XCTAssertEqual(resolved.map(\.1), ["Note_002.png", "Note_001.jpg"])
    }
}
