import XCTest

/// Q440: the share-door cases of `IngressDispatchTests` (C126 C127 C146), against the fixtures
/// `ingress/named-voice-memo`, `ingress/same-file-twice`, `ingress/skriftbook-via-share`. The
/// every-door table in `IngressDispatchTests.swift` checks their plans; these check the rules.
extension IngressDispatchTests {

    private static var q440Root: URL {
        CorpusSeed.fixtureRoot(file: #filePath).appendingPathComponent("ingress", isDirectory: true)
    }

    private struct Q440Manifest: Decodable { var items: [IngressDispatch.Item] }

    private func q440Outcome(_ door: String) throws -> IngressDispatch.Outcome {
        let url = Self.q440Root.appendingPathComponent(door).appendingPathComponent("providers.json")
        return IngressDispatch.dispatch(try JSONDecoder().decode(Q440Manifest.self, from: Data(contentsOf: url)).items)
    }

    // MARK: C126

    /// A Voice Memo shared as "kiln idea.m4a" keeps "kiln idea" as the note title.
    func testNamedVoiceMemoKeepsItsName() throws {
        guard case .plan(let plan) = try q440Outcome("named-voice-memo") else { return XCTFail("refused") }
        XCTAssertEqual(plan.kind, .audio)
        XCTAssertEqual(plan.clips, ["kiln idea.m4a"])
        XCTAssertEqual(plan.title, "kiln idea")
    }

    /// A messenger's, the system's or Skrift's own file name is never a title.
    func testMessengerFilenameIsNeverATitle() throws {
        for name in ["PTT-20241003-WA0007.opus", "AUD-20241003-WA0002.m4a", "WhatsApp Audio 2025-12-18 at 18.30.44.opus",
                     "signal-2024-10-03-120001.aac", "voice_1.ogg", "audio_2024-10-03_12-00-01.ogg",
                     "audioclip1734567890.mp4", "Voice message.m4a", "shared_8F2C1B7A-0000-4000-8000-123456789ABC.m4a",
                     "shared_import_8F2C1B7A-0000-4000-8000-123456789ABC_0.m4a", "20241003 120001.m4a", ""] {
            XCTAssertNil(IngressDispatch.clipTitle(name), name)
        }
        XCTAssertNil(IngressDispatch.clipTitle(nil))
        XCTAssertEqual(IngressDispatch.clipTitle("Rua Augusta 12.m4a"), "Rua Augusta 12")
        XCTAssertEqual(IngressDispatch.clipTitle("Dinner idea"), "Dinner idea")

        // The WhatsApp door, the Telegram name: one or more messenger clips, no title.
        guard case .plan(let wa) = try q440Outcome("whatsapp-3-items") else { return XCTFail("refused") }
        XCTAssertNil(wa.title)
        let telegram = [IngressDispatch.Item(providers: [.init(uti: ["public.data"], file: "voice_1.ogg")])]
        guard case .plan(let tg) = IngressDispatch.dispatch(telegram) else { return XCTFail("refused") }
        XCTAssertNil(tg.title)
        // Two named clips: one note, no single name to give it.
        let two = [IngressDispatch.Item(providers: [.init(uti: ["com.apple.m4a-audio"], file: "kiln idea.m4a"),
                                                    .init(uti: ["com.apple.m4a-audio"], file: "glaze test.m4a")])]
        guard case .plan(let both) = IngressDispatch.dispatch(two) else { return XCTFail("refused") }
        XCTAssertNil(both.title)
    }

    // MARK: C127

    /// The same bytes shared twice (under two WhatsApp names) find the first share's note.
    func testSameFileTwiceIsOneNote() throws {
        let dir = Self.q440Root.appendingPathComponent("same-file-twice", isDirectory: true)
        let first = dir.appendingPathComponent("first-share/PTT-20241007-WA0012.opus")
        let second = dir.appendingPathComponent("second-share/PTT-20241009-WA0031.opus")
        let different = dir.appendingPathComponent("different.opus")

        let fp1 = try XCTUnwrap(ShareFingerprint.of(files: [first]))
        let fp2 = try XCTUnwrap(ShareFingerprint.of(files: [second]))
        let fp3 = try XCTUnwrap(ShareFingerprint.of(files: [different]))
        XCTAssertEqual(fp1, fp2, "same bytes, different names: one fingerprint")
        XCTAssertNotEqual(fp1, fp3, "one byte apart: two files")
        XCTAssertNil(ShareFingerprint.of(files: []))
        XCTAssertNil(ShareFingerprint.of(files: [dir.appendingPathComponent("missing.opus")]))
        XCTAssertEqual(ShareFingerprint.of(files: [], datas: [Data("photo".utf8)]),
                       ShareFingerprint.of(files: [], datas: [Data("photo".utf8)]))

        // Both shares dispatch the same plan; the ledger is what makes the second one a no-op.
        guard case .plan(let plan) = try q440Outcome("same-file-twice") else { return XCTFail("refused") }
        XCTAssertEqual(plan.clips, ["PTT-20241007-WA0012.opus"])
        XCTAssertNil(plan.title)

        let ledgerURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("q440-ledger-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: ledgerURL) }
        let ledger = ShareLedger(fileURL: ledgerURL)
        let note = UUID()
        XCTAssertNil(ledger.existing(fp1), "the first share is new")
        XCTAssertTrue(ledger.record(fp1, id: note))
        XCTAssertEqual(ledger.existing(fp2), note, "the second share yields the existing note")
        XCTAssertNil(ledger.existing(fp3))

        // The note was deleted: the app prunes the row and the file can come in again.
        ledger.prune { $0 != note }
        XCTAssertNil(ledger.existing(fp2))
    }

    // MARK: C146

    /// A `.skriftbook` through the share sheet is a book for the importer, never a file card.
    func testSkriftbookViaShareGoesToBooks() throws {
        guard case .plan(let plan) = try q440Outcome("skriftbook-via-share") else { return XCTFail("refused") }
        XCTAssertEqual(plan.kind, .document)
        XCTAssertEqual(plan.bookFile, "The Potter's Year.skriftbook")
        XCTAssertTrue(IngressDispatch.isBookFile("Mine.skriftbookdev"), "a Dev build's bundle too")

        let pdf = [IngressDispatch.Item(providers: [.init(uti: ["com.adobe.pdf"], file: "paper.pdf")])]
        guard case .plan(let doc) = IngressDispatch.dispatch(pdf) else { return XCTFail("refused") }
        XCTAssertNil(doc.bookFile, "a PDF stays a document")
    }
}
