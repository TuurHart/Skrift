import XCTest
import SwiftData

/// Q448 (C142, C77): an email share keeps its attachments as note attachments (the Q385 kind:
/// a `[[file_NNN]]` marker per file after the body, in attachment order, a synced `MemoAsset`
/// per file), and an `.eml` in a dropped folder is an email capture like the direct drop.
/// Built on the `ingress/email` fixture with a second attachment added to its MIME tail.
@MainActor
final class EmailAttachmentsTests: XCTestCase {

    private static let secondText = "Glaze recipe: 3 parts frit, 1 part kaolin.\n"

    /// The corpus `ingress/email/message.eml` (one attachment, `schedule.txt`) plus a second
    /// part, `glaze.csv`, before the closing boundary.
    private func twoAttachmentMail() throws -> Data {
        let url = CorpusSeed.fixtureRoot(file: #filePath)
            .appendingPathComponent("ingress/email/message.eml")
        var text = try XCTUnwrap(String(data: try Data(contentsOf: url), encoding: .utf8))
        let closing = "--MIX-7f3a--"
        let range = try XCTUnwrap(text.range(of: closing, options: .backwards))
        let second = """
        --MIX-7f3a
        Content-Type: text/csv; name="glaze.csv"
        Content-Disposition: attachment; filename="glaze.csv"
        Content-Transfer-Encoding: base64

        \(Data(Self.secondText.utf8).base64EncodedString())
        """
        text.replaceSubrange(range, with: second + "\n" + closing)
        return Data(text.utf8)
    }

    private func localContext() throws -> ModelContext {
        ModelContext(try ModelContainer(for: PipelineFile.self,
                                        configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
    }

    private func cloudContext() throws -> ModelContext {
        ModelContext(try ModelContainer(for: Memo.self, MemoAsset.self, MemoEnhancement.self,
                                        configurations: ModelConfiguration(isStoredInMemoryOnly: true,
                                                                           cloudKitDatabase: .none)))
    }

    /// The parser sees both parts, in order (the fixture the rest builds on).
    func testFixtureHasTwoAttachmentsInOrder() throws {
        let mail = try XCTUnwrap(EmailShare.parse(try twoAttachmentMail()))
        XCTAssertEqual(mail.attachments.map(\.name), ["schedule.txt", "glaze.csv"])
    }

    /// A dropped `.eml`: the note carries both attachments, body then `[[file_001]]`, `[[file_002]]`.
    func testDroppedEmailKeepsBothAttachmentsInOrder() async throws {
        let src = makeTempDir(); defer { try? FileManager.default.removeItem(at: src) }
        let eml = src.appendingPathComponent("Kiln firing schedule.eml")
        try twoAttachmentMail().write(to: eml)

        let out = makeTempDir(); defer { try? FileManager.default.removeItem(at: out) }
        let report = try await IngestService(outputDir: out).ingestReport(localURLs: [eml], into: try localContext())
        let pf = try XCTUnwrap(report.created.first)
        XCTAssertEqual(pf.sourceType, .capture)

        // The body: the email's words, then one marker paragraph per file, in order.
        let body = try XCTUnwrap(pf.transcript)
        XCTAssertTrue(body.hasPrefix("Hi Tuur,"), body)
        XCTAssertTrue(body.hasSuffix("Ana\n\n[[file_001]]\n\n[[file_002]]"), body)
        XCTAssertEqual(NoteAttachment.markers(in: body).map(\.number), [1, 2])

        // The manifest names them in attachment order; the files hold the bytes.
        let folder = try XCTUnwrap(pf.workingFolder)
        let manifest = MacNoteAttachments.manifest(in: folder)
        XCTAssertEqual(manifest.map(\.name), ["schedule.txt", "glaze.csv"])
        XCTAssertEqual(manifest.map(\.kind), [NoteAttachment.Kind.file, NoteAttachment.Kind.file])
        let first = try XCTUnwrap(MacNoteAttachments.fileURL(manifest[0], working: folder))
        let second = try XCTUnwrap(MacNoteAttachments.fileURL(manifest[1], working: folder))
        XCTAssertEqual(try String(contentsOf: first, encoding: .utf8),
                       "Kiln schedule for the week: Tuesday bisque, Friday glaze.\n")
        XCTAssertEqual(try String(contentsOf: second, encoding: .utf8), Self.secondText)
    }

    /// Authored as a memo, the note carries both: the manifest in its metadata, one synced
    /// `file` asset per attachment under the manifest's (unique) filenames.
    func testAuthoredMemoCarriesBothAttachments() async throws {
        let src = makeTempDir(); defer { try? FileManager.default.removeItem(at: src) }
        let eml = src.appendingPathComponent("Kiln firing schedule.eml")
        try twoAttachmentMail().write(to: eml)
        let out = makeTempDir(); defer { try? FileManager.default.removeItem(at: out) }
        let report = try await IngestService(outputDir: out).ingestReport(localURLs: [eml], into: try localContext())
        let pf = try XCTUnwrap(report.created.first)

        let cloud = try cloudContext()
        XCTAssertEqual(try V2.backfill([pf], into: cloud), 1)
        let id = try XCTUnwrap(UUID(uuidString: pf.id))
        let memo = try XCTUnwrap(try cloud.fetch(FetchDescriptor<Memo>()).first { $0.id == id })
        let manifest = try XCTUnwrap(memo.metadata?.attachmentManifest)
        XCTAssertEqual(manifest.map(\.name), ["schedule.txt", "glaze.csv"])
        XCTAssertTrue(manifest.allSatisfy { $0.filename.contains(id.uuidString) })
        XCTAssertEqual(memo.annotationText?.hasSuffix("[[file_001]]\n\n[[file_002]]"), true)

        let assets = try cloud.fetch(FetchDescriptor<MemoAsset>()).filter { $0.memoID == id }
        XCTAssertEqual(Set(assets.map(\.kind)), [MemoAsset.Kind.file])
        XCTAssertEqual(assets.map(\.filename).sorted(), manifest.map(\.filename).sorted())
        let secondAsset = try XCTUnwrap(assets.first { $0.filename == manifest[1].filename })
        XCTAssertEqual(String(data: secondAsset.blob, encoding: .utf8), Self.secondText)
    }

    /// An `.eml` inside a dropped folder is an email capture (not skipped), attachments and all.
    func testEmailInAFolderIsAnEmailCapture() async throws {
        let root = makeTempDir(); defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("Mail", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try twoAttachmentMail().write(to: folder.appendingPathComponent("Kiln firing schedule.eml"))

        let out = makeTempDir(); defer { try? FileManager.default.removeItem(at: out) }
        let report = try await IngestService(outputDir: out).ingestReport(localURLs: [folder], into: try localContext())
        XCTAssertTrue(report.skipped.isEmpty, "\(report.skipped)")
        let pf = try XCTUnwrap(report.created.first)
        XCTAssertEqual(pf.sourceType, .capture)
        XCTAssertEqual(MacNoteAttachments.manifest(in: try XCTUnwrap(pf.workingFolder)).count, 2)
        XCTAssertTrue(try XCTUnwrap(pf.transcript).hasSuffix("[[file_001]]\n\n[[file_002]]"))
    }

    /// An email without attachments is as before: the body alone, no manifest.
    func testEmailWithoutAttachmentsIsUnchanged() {
        let entries = NoteAttachment.emailFiles([], owner: UUID()).map(\.entry)
        XCTAssertTrue(entries.isEmpty)
        XCTAssertEqual(NoteAttachment.appendingMarkers(to: "Hello", entries: entries), "Hello")
    }
}
