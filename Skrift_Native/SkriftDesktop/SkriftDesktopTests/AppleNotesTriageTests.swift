import XCTest
import SQLite3
import Compression
import SwiftData

/// Q333 (mocks/Q71-apple-notes-triage-v3.html): the Apple Notes triage data layer, driven off a
/// GENERATED NoteStore.sqlite (synthetic notes only; the real database is never read here).
/// Pins: a declined note is never re-offered, a renamed note is still recognised, Next 10 stays
/// locked until all ten are decided, the state survives a relaunch, Notes tags map to Skrift
/// tags, locked notes stay behind.
@MainActor
final class AppleNotesTriageTests: XCTestCase {

    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("q333_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    // MARK: - fixture database

    private struct P { var text: String; var style = -1; var done = false; var indent = 0 }
    private struct FixtureNote {
        var id: String = UUID().uuidString
        var title: String
        var lines: [P] = []
        var tags: [String] = []
        var created: Date? = Date(timeIntervalSince1970: 1_790_000_000)
        var locked = false
        var trashed = false
        var inTrashFolder = false
        /// Inline picture attachments (their runs carry `public.jpeg`; the bytes are not copied by the importer).
        var pictures = 0
        /// `ZICCLOUDSYNCINGOBJECT.ZTITLE2` of the folder row the note sits in (nil = the default "Notes" folder).
        var folder: String?
        /// A ZDATA blob that is not a note at all (the body reads as nil).
        var corruptBlob = false
    }

    private func varint(_ value: UInt64) -> [UInt8] {
        var v = value; var out: [UInt8] = []
        repeat { var b = UInt8(v & 0x7f); v >>= 7; if v != 0 { b |= 0x80 }; out.append(b) } while v != 0
        return out
    }
    private func lenField(_ n: Int, _ bytes: [UInt8]) -> [UInt8] { varint(UInt64(n << 3 | 2)) + varint(UInt64(bytes.count)) + bytes }
    private func intField(_ n: Int, _ v: UInt64) -> [UInt8] { varint(UInt64(n << 3)) + varint(v) }

    /// gzip with a real header around raw DEFLATE (the CRC is not checked by the reader).
    private func gzip(_ raw: [UInt8]) -> Data {
        var out = [UInt8](repeating: 0, count: raw.count + 1024)
        let n = compression_encode_buffer(&out, out.count, raw, raw.count, nil, COMPRESSION_ZLIB)
        return Data([0x1f, 0x8b, 8, 0, 0, 0, 0, 0, 0, 0xff] + out[0..<n] + [0, 0, 0, 0, 0, 0, 0, 0])
    }

    /// The REAL wrapper (apple_cloud_notes_parser proto/notestore.proto):
    /// NoteStoreProto{2: Document{2: version, 3: Note{2: note_text, 5: repeated AttributeRun}}}.
    /// ParagraphStyle numbers as the parser's AppleNote.rb / the Obsidian importer's ANStyleType:
    /// -1 default, 0 title, 1 heading, 2 subheading, 4 monospaced, 100 dotted, 101 dashed, 102 numbered, 103 checkbox.
    private func blob(for note: FixtureNote, wrapped: Bool = true) -> (Data, [String: String]) {
        var text = ""
        var runs: [[UInt8]] = []
        var alt: [String: String] = [:]
        func run(len: Int, style: Int, indent: Int = 0, done: Bool = false, attach: (String, String)? = nil) {
            var style_ = intField(1, UInt64(bitPattern: Int64(style)))
            if indent != 0 { style_ += intField(4, UInt64(indent)) }
            if style == 103 { style_ += lenField(5, lenField(1, [1, 2, 3]) + intField(2, done ? 1 : 0)) }
            var r = intField(1, UInt64(len)) + lenField(2, style_)
            if let (id, uti) = attach { r += lenField(12, lenField(1, Array(id.utf8)) + lenField(2, Array(uti.utf8))) }
            runs.append(r)
        }
        for (k, l) in note.lines.enumerated() {
            let isLast = k == note.lines.count - 1 && note.tags.isEmpty
            let piece = l.text + (isLast ? "" : "\n")
            text += piece
            run(len: piece.utf16.count, style: l.style, indent: l.indent, done: l.done)
        }
        if !note.tags.isEmpty {
            text += "Tags: "; run(len: 6, style: -1)
            for (k, t) in note.tags.enumerated() {
                let id = "tag-\(note.id)-\(k)"
                alt[id] = "#" + t
                text += "\u{FFFC}"; run(len: 1, style: -1, attach: (id, NotesBodyDecoder.hashtagUTI))
            }
        }
        for k in 0..<note.pictures {
            text += "\u{FFFC}"; run(len: 1, style: -1, attach: ("pic-\(note.id)-\(k)", "public.jpeg"))
        }
        let noteMsg = lenField(2, Array(text.utf8)) + runs.reduce([UInt8]()) { $0 + lenField(5, $1) }
        let document = intField(2, 0) + lenField(3, noteMsg)
        return (gzip(wrapped ? lenField(2, document) : document), alt)
    }

    private func exec(_ db: OpaquePointer?, _ sql: String) {
        var err: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &err) != SQLITE_OK { XCTFail("sql: \(String(cString: err!))\n\(sql)") }
    }
    private func q(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "''") + "'" }

    /// Builds a NoteStore.sqlite with just the columns the reader asks for (the real one has many more).
    @discardableResult
    private func makeStore(_ notes: [FixtureNote], at url: URL? = nil) throws -> URL {
        let path = url ?? dir.appendingPathComponent("NoteStore-\(UUID().uuidString).sqlite")
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(path.path, &db), SQLITE_OK)
        defer { sqlite3_close(db) }
        exec(db, """
            CREATE TABLE ZICCLOUDSYNCINGOBJECT (Z_PK INTEGER PRIMARY KEY, Z_ENT INTEGER, ZIDENTIFIER TEXT, ZTITLE1 TEXT,
              ZSNIPPET TEXT, ZCREATIONDATE1 REAL, ZCREATIONDATE2 REAL, ZCREATIONDATE3 REAL, ZMODIFICATIONDATE1 REAL, ZTITLE2 TEXT, ZISPASSWORDPROTECTED INTEGER,
              ZMARKEDFORDELETION INTEGER, ZFOLDER INTEGER, ZFOLDERTYPE INTEGER, ZNOTE INTEGER, ZTYPEUTI TEXT,
              ZALTTEXT TEXT, ZTOKENCONTENTIDENTIFIER TEXT);
            CREATE TABLE ZICNOTEDATA (Z_PK INTEGER PRIMARY KEY, ZNOTE INTEGER, ZDATA BLOB);
            INSERT INTO ZICCLOUDSYNCINGOBJECT (Z_PK, ZIDENTIFIER, ZFOLDERTYPE, ZTITLE2) VALUES (1, 'folder-notes', 0, 'Notes');
            INSERT INTO ZICCLOUDSYNCINGOBJECT (Z_PK, ZIDENTIFIER, ZFOLDERTYPE, ZTITLE2) VALUES (2, 'folder-trash', 1, 'Recently Deleted');
            """)
        var pk = 10
        var customFolders: [String: Int] = [:]
        for n in notes {
            let created = n.created.map { String($0.timeIntervalSinceReferenceDate) } ?? "NULL"
            var folderPK = n.inTrashFolder ? 2 : 1
            if let f = n.folder {
                if customFolders[f] == nil {
                    pk += 1
                    customFolders[f] = pk
                    exec(db, "INSERT INTO ZICCLOUDSYNCINGOBJECT (Z_PK, ZIDENTIFIER, ZFOLDERTYPE, ZTITLE2) VALUES (\(pk), \(q("folder-" + f)), 0, \(q(f)));")
                }
                folderPK = customFolders[f]!
            }
            pk += 1
            let notePK = pk
            exec(db, """
                INSERT INTO ZICCLOUDSYNCINGOBJECT (Z_PK, ZIDENTIFIER, ZTITLE1, ZSNIPPET, ZCREATIONDATE3, ZMODIFICATIONDATE1,
                  ZISPASSWORDPROTECTED, ZMARKEDFORDELETION, ZFOLDER)
                VALUES (\(pk), \(q(n.id)), \(q(n.title)), \(q(n.lines.first?.text ?? "")), \(created), 700000000,
                  \(n.locked ? 1 : 0), \(n.trashed ? 1 : 0), \(folderPK));
                """)
            let (data, alt) = n.corruptBlob ? (gzip([1, 2, 3, 4]), [:]) : blob(for: n)
            var st: OpaquePointer?
            sqlite3_prepare_v2(db, "INSERT INTO ZICNOTEDATA (ZNOTE, ZDATA) VALUES (?, ?)", -1, &st, nil)
            sqlite3_bind_int64(st, 1, Int64(notePK))
            _ = data.withUnsafeBytes { sqlite3_bind_blob(st, 2, $0.baseAddress, Int32(data.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
            sqlite3_step(st); sqlite3_finalize(st)
            for (id, text) in alt {
                pk += 1
                exec(db, """
                    INSERT INTO ZICCLOUDSYNCINGOBJECT (Z_PK, ZIDENTIFIER, ZTYPEUTI, ZALTTEXT)
                    VALUES (\(pk), \(q(id)), \(q(NotesBodyDecoder.hashtagUTI)), \(q(text)));
                    """)
            }
        }
        return path
    }

    private func numbered(_ count: Int, start: Date = Date(timeIntervalSince1970: 1_790_000_000)) -> [FixtureNote] {
        (0..<count).map { i in
            FixtureNote(title: "Note \(i)", lines: [P(text: "Note \(i)", style: 0), P(text: "Body \(i)")],
                        created: start.addingTimeInterval(Double(-i) * 86_400))
        }
    }

    // MARK: - declined notes are never offered again

    func testDeclinedUUIDIsNeverReOfferedEvenAfterRelaunchAndAnEditAndANewSession() throws {
        let notes = numbered(12)
        let store = try makeStore(notes)
        var reader: NotesStoreReader? = try NotesStoreReader(copying: store)
        let summaries = try reader!.listNotes()
        reader = nil
        var triage = AppleNotesTriage()
        triage.beginSession(notes: summaries)
        let target = try XCTUnwrap(summaries.first { $0.title == "Note 0" })
        XCTAssertEqual(triage.decide(target, kind: .never), .changed)

        // relaunch: state through the JSON file, a NEW session, the note edited AND renamed in Notes
        let file = AppleNotesTriageStore(url: dir.appendingPathComponent("triage.json"))
        file.save(triage.state)
        var again = AppleNotesTriage(state: file.load())
        var edited = summaries
        let i = try XCTUnwrap(edited.firstIndex { $0.id == target.id })
        edited[i].title = "Something else entirely"; edited[i].modified = Date()
        again.beginSession(notes: edited)
        XCTAssertFalse(again.queue(from: edited).contains { $0.id == target.id })
        XCTAssertTrue(again.isDecided(target.id), "it stays in its batch as a decided (×) note, not as an open one")
        XCTAssertEqual(again.openCount, again.state.batch.count - 1)
        XCTAssertEqual(again.decision(target.id)?.kind, .never)
    }

    func testARenamedNoteKeepsItsIdentityInTheDatabaseCopy() throws {
        var note = FixtureNote(title: "Passwords to change", lines: [P(text: "Passwords to change", style: 0), P(text: "Bank, email")])
        let store = try makeStore([note])
        let before = try NotesStoreReader(copying: store).listNotes()
        XCTAssertEqual(before.count, 1)
        // rename + add a line, same ZIDENTIFIER
        note.title = "Passwords, change by Nov"
        note.lines.append(P(text: "Also the Wi-Fi"))
        let after = try NotesStoreReader(copying: try makeStore([note])).listNotes()
        XCTAssertEqual(before[0].id, after[0].id)
        XCTAssertNotEqual(before[0].title, after[0].title)
        var triage = AppleNotesTriage()
        triage.beginSession(notes: before)
        triage.decide(before[0], kind: .never)
        triage.beginSession(notes: after)
        XCTAssertTrue(triage.queue(from: after).isEmpty)
    }

    func testSkipComesBackNextSessionButNotThisOne() throws {
        let summaries = try NotesStoreReader(copying: try makeStore(numbered(3))).listNotes()
        var triage = AppleNotesTriage()
        triage.beginSession(notes: summaries)
        let first = AppleNotesTriage.ordered(summaries)[0]
        triage.decide(first, kind: .skipped)
        XCTAssertTrue(triage.isDecided(first.id), "a skip counts as a decision for the lock")
        XCTAssertFalse(triage.queue(from: summaries).contains { $0.id == first.id })
        triage.beginSession(notes: summaries)
        XCTAssertFalse(triage.isDecided(first.id))
        XCTAssertTrue(triage.queue(from: summaries).contains { $0.id == first.id })
    }

    // MARK: - batch lock

    func testNextTenStaysLockedUntilAllTenAreDecided() throws {
        let summaries = try NotesStoreReader(copying: try makeStore(numbered(25))).listNotes()
        var triage = AppleNotesTriage()
        triage.beginSession(notes: summaries)
        XCTAssertEqual(triage.state.batch.count, 10)
        XCTAssertFalse(triage.canAdvance)
        let byID = Dictionary(uniqueKeysWithValues: summaries.map { ($0.id, $0) })
        let ids = triage.state.batch
        for id in ids.prefix(9) { triage.decide(byID[id]!, kind: .rated, rating: 2) }
        XCTAssertEqual(triage.openCount, 1)
        XCTAssertFalse(triage.canAdvance)
        XCTAssertNil(triage.advance(notes: summaries), "tapping Next 10 early does nothing")
        XCTAssertEqual(triage.state.batch, ids)
        // the tenth: a skip counts
        triage.decide(byID[ids[9]]!, kind: .skipped)
        XCTAssertTrue(triage.canAdvance)
        let imports = try XCTUnwrap(triage.advance(notes: summaries))
        XCTAssertEqual(Set(imports), Set(ids.prefix(9)))
        XCTAssertEqual(triage.state.batchesDone, 1)
        XCTAssertEqual(triage.state.batch.count, 10)
        XCTAssertTrue(Set(triage.state.batch).isDisjoint(with: ids))
        XCTAssertFalse(triage.queue(from: summaries).contains { ids.contains($0.id) },
                       "rated, skipped-this-session notes are not offered again in this session")
    }

    func testImportSoFarTakesOnlyTheRatedNotesOfTheOpenBatch() throws {
        let summaries = try NotesStoreReader(copying: try makeStore(numbered(12))).listNotes()
        var triage = AppleNotesTriage()
        triage.beginSession(notes: summaries)
        let byID = Dictionary(uniqueKeysWithValues: summaries.map { ($0.id, $0) })
        let ids = triage.state.batch
        triage.decide(byID[ids[0]]!, kind: .rated, rating: 3)
        triage.decide(byID[ids[1]]!, kind: .never)
        triage.decide(byID[ids[2]]!, kind: .rated, rating: 1)
        XCTAssertEqual(triage.pendingImports(), [ids[0], ids[2]])
        triage.markImported(ids[0], skriftID: "pf-1")
        XCTAssertEqual(triage.pendingImports(), [ids[2]])
        // an imported note cannot be flipped to Never import from here
        XCTAssertEqual(triage.decide(byID[ids[0]]!, kind: .never), .alreadyInSkrift)
        // nor re-rated from here: that happens on the note itself, and the import link survives
        XCTAssertEqual(triage.decide(byID[ids[0]]!, kind: .rated, rating: 1), .alreadyInSkrift)
        XCTAssertEqual(triage.state.decisions[ids[0]]?.skriftID, "pf-1")
        XCTAssertEqual(triage.state.decisions[ids[0]]?.rating, 3)
    }

    func testSameTapAgainClearsAnUnimportedDecision() throws {
        let summaries = try NotesStoreReader(copying: try makeStore(numbered(2))).listNotes()
        var triage = AppleNotesTriage()
        triage.beginSession(notes: summaries)
        let n = summaries[0]
        XCTAssertEqual(triage.decide(n, kind: .rated, rating: 2), .changed)
        XCTAssertEqual(triage.decide(n, kind: .rated, rating: 2), .cleared)
        XCTAssertNil(triage.decision(n.id))
    }

    // MARK: - resume

    func testResumeStateSurvivesARelaunchAndLandsOnTheFirstOpenNote() throws {
        let summaries = try NotesStoreReader(copying: try makeStore(numbered(30))).listNotes()
        let file = AppleNotesTriageStore(url: dir.appendingPathComponent("triage.json"))
        var triage = AppleNotesTriage()
        triage.beginSession(notes: summaries)
        let byID = Dictionary(uniqueKeysWithValues: summaries.map { ($0.id, $0) })
        let ids = triage.state.batch
        let t0 = Date(timeIntervalSince1970: 1_790_000_000)   // whole seconds: the file stores ISO 8601
        triage.decide(byID[ids[0]]!, kind: .rated, rating: 3, now: t0)
        triage.decide(byID[ids[1]]!, kind: .never, now: t0)
        triage.decide(byID[ids[2]]!, kind: .skipped, now: t0)
        file.save(triage.state)

        var back = AppleNotesTriage(state: file.load())
        XCTAssertEqual(back.state, triage.state, "every tap is on disk")
        back.beginSession(notes: summaries)
        XCTAssertEqual(back.state.batch, ids, "the open batch is the same ten")
        // the skip is from the earlier session, so it is open again: first open is the skip
        XCTAssertEqual(back.firstOpenIndex(), 2)
        XCTAssertEqual(back.state.cursor, 2)
        XCTAssertEqual(back.decision(ids[0])?.rating, 3)
        let counts = back.counts(notes: summaries)
        XCTAssertEqual(counts.decided, 2)
        XCTAssertEqual(counts.total, 30)
    }

    func testANoteDeletedInNotesLeavesTheOpenBatch() throws {
        var summaries = try NotesStoreReader(copying: try makeStore(numbered(12))).listNotes()
        var triage = AppleNotesTriage()
        triage.beginSession(notes: summaries)
        let gone = triage.state.batch[4]
        summaries.removeAll { $0.id == gone }
        triage.beginSession(notes: summaries)
        XCTAssertFalse(triage.state.batch.contains(gone))
        XCTAssertEqual(triage.state.batch.count, 9)
    }

    // MARK: - tags

    func testNotesTagsBecomeSkriftTagsFoldedIntoTheLibrary() throws {
        let note = FixtureNote(title: "Shino recipe", lines: [P(text: "Shino recipe", style: 0), P(text: "Cone 6")],
                               tags: ["Kiln", "glaze", "gift ideas", "kiln"])
        let reader = try NotesStoreReader(copying: try makeStore([note]))
        let summary = try XCTUnwrap(try reader.listNotes().first)
        let decoded = try XCTUnwrap(reader.content(of: summary))
        XCTAssertEqual(decoded.tags, ["Kiln", "glaze", "gift ideas"], "read in order, same tag in another case dropped")
        let mapped = AppleNotesTags.map(decoded.tags, library: ["kiln", "books"])
        XCTAssertEqual(mapped, ["kiln", "glaze", "gift ideas"], "case folds into the library's spelling; multi-word keeps its space")
        XCTAssertTrue(decoded.markdown.contains("#Kiln"))
    }

    // MARK: - locked + trashed

    func testLockedNotesStayBehindAndTrashedNotesAreInvisible() throws {
        var locked = FixtureNote(title: "Secrets", lines: [P(text: "Secrets", style: 0)])
        locked.locked = true
        var trashed = FixtureNote(title: "Gone", lines: [P(text: "Gone", style: 0)]); trashed.trashed = true
        var inTrash = FixtureNote(title: "Recently deleted", lines: [P(text: "x", style: 0)]); inTrash.inTrashFolder = true
        let ok = FixtureNote(title: "Fine", lines: [P(text: "Fine", style: 0)])
        let reader = try NotesStoreReader(copying: try makeStore([locked, trashed, inTrash, ok]))
        let all = try reader.listNotes()
        XCTAssertEqual(Set(all.map(\.title)), ["Secrets", "Fine"])
        let lockedSummary = try XCTUnwrap(all.first { $0.title == "Secrets" })
        XCTAssertTrue(lockedSummary.isLocked)
        XCTAssertNil(reader.content(of: lockedSummary), "a locked body is never decoded")
        XCTAssertEqual(AppleNotesTriage.offerable(all).map(\.title), ["Fine"])
        var triage = AppleNotesTriage()
        triage.beginSession(notes: all)
        XCTAssertEqual(triage.state.batch.count, 1)
        let c = triage.counts(notes: all)
        XCTAssertEqual(c.total, 1)
        XCTAssertEqual(c.lockedLeftBehind, 1)
    }

    // MARK: - bodies and dates

    func testBodyKeepsHeadingsListsAndTicksAndDateUnknownIsHonest() throws {
        let note = FixtureNote(title: "Gift ideas", lines: [
            P(text: "Gift ideas", style: 0), P(text: "Soon", style: 1),
            P(text: "A chisel", style: 100), P(text: "Concert tickets?", style: 103, done: true),
            P(text: "Book on joinery", style: 103), P(text: "Plain line")], created: nil)
        let reader = try NotesStoreReader(copying: try makeStore([note]))
        let s = try XCTUnwrap(try reader.listNotes().first)
        XCTAssertNil(s.created, "no creation date stays nil: Date unknown, never today (Q141)")
        let d = try XCTUnwrap(reader.content(of: s))
        XCTAssertEqual(d.markdown, "# Gift ideas\n\n## Soon\n\n- A chisel\n- [x] Concert tickets?\n- [ ] Book on joinery\n\nPlain line")
        XCTAssertEqual(d.media.checklistItems, 2); XCTAssertEqual(d.media.checklistDone, 1)
        XCTAssertEqual(AppleNotesTriage.ordered([s, AppleNoteSummary(id: "z", pk: 1, title: "dated", snippet: "", created: Date(), modified: nil, isLocked: false)]).last?.id, s.id,
                       "date unknown sorts last")
    }

    // MARK: - Q337 (1) the real NoteStoreProto wrapper, (2) the real paragraph style numbers

    func testTheRealNoteStoreProtoWrapperDecodesAndABareDocumentStillDoes() throws {
        let note = FixtureNote(title: "Wrapped", lines: [P(text: "Wrapped", style: 0), P(text: "Body text")])
        for wrapped in [true, false] {
            let (data, _) = blob(for: note, wrapped: wrapped)
            let d = try XCTUnwrap(NotesBodyDecoder.decode(zdata: data), "wrapped=\(wrapped)")
            XCTAssertEqual(d.markdown, "# Wrapped\n\nBody text", "wrapped=\(wrapped)")
        }
    }

    func testParagraphStylesUseTheRealNumbers() throws {
        let note = FixtureNote(title: "Styles", lines: [
            P(text: "Styles", style: 0), P(text: "Big", style: 1), P(text: "Small", style: 2),
            P(text: "dot one", style: 100), P(text: "dot two", style: 100, indent: 1),
            P(text: "dash one", style: 101), P(text: "dash two", style: 101),
            P(text: "first", style: 102), P(text: "second", style: 102),
            P(text: "tick me", style: 103), P(text: "ticked", style: 103, done: true),
            P(text: "let x = 1", style: 4), P(text: "Plain")])
        let d = try XCTUnwrap(NotesBodyDecoder.decode(zdata: blob(for: note).0))
        XCTAssertEqual(d.markdown, [
            "# Styles", "## Big", "### Small",
            "- dot one\n  - dot two\n- dash one\n- dash two\n1. first\n2. second\n- [ ] tick me\n- [x] ticked",
            "let x = 1", "Plain"].joined(separator: "\n\n"))
        XCTAssertEqual(d.media.checklistItems, 2); XCTAssertEqual(d.media.checklistDone, 1)
    }

    // MARK: - Q337 (3) retryable, (4) idempotent + persisted per note, (5) dropped media survives, models end to end

    private func makeModel(_ notes: [FixtureNote]) async throws -> (AppleNotesTriageModel, AppleNotesTriageStore) {
        let source = try makeStore(notes)
        let store = AppleNotesTriageStore(url: dir.appendingPathComponent("triage-\(UUID().uuidString).json"))
        let model = AppleNotesTriageModel(store: store)
        await model.load(from: source)
        XCTAssertEqual(model.phase, .start)
        return (model, store)
    }

    func testARatedNoteWhoseImportFailedStaysRetryableAfterItsBatchCloses() throws {
        let summaries = try NotesStoreReader(copying: try makeStore(numbered(25))).listNotes()
        var triage = AppleNotesTriage()
        triage.beginSession(notes: summaries)
        let byID = Dictionary(uniqueKeysWithValues: summaries.map { ($0.id, $0) })
        let first = triage.state.batch
        for id in first { triage.decide(byID[id]!, kind: .rated, rating: 2) }
        let handed = try XCTUnwrap(triage.advance(notes: summaries))
        XCTAssertEqual(handed.count, 10)
        triage.markImported(handed[0], skriftID: "pf-0")          // the other nine failed or had no body
        XCTAssertFalse(triage.state.batch.contains(handed[1]), "its batch is closed")
        XCTAssertEqual(Set(triage.pendingImports()), Set(handed.dropFirst()), "all nine are still on the retry list")
    }

    func testImportSavesTheTriageFileAfterEveryNoteAndAFailedOneIsRetriedAndListed() async throws {
        let (model, store) = try await makeModel(numbered(3))
        var calls = 0
        var failNext = true
        var persistedBeforeThird: Int?
        model.importer = { note, body, _ in
            calls += 1
            if calls == 2, failNext { failNext = false; throw NSError(domain: "t", code: 1, userInfo: [NSLocalizedDescriptionKey: "disk full"]) }
            if calls == 3 { persistedBeforeThird = store.load().decisions.values.filter { $0.skriftID != nil }.count }
            return ("pf-\(note.id.prefix(4))", AppleNotesImporter.dropped(from: body.media))
        }
        model.rate(2); model.rate(2); model.rate(3)
        await model.importSoFar()
        XCTAssertEqual(persistedBeforeThird, 1, "the first note was already on disk when the third was being imported")
        XCTAssertEqual(model.waitingToImport.count, 1, "the failed note is listed in the report")
        XCTAssertEqual(model.importFailures.count, 1)
        XCTAssertEqual(model.counts.inSkrift, 2)
        // a retry (the next Import so far) picks it up; nothing is imported twice
        await model.importSoFar()
        XCTAssertEqual(model.waitingToImport.count, 0)
        XCTAssertEqual(model.importFailures.count, 0)
        XCTAssertEqual(model.counts.inSkrift, 3)
        XCTAssertEqual(calls, 4, "3 first tries (one failed) + 1 retry; the two imported notes were not re-imported")
    }

    func testANoteWhoseBodyCannotBeReadStaysRetryableAndIsListed() async throws {
        var bad = FixtureNote(title: "Garbled", lines: [P(text: "Garbled", style: 0)])
        bad.corruptBlob = true
        let (model, _) = try await makeModel([bad])
        model.importer = { n, _, _ in ("pf-\(n.id.prefix(4))", NotesBodyDecoder.Media()) }
        model.rate(1)
        await model.importSoFar()
        XCTAssertEqual(model.counts.inSkrift, 0)
        XCTAssertEqual(model.waitingToImport.map(\.decision.title), ["Garbled"])
        XCTAssertNotNil(model.importFailures[bad.id])
    }

    func testDroppedMediaIsPersistedAndKeepsANoteOutOfSafeToDeleteAfterARelaunch() async throws {
        var pics = FixtureNote(title: "Trip photos", lines: [P(text: "Trip photos", style: 0), P(text: "Day one")])
        pics.pictures = 2
        pics.created = Date(timeIntervalSince1970: 1_790_000_000)
        var plain = FixtureNote(title: "Just words", lines: [P(text: "Just words", style: 0)])
        plain.created = Date(timeIntervalSince1970: 1_780_000_000)
        let (model, store) = try await makeModel([pics, plain])
        model.importer = { n, body, _ in ("pf-\(n.id.prefix(4))", AppleNotesImporter.dropped(from: body.media)) }
        model.rate(2); model.rate(2)
        await model.importSoFar()
        XCTAssertEqual(model.safeToDelete.map(\.decision.title), ["Just words"])
        XCTAssertEqual(model.keepInNotes.map(\.decision.title), ["Trip photos"])
        XCTAssertEqual(model.droppedTotals.pictures, 2)

        // relaunch: a fresh model on the same file and the same database
        let again = AppleNotesTriageModel(store: store)
        await again.load(from: try makeStore([pics, plain]))
        XCTAssertEqual(again.safeToDelete.map(\.decision.title), ["Just words"])
        XCTAssertEqual(again.keepInNotes.map(\.decision.title), ["Trip photos"])
        XCTAssertEqual(again.droppedTotals.pictures, 2)
    }

    func testNeverImportStoresOnlyTheUUIDButTheReportStillShowsTheTitle() async throws {
        let (model, store) = try await makeModel([FixtureNote(title: "Private thing about Rui", lines: [P(text: "Private thing about Rui", style: 0)])])
        model.never()
        let json = try String(contentsOf: store.url, encoding: .utf8)
        XCTAssertFalse(json.contains("Private thing"), "no title on disk for a note that was declined")
        XCTAssertEqual(model.decided(.never).map(\.decision.title), ["Private thing about Rui"], "read from the live note")
    }

    func testTheOpenBatchBodiesAreDecodedBeforeTheStartScreen() async throws {
        let (model, _) = try await makeModel(numbered(12))
        XCTAssertEqual(model.batchIDs.count, 10)
        for id in model.batchIDs {
            XCTAssertFalse(model.bodyPending(id))
            XCTAssertNotNil(model.body(of: try XCTUnwrap(model.note(id))))
        }
    }

    func testFoldersAreReportedOnlyWhenThereReallyAreSome() async throws {
        let (flat, _) = try await makeModel(numbered(3))
        XCTAssertFalse(flat.hasFolders)
        var inPottery = FixtureNote(title: "Glaze", lines: [P(text: "Glaze", style: 0)]); inPottery.folder = "Pottery"
        let plain = FixtureNote(title: "Dentist", lines: [P(text: "Dentist", style: 0)])
        let (foldered, _) = try await makeModel([inPottery, plain])
        XCTAssertTrue(foldered.hasFolders)
        XCTAssertEqual(foldered.folderNames, ["Notes", "Pottery"])
    }

    // MARK: - Q337 (4) the import is idempotent, (6) the folder name is capped

    func testRetryingAnImportReusesTheRowItAlreadyMade() throws {
        let note = FixtureNote(title: "Once only", lines: [P(text: "Once only", style: 0), P(text: "Body")])
        let reader = try NotesStoreReader(copying: try makeStore([note]))
        let s = try XCTUnwrap(try reader.listNotes().first)
        let d = try XCTUnwrap(reader.content(of: s))
        let ctx = ModelContext(try ModelContainer(for: PipelineFile.self,
                                                  configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
        let out = dir.appendingPathComponent("out")
        let a = try AppleNotesImporter.importNote(s, decoded: d, rating: 2, libraryTags: [], outputDir: out, context: ctx, cloudContext: nil)
        let b = try AppleNotesImporter.importNote(s, decoded: d, rating: 2, libraryTags: [], outputDir: out, context: ctx, cloudContext: nil)
        XCTAssertEqual(a.file.id, b.file.id)
        XCTAssertEqual(a.file.appleNoteID, s.id)
        XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<PipelineFile>()), 1)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: out.path).count, 1, "one folder, not two")
    }

    func testALongTitleIsCappedAt80CharactersInTheImportFolderName() throws {
        let long = String(repeating: "Long title word ", count: 30)
        let note = FixtureNote(title: long, lines: [P(text: long, style: 0), P(text: "Body")])
        let reader = try NotesStoreReader(copying: try makeStore([note]))
        let s = try XCTUnwrap(try reader.listNotes().first)
        let d = try XCTUnwrap(reader.content(of: s))
        let ctx = ModelContext(try ModelContainer(for: PipelineFile.self,
                                                  configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
        let r = try AppleNotesImporter.importNote(s, decoded: d, rating: 1, libraryTags: [], outputDir: dir.appendingPathComponent("out"),
                                                  context: ctx, cloudContext: nil)
        XCTAssertLessThanOrEqual(r.file.filename.count, 80 + ".md".count)
        let folder = URL(fileURLWithPath: r.file.path).deletingLastPathComponent().lastPathComponent
        XCTAssertLessThanOrEqual(folder.utf8.count, 36 + 1 + 83, "uuid + _ + 80 chars + .md")
        XCTAssertEqual(r.file.enhancedTitle?.count, d.title.count, "the full title is kept on the note")
    }

    // MARK: - Q337 (7)(8)(9) reader

    func testCreationDateIsReadInTheOrder3Then2Then1() throws {
        let store = try makeStore([FixtureNote(title: "A", lines: [P(text: "A", style: 0)], created: nil),
                                   FixtureNote(title: "B", lines: [P(text: "B", style: 0)], created: nil)])
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(store.path, &db), SQLITE_OK)
        exec(db, "UPDATE ZICCLOUDSYNCINGOBJECT SET ZCREATIONDATE1 = 100, ZCREATIONDATE2 = 200, ZCREATIONDATE3 = 300 WHERE ZTITLE1 = 'A';")
        exec(db, "UPDATE ZICCLOUDSYNCINGOBJECT SET ZCREATIONDATE1 = 100, ZCREATIONDATE2 = 200 WHERE ZTITLE1 = 'B';")
        sqlite3_close(db)
        let got = Dictionary(uniqueKeysWithValues: try NotesStoreReader(copying: store).listNotes().map { ($0.title, $0.created) })
        XCTAssertEqual(got["A"]!, Date(timeIntervalSinceReferenceDate: 300))
        XCTAssertEqual(got["B"]!, Date(timeIntervalSinceReferenceDate: 200))
    }

    func testHashtagTextIsFoundByTheAttachmentsOwnIdentifierWhateverNoteColumnPointsAtIt() throws {
        // The fixture's tag rows carry NO ZNOTE at all; the runs' identifiers are the only link.
        let note = FixtureNote(title: "Tagged", lines: [P(text: "Tagged", style: 0)], tags: ["Alpha", "Beta"])
        let reader = try NotesStoreReader(copying: try makeStore([note]))
        let s = try XCTUnwrap(try reader.listNotes().first)
        XCTAssertEqual(try XCTUnwrap(reader.content(of: s)).tags, ["Alpha", "Beta"])
        XCTAssertEqual(NotesBodyDecoder.inlineAttachmentIDs(zdata: blob(for: note).0).count, 2)
    }

    func testStaleDatabaseCopiesAreSweptAndFreshOnesKept() throws {
        let old = dir.appendingPathComponent("skrift-notes-OLD", isDirectory: true)
        let fresh = dir.appendingPathComponent("skrift-notes-FRESH", isDirectory: true)
        let other = dir.appendingPathComponent("someone-elses", isDirectory: true)
        for u in [old, fresh, other] { try FileManager.default.createDirectory(at: u, withIntermediateDirectories: true) }
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-86_400)], ofItemAtPath: old.path)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-86_400)], ofItemAtPath: other.path)
        XCTAssertEqual(NotesStoreReader.sweepStaleCopies(in: dir), 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: old.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fresh.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: other.path), "only skrift-notes-* folders are touched")
    }

    func testDeniedCopyTellsYouToQuitAndReopenSkrift() {
        XCTAssertTrue(NotesStoreReader.fullDiskAccessHint.contains("quit and reopen Skrift"))
        let perm = NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoPermissionError)
        XCTAssertTrue(NotesStoreReader.classify(copyError: perm, source: dir).detail.contains("quit and reopen Skrift"))
    }

    func testImportedNoteArrivesRatedDatedAndTagged() throws {
        let created = Date(timeIntervalSince1970: 1_700_000_000)
        let note = FixtureNote(title: "Glaze test", lines: [P(text: "Glaze test", style: 0), P(text: "Too green")],
                               tags: ["Kiln"], created: created)
        let reader = try NotesStoreReader(copying: try makeStore([note]))
        let s = try XCTUnwrap(try reader.listNotes().first)
        let d = try XCTUnwrap(reader.content(of: s))
        let ctx = ModelContext(try ModelContainer(for: PipelineFile.self,
                                                  configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
        let result = try AppleNotesImporter.importNote(s, decoded: d, rating: 2, libraryTags: ["kiln"],
                                                       outputDir: dir.appendingPathComponent("out"),
                                                       context: ctx, cloudContext: nil)
        let pf = result.file
        XCTAssertEqual(ThreeBallScale.step(for: pf.significance), 2)
        XCTAssertEqual(pf.uploadedAt, created)
        XCTAssertEqual(pf.tags, ["kiln"])
        XCTAssertEqual(pf.enhancedTitle, "Glaze test")
        XCTAssertEqual(pf.sourceType, .note)
        XCTAssertTrue(pf.isLocalImport)

        var undated = s; undated.created = nil; undated.id = UUID().uuidString   // another note: the same id would (rightly) reuse the first row
        let r2 = try AppleNotesImporter.importNote(undated, decoded: d, rating: 3, libraryTags: [],
                                                   outputDir: dir.appendingPathComponent("out"), context: ctx, cloudContext: nil)
        XCTAssertTrue(MemoDate.isUnknown(r2.file.uploadedAt))
    }

    // MARK: - the read itself

    func testACopyThatIsDeniedOrMissingSaysWhichAndNeverTouchesTheSource() throws {
        XCTAssertThrowsError(try NotesStoreReader(copying: dir.appendingPathComponent("nope.sqlite"))) {
            XCTAssertEqual(($0 as? NotesStoreReader.Failure)?.kind, .missing)
        }
        let perm = NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoPermissionError,
                           userInfo: [NSUnderlyingErrorKey: NSError(domain: NSPOSIXErrorDomain, code: Int(EPERM))])
        let f = NotesStoreReader.classify(copyError: perm, source: dir)
        XCTAssertEqual(f.kind, .denied)
        XCTAssertTrue(f.detail.contains("Full Disk Access"))
        // not a database at all
        let junk = dir.appendingPathComponent("junk.sqlite")
        try Data("not sqlite".utf8).write(to: junk)
        XCTAssertThrowsError(try NotesStoreReader(copying: junk))
    }
}
