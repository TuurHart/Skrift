import XCTest
@testable import SkriftMobile

/// Q513 (R38, C2): with export v2 routed (`ExportV2.routingOverride`), the iPad puts a `.file`
/// capture's shared document in the vault beside the note, named by the rule the Mac uses
/// (`ExportV2.documentName`), and links it from the capture block. No document bytes on this
/// device → no document and no dangling link. The Mac half is `ExportV2SwapGapsTests`.
@MainActor
final class ExportV2DocumentPhoneTests: XCTestCase {
    private var sandbox: URL!

    override func setUpWithError() throws {
        sandbox = FileManager.default.temporaryDirectory.appendingPathComponent("q513-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
        ExportV2.routingOverride = true
    }

    override func tearDownWithError() throws {
        ExportV2.routingOverride = nil
        try? FileManager.default.removeItem(at: sandbox)
    }

    private func publisher(document: Data?) -> ObsidianPublisher {
        var p = ObsidianPublisher(vaultProvider: { self.sandbox }, manageScope: false, author: "T",
                                  peopleProvider: { [] },
                                  ledgerOverride: ExportLedger(fileURL: sandbox.appendingPathComponent("ledger.json")))
        p.documentProvider = { _ in document }
        return p
    }

    private func capture() -> Memo {
        let m = Memo(title: "Kiln quote", transcript: "The price for the new kiln line.", significance: 0.5)
        m.sharedContent = SharedContent(type: .file, filePath: "Inbox/Offerte kiln.pdf", fileName: "Offerte kiln.pdf",
                                        mimeType: "application/pdf")
        return m
    }

    /// The folder Skrift owns inside the picked vault, which `relativePath` is relative to.
    private func home() -> URL { VaultLayout.home(forPicked: sandbox, profile: .obsidian) }

    private func files() -> [String] {
        (FileManager.default.enumerator(atPath: sandbox.path)?.allObjects as? [String] ?? []).sorted()
    }

    func testTheSharedDocumentGoesWithTheNote() throws {
        let pdf = Data("%PDF-1.4 kiln".utf8)
        let report = try publisher(document: pdf).publishReport(capture())
        let note = home().appendingPathComponent(report.relativePath)
        let md = try String(contentsOf: note, encoding: .utf8)
        let stem = note.deletingPathExtension().lastPathComponent
        let doc = try XCTUnwrap(files().first { $0.hasSuffix("/\(stem).pdf") || $0 == "\(stem).pdf" }, "\(files())")
        XCTAssertEqual(try Data(contentsOf: sandbox.appendingPathComponent(doc)), pdf, "the document's own bytes")
        XCTAssertTrue(md.contains("\(stem).pdf"), "the capture block names it\n\(md)")
    }

    func testNoBytesOnThisDeviceMeansNoDocumentAndNoLink() throws {
        let report = try publisher(document: nil).publishReport(capture())
        let md = try String(contentsOf: home().appendingPathComponent(report.relativePath), encoding: .utf8)
        XCTAssertFalse(files().contains { $0.hasSuffix(".pdf") }, "\(files())")
        XCTAssertFalse(md.contains(".pdf]]") || md.contains(".pdf)"), "no dangling link\n\(md)")
    }
}
