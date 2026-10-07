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

    /// Document{3: Note{2: text, 5: runs}} for the note's lines, then its tags as inline attachments.
    private func blob(for note: FixtureNote) -> (Data, [String: String]) {
        var text = ""
        var runs: [[UInt8]] = []
        var alt: [String: String] = [:]
        func run(len: Int, style: Int, indent: Int = 0, done: Bool = false, attach: (String, String)? = nil) {
            var style_ = intField(1, UInt64(bitPattern: Int64(style)))
            if indent != 0 { style_ += intField(4, UInt64(indent)) }
            if style == 100 { style_ += lenField(5, lenField(1, [1, 2, 3]) + intField(2, done ? 1 : 0)) }
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
        // one picture, to prove the report counts what is not copied
        var doc: [UInt8] = intField(2, 0)
        let noteMsg = lenField(2, Array(text.utf8)) + runs.reduce([UInt8]()) { $0 + lenField(5, $1) }
        doc += lenField(3, noteMsg)
        return (gzip(doc), alt)
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
              ZSNIPPET TEXT, ZCREATIONDATE3 REAL, ZMODIFICATIONDATE1 REAL, ZISPASSWORDPROTECTED INTEGER,
              ZMARKEDFORDELETION INTEGER, ZFOLDER INTEGER, ZFOLDERTYPE INTEGER, ZNOTE INTEGER, ZTYPEUTI TEXT,
              ZALTTEXT TEXT, ZTOKENCONTENTIDENTIFIER TEXT);
            CREATE TABLE ZICNOTEDATA (Z_PK INTEGER PRIMARY KEY, ZNOTE INTEGER, ZDATA BLOB);
            INSERT INTO ZICCLOUDSYNCINGOBJECT (Z_PK, ZIDENTIFIER, ZFOLDERTYPE) VALUES (1, 'folder-notes', 0);
            INSERT INTO ZICCLOUDSYNCINGOBJECT (Z_PK, ZIDENTIFIER, ZFOLDERTYPE) VALUES (2, 'folder-trash', 1);
            """)
        var pk = 10
        for n in notes {
            pk += 1
            let notePK = pk
            let created = n.created.map { String($0.timeIntervalSinceReferenceDate) } ?? "NULL"
            exec(db, """
                INSERT INTO ZICCLOUDSYNCINGOBJECT (Z_PK, ZIDENTIFIER, ZTITLE1, ZSNIPPET, ZCREATIONDATE3, ZMODIFICATIONDATE1,
                  ZISPASSWORDPROTECTED, ZMARKEDFORDELETION, ZFOLDER)
                VALUES (\(pk), \(q(n.id)), \(q(n.title)), \(q(n.lines.first?.text ?? "")), \(created), 700000000,
                  \(n.locked ? 1 : 0), \(n.trashed ? 1 : 0), \(n.inTrashFolder ? 2 : 1));
                """)
            let (data, alt) = blob(for: n)
            var st: OpaquePointer?
            sqlite3_prepare_v2(db, "INSERT INTO ZICNOTEDATA (ZNOTE, ZDATA) VALUES (?, ?)", -1, &st, nil)
            sqlite3_bind_int64(st, 1, Int64(pk))
            _ = data.withUnsafeBytes { sqlite3_bind_blob(st, 2, $0.baseAddress, Int32(data.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
            sqlite3_step(st); sqlite3_finalize(st)
            for (id, text) in alt {
                pk += 1
                exec(db, """
                    INSERT INTO ZICCLOUDSYNCINGOBJECT (Z_PK, ZIDENTIFIER, ZNOTE, ZTYPEUTI, ZALTTEXT)
                    VALUES (\(pk), \(q(id)), \(notePK), \(q(NotesBodyDecoder.hashtagUTI)), \(q(text)));
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
            P(text: "A chisel", style: 4), P(text: "Concert tickets?", style: 100, done: true),
            P(text: "Book on joinery", style: 100), P(text: "Plain line")], created: nil)
        let reader = try NotesStoreReader(copying: try makeStore([note]))
        let s = try XCTUnwrap(try reader.listNotes().first)
        XCTAssertNil(s.created, "no creation date stays nil: Date unknown, never today (Q141)")
        let d = try XCTUnwrap(reader.content(of: s))
        XCTAssertEqual(d.markdown, "# Gift ideas\n\n## Soon\n\n- A chisel\n- [x] Concert tickets?\n- [ ] Book on joinery\n\nPlain line")
        XCTAssertEqual(d.media.checklistItems, 2); XCTAssertEqual(d.media.checklistDone, 1)
        XCTAssertEqual(AppleNotesTriage.ordered([s, AppleNoteSummary(id: "z", pk: 1, title: "dated", snippet: "", created: Date(), modified: nil, isLocked: false)]).last?.id, s.id,
                       "date unknown sorts last")
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

        var undated = s; undated.created = nil
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
