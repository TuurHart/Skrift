import XCTest
import SwiftData
import Foundation

private func multipartBody(
    boundary: String,
    parts: [(name: String, filename: String?, contentType: String?, data: Data)]
) -> Data {
    var body = Data()
    for p in parts {
        body.append(Data("--\(boundary)\r\n".utf8))
        var disp = "Content-Disposition: form-data; name=\"\(p.name)\""
        if let fn = p.filename { disp += "; filename=\"\(fn)\"" }
        body.append(Data("\(disp)\r\n".utf8))
        if let ct = p.contentType { body.append(Data("Content-Type: \(ct)\r\n".utf8)) }
        body.append(Data("\r\n".utf8))
        body.append(p.data)
        body.append(Data("\r\n".utf8))
    }
    body.append(Data("--\(boundary)--\r\n".utf8))
    return body
}

final class MultipartParserTests: XCTestCase {

    func testBoundaryExtraction() {
        XCTAssertEqual(MultipartParser.boundary(fromContentType: "multipart/form-data; boundary=----abc123"), "----abc123")
        XCTAssertEqual(MultipartParser.boundary(fromContentType: #"multipart/form-data; boundary="quoted""#), "quoted")
        XCTAssertNil(MultipartParser.boundary(fromContentType: "application/json"))
    }

    func testParseFileAndFieldParts() {
        let boundary = "----skrifttest"
        let body = multipartBody(boundary: boundary, parts: [
            ("files", "memo.m4a", "audio/mp4", Data("BINARYAUDIO".utf8)),
            ("metadata", nil, "application/json", Data(#"{"transcriptConfidence":0.9}"#.utf8)),
        ])
        let parts = MultipartParser.parse(body, boundary: boundary)
        XCTAssertEqual(parts.count, 2)
        let file = parts.first { $0.name == "files" }
        XCTAssertEqual(file?.filename, "memo.m4a")
        XCTAssertEqual(file?.contentType, "audio/mp4")
        XCTAssertEqual(file.flatMap { String(data: $0.data, encoding: .utf8) }, "BINARYAUDIO")
        let meta = parts.first { $0.name == "metadata" }
        XCTAssertEqual(meta.flatMap { String(data: $0.data, encoding: .utf8) }, #"{"transcriptConfidence":0.9}"#)
    }
}

final class UploadServiceTests: XCTestCase {

    private func memoryContext() throws -> ModelContext {
        let container = try ModelContainer(for: PipelineFile.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(container)
    }

    private func tempDir() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("up_\(UUID().uuidString)", isDirectory: true)
    }

    func testIngestTrustedTranscriptIsAccepted() throws {
        let svc = UploadService(outputDir: tempDir())
        let ctx = try memoryContext()
        let parts = [
            MultipartPart(name: "files", filename: "memo_abc.m4a", contentType: "audio/mp4", data: Data("AUDIO".utf8)),
            MultipartPart(name: "metadata", filename: nil, contentType: "application/json",
                          data: Data(#"{"transcriptConfidence":0.9}"#.utf8)),
            MultipartPart(name: "transcript", filename: nil, contentType: nil, data: Data("hello world".utf8)),
        ]
        let created = try svc.ingest(parts: parts, into: ctx)
        XCTAssertEqual(created.count, 1)
        let pf = created[0]
        XCTAssertEqual(pf.filename, "memo_abc.m4a")
        XCTAssertEqual(pf.transcript, "hello world")
        XCTAssertEqual(pf.transcribeStatus, .done)             // trusted (conf 0.9)
        XCTAssertEqual(pf.sanitiseStatus, .pending)            // Mac links names
        XCTAssertTrue(FileManager.default.fileExists(atPath: pf.path))
        XCTAssertNotNil(pf.audioMetadataJSON)                  // metadata preserved verbatim
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<PipelineFile>()).count, 1)
    }

    func testIngestUntrustedTranscriptIsDropped() throws {
        let svc = UploadService(outputDir: tempDir())
        let ctx = try memoryContext()
        let parts = [
            MultipartPart(name: "files", filename: "memo_xyz.m4a", contentType: "audio/mp4", data: Data("AUDIO".utf8)),
            MultipartPart(name: "metadata", filename: nil, contentType: "application/json",
                          data: Data(#"{"transcriptConfidence":0.5}"#.utf8)),
            MultipartPart(name: "transcript", filename: nil, contentType: nil, data: Data("low conf".utf8)),
        ]
        let pf = try XCTUnwrap(svc.ingest(parts: parts, into: ctx).first)
        XCTAssertNil(pf.transcript)                            // dropped (conf 0.5 < 0.7, not edited)
        XCTAssertEqual(pf.transcribeStatus, .pending)
    }

    func testTrustViaUserEditedFlag() throws {
        let svc = UploadService()
        XCTAssertTrue(svc.isTranscriptTrusted(["transcriptUserEdited": true]))
        XCTAssertTrue(svc.isTranscriptTrusted(["transcriptConfidence": 0.7]))
        XCTAssertFalse(svc.isTranscriptTrusted(["transcriptConfidence": 0.69]))
        XCTAssertFalse(svc.isTranscriptTrusted(nil))
    }
}
