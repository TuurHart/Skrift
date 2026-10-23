import XCTest
@testable import SkriftMobile

/// Q496 (C292): model-download completeness is every file at its exact expected byte count,
/// never a size floor. A truncated-but-over-floor download is incomplete and resumes from
/// its end. Network is a URLProtocol stub for one fake repo; nothing leaves the process.
final class ModelDownloadCompletenessTests: XCTestCase {

    private var root: URL!
    private let repo = "skrift-test/fake-model"

    override func setUp() {
        super.setUp()
        root = FileManager.default.temporaryDirectory.appendingPathComponent("models_\(UUID().uuidString)")
        StubHub.reset()
        URLProtocol.registerClass(StubHub.self)
    }

    override func tearDown() {
        URLProtocol.unregisterClass(StubHub.self)
        try? FileManager.default.removeItem(at: root)
        super.tearDown()
    }

    private func dir() throws -> URL {
        let d = ResumableModelDownloader(root: root).snapshotDirectory(id: repo, revision: "main")
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    /// A sparse file of `size` bytes (instant on APFS; no real disk used).
    private func sparse(_ url: URL, size: Int64) throws {
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let h = try FileHandle(forWritingTo: url)
        try h.truncate(atOffset: UInt64(size))
        try h.close()
    }

    func testTruncatedButOverTheOldFloorIsIncomplete() throws {
        let d = try dir()
        let want: Int64 = 700_000_000
        try ResumableModelDownloader.writeExpected([.init(name: "model.safetensors", size: want)], in: d)
        try sparse(d.appendingPathComponent("model.safetensors"), size: 600_000_000)
        XCTAssertGreaterThan(ResumableModelDownloader.sizeOnDisk(d.appendingPathComponent("model.safetensors")),
                             500_000_000, "the old 500 MB floor would have called this downloaded")
        XCTAssertFalse(ResumableModelDownloader(root: root).isComplete(id: repo, revision: "main"))

        try sparse(d.appendingPathComponent("model.safetensors"), size: want)
        XCTAssertTrue(ResumableModelDownloader(root: root).isComplete(id: repo, revision: "main"))
    }

    func testNoRecordOfWhatWasAskedForIsIncomplete() throws {
        let d = try dir()
        try sparse(d.appendingPathComponent("model.safetensors"), size: 4_000_000_000)
        XCTAssertFalse(ResumableModelDownloader(root: root).isComplete(id: repo, revision: "main"))
    }

    func testAMissingOrOvershotFileIsIncomplete() throws {
        let d = try dir()
        try ResumableModelDownloader.writeExpected([.init(name: "a.bin", size: 10), .init(name: "b.json", size: 5)], in: d)
        try Data(count: 10).write(to: d.appendingPathComponent("a.bin"))
        XCTAssertFalse(ResumableModelDownloader(root: root).isComplete(id: repo, revision: "main"), "b.json missing")
        try Data(count: 6).write(to: d.appendingPathComponent("b.json"))
        XCTAssertFalse(ResumableModelDownloader(root: root).isComplete(id: repo, revision: "main"), "b.json overshot")
        try Data(count: 5).write(to: d.appendingPathComponent("b.json"))
        XCTAssertTrue(ResumableModelDownloader(root: root).isComplete(id: repo, revision: "main"))
    }

    /// A short weights file left in place resumes from its own end (one Range request),
    /// and the finished snapshot then reads complete.
    func testTruncatedFileResumesFromItsEnd() async throws {
        let d = try dir()
        let blob = Data((0..<65_536).map { UInt8($0 % 251) })
        let config = Data(#"{"model_type":"fake"}"#.utf8)
        StubHub.files = ["weights.bin": blob, "config.json": config]
        try blob.prefix(40_000).write(to: d.appendingPathComponent("weights.bin"))
        XCTAssertFalse(ResumableModelDownloader(root: root).isComplete(id: repo, revision: "main"))

        let out = try await ResumableModelDownloader(root: root, attemptsPerFile: 2)
            .download(id: repo, revision: "main", matching: [], useLatest: false) { _ in }

        XCTAssertEqual(out, d)
        XCTAssertEqual(try Data(contentsOf: d.appendingPathComponent("weights.bin")), blob)
        XCTAssertEqual(try Data(contentsOf: d.appendingPathComponent("config.json")), config)
        let weightRequests = StubHub.requests.filter { $0.path.hasSuffix("/weights.bin") }
        XCTAssertEqual(weightRequests.map(\.range), ["bytes=40000-"], "resumed, not refetched from zero")
        XCTAssertTrue(ResumableModelDownloader(root: root).isComplete(id: repo, revision: "main"))
    }
}

/// Serves the fake repo's manifest and files, honouring `Range:`; records each request.
private final class StubHub: URLProtocol {
    struct Seen { let path: String; let range: String? }
    nonisolated(unsafe) static var files: [String: Data] = [:]
    nonisolated(unsafe) static var requests: [Seen] = []
    private static let lock = NSLock()

    static func reset() { lock.lock(); files = [:]; requests = []; lock.unlock() }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "huggingface.co" && (request.url?.path.contains("skrift-test/fake-model") ?? false)
    }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let url = request.url!
        let range = request.value(forHTTPHeaderField: "Range")
        Self.lock.lock(); Self.requests.append(Seen(path: url.path, range: range)); let files = Self.files; Self.lock.unlock()

        if url.path.hasPrefix("/api/models/") {
            let siblings = files.map { ["rfilename": $0.key, "size": $0.value.count] as [String: Any] }
            let body = try! JSONSerialization.data(withJSONObject: ["siblings": siblings])
            respond(200, body)
            return
        }
        guard let name = url.path.components(separatedBy: "/resolve/main/").last, let data = files[name] else {
            respond(404, Data()); return
        }
        if let range, range.hasPrefix("bytes="), let start = Int(range.dropFirst(6).dropLast()) {
            respond(206, data.subdata(in: start..<data.count))
        } else {
            respond(200, data)
        }
    }

    private func respond(_ status: Int, _ body: Data) {
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Length": "\(body.count)"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
}
