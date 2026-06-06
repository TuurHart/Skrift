import XCTest
import Foundation

final class HTTPParserTests: XCTestCase {

    func testParseGETWithQuery() {
        let raw = Data("GET /api/files/?since=5 HTTP/1.1\r\nHost: skrift.local\r\n\r\n".utf8)
        let req = HTTPParser.parse(raw)
        XCTAssertEqual(req?.method, .GET)
        XCTAssertEqual(req?.path, "/api/files/")
        XCTAssertEqual(req?.query["since"], "5")
    }

    func testParsePUTBodyAndIncomplete() {
        let body = #"{"hi":1}"#
        let head = "PUT /api/names HTTP/1.1\r\nContent-Type: application/json\r\nContent-Length: \(body.utf8.count)\r\n\r\n"
        // Body not yet arrived → nil (caller keeps reading).
        XCTAssertNil(HTTPParser.parse(Data(head.utf8)))
        // Full request parses.
        let req = HTTPParser.parse(Data((head + body).utf8))
        XCTAssertEqual(req?.method, .PUT)
        XCTAssertEqual(req?.path, "/api/names")
        XCTAssertEqual(req.flatMap { String(data: $0.body, encoding: .utf8) }, body)
    }
}

final class SyncHandlerTests: XCTestCase {

    private func handlers() -> SyncHandlers {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("names_\(UUID().uuidString).json")
        return SyncHandlers(namesStore: NamesStore(fileURL: url))
    }

    private func req(_ m: HTTPMethod, _ path: String, body: Data = Data()) -> HTTPRequest {
        HTTPRequest(method: m, path: path, query: [:], headers: [:], body: body)
    }

    func testHealth() {
        let resp = handlers().handle(req(.GET, "/api/system/health"))
        XCTAssertEqual(resp.status, 200)
        XCTAssertTrue(String(data: resp.body, encoding: .utf8)?.contains("\"healthy\"") == true)
    }

    func testNamesRoundTrip() throws {
        let h = handlers()
        let put = Data(#"{"people":[{"canonical":"[[Nick]]","aliases":["Nicky"],"short":"Nick","lastModifiedAt":"2026-01-01T00:00:00.000Z"}]}"#.utf8)
        XCTAssertEqual(h.handle(req(.PUT, "/api/names", body: put)).status, 200)

        let getResp = h.handle(req(.GET, "/api/names"))
        let data = try JSONDecoder().decode(NamesData.self, from: getResp.body)
        XCTAssertEqual(data.people.count, 1)
        XCTAssertEqual(data.people.first?.canonical, "[[Nick]]")
        XCTAssertEqual(data.people.first?.aliases, ["Nicky"])

        // Top-level timestamp is recomputed = max per-entry.
        let metaResp = h.handle(req(.GET, "/api/names/meta"))
        let meta = try JSONDecoder().decode([String: String].self, from: metaResp.body)
        XCTAssertEqual(meta["lastModifiedAt"], "2026-01-01T00:00:00.000Z")
    }

    func testTrailingSlashRoutesAndNotFound() {
        let h = handlers()
        XCTAssertEqual(h.handle(req(.GET, "/api/names/")).status, 200)   // trailing slash tolerated
        XCTAssertEqual(h.handle(req(.GET, "/api/unknown")).status, 404)
    }

    func testFilesListDefaultsEmpty() throws {
        let resp = handlers().handle(req(.GET, "/api/files/"))
        XCTAssertEqual(resp.status, 200)
        let arr = try JSONSerialization.jsonObject(with: resp.body) as? [Any]
        XCTAssertEqual(arr?.count, 0)
    }
}
