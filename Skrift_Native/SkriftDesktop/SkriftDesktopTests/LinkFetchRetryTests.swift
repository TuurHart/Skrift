import XCTest
import SwiftData

/// Q266 (C72): the Mac's link door retries a failed page fetch at most three times, with a
/// doubling backoff, behind the `LinkFetching` seam. A stub fetcher plays the network and the
/// backoff sleep is recorded, never waited on.
@MainActor
final class LinkFetchRetryTests: XCTestCase {

    /// Fails the first `failures` GETs of each URL, then answers from `table`. Records calls.
    private final class FlakyFetcher: LinkFetching, @unchecked Sendable {
        private let lock = NSLock()
        private var failuresLeft: [String: Int] = [:]
        private let table: [String: LinkFetchResponse]
        private let failures: Int
        private var calls: [String] = []
        init(failures: Int, table: [String: LinkFetchResponse] = [:]) {
            self.failures = failures
            self.table = table
        }
        var recorded: [String] { lock.lock(); defer { lock.unlock() }; return calls }
        func fetch(_ url: URL, method: String, timeout: TimeInterval) async -> LinkFetchResponse? {
            let key = "\(method) \(url.absoluteString)"
            lock.lock(); defer { lock.unlock() }
            calls.append(key)
            let left = failuresLeft[key] ?? failures
            if left > 0 { failuresLeft[key] = left - 1; return nil }
            return table[key]
        }
    }

    private final class SleepLog: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [TimeInterval] = []
        var all: [TimeInterval] { lock.lock(); defer { lock.unlock() }; return values }
        func add(_ v: TimeInterval) { lock.lock(); values.append(v); lock.unlock() }
    }

    private let page = URL(string: "https://www.metro.example.org/article")!

    private func html(_ s: String) -> LinkFetchResponse {
        LinkFetchResponse(data: Data(s.utf8), contentType: "text/html; charset=utf-8")
    }

    private func service(_ fetcher: FlakyFetcher, sleeps: SleepLog) throws -> (IngestService, URL) {
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("lfr_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        var s = IngestService(outputDir: work.appendingPathComponent("out"))
        s.linkFetcher = fetcher
        s.linkRetrySleep = { sleeps.add($0) }
        return (s, work)
    }

    private func context() throws -> ModelContext {
        ModelContext(try ModelContainer(for: PipelineFile.self,
                                        configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
    }

    // MARK: - The wrapper

    func testAFailedGetIsRetriedUntilItSucceeds() async {
        let fetcher = FlakyFetcher(failures: 2, table: ["GET \(page.absoluteString)": html("<title>T</title>")])
        let sleeps = SleepLog()
        let retrying = RetryingLinkFetcher(base: fetcher, sleep: { sleeps.add($0) })
        let got = await retrying.fetch(page, method: "GET", timeout: 1)
        XCTAssertNotNil(got)
        XCTAssertEqual(fetcher.recorded.count, 3, "one try + two retries")
        XCTAssertEqual(sleeps.all, [0.5, 1], "doubling backoff before each retry")
    }

    func testAtMostThreeRetries() async {
        let fetcher = FlakyFetcher(failures: 100)
        let sleeps = SleepLog()
        let retrying = RetryingLinkFetcher(base: fetcher, sleep: { sleeps.add($0) })
        let got = await retrying.fetch(page, method: "GET", timeout: 1)
        XCTAssertNil(got)
        XCTAssertEqual(fetcher.recorded.count, 1 + RetryingLinkFetcher.maxRetries)
        XCTAssertEqual(RetryingLinkFetcher.maxRetries, 3, "C72: at most three times")
        XCTAssertEqual(sleeps.all, [0.5, 1, 2])
    }

    func testHeadIsNeverRetried() async {
        let fetcher = FlakyFetcher(failures: 100)
        let retrying = RetryingLinkFetcher(base: fetcher, sleep: { _ in })
        let got = await retrying.fetch(page, method: "HEAD", timeout: 1)
        XCTAssertNil(got)
        XCTAssertEqual(fetcher.recorded, ["HEAD \(page.absoluteString)"])
    }

    func testASuccessfulFirstGetIsNotRepeated() async {
        let fetcher = FlakyFetcher(failures: 0, table: ["GET \(page.absoluteString)": html("<title>T</title>")])
        let sleeps = SleepLog()
        let retrying = RetryingLinkFetcher(base: fetcher, sleep: { sleeps.add($0) })
        _ = await retrying.fetch(page, method: "GET", timeout: 1)
        XCTAssertEqual(fetcher.recorded.count, 1)
        XCTAssertTrue(sleeps.all.isEmpty)
    }

    // MARK: - Through the Mac's link door

    func testLinkDropRecoversFromAFailedFirstGet() async throws {
        let fetcher = FlakyFetcher(failures: 1, table: [
            "GET \(page.absoluteString)": html("<html><head><title>The Real Title</title></head><body></body></html>"),
        ])
        let sleeps = SleepLog()
        let (svc, work) = try service(fetcher, sleeps: sleeps)
        defer { try? FileManager.default.removeItem(at: work) }
        let pf = try XCTUnwrap(try await svc.ingestLink(page, into: try context()))
        let sc = try XCTUnwrap(SharedContent.decode(from: pf.audioMetadataJSON))
        XCTAssertEqual(sc.urlTitle, "The Real Title", "the retry reached the page")
        XCTAssertEqual(fetcher.recorded.filter { $0 == "GET \(page.absoluteString)" }.count, 2)
        XCTAssertEqual(sleeps.all, [0.5])
    }

    func testLinkDropThatNeverLoadsKeepsTheHostTitleAfterThreeRetries() async throws {
        let fetcher = FlakyFetcher(failures: 100)
        let sleeps = SleepLog()
        let (svc, work) = try service(fetcher, sleeps: sleeps)
        defer { try? FileManager.default.removeItem(at: work) }
        let pf = try XCTUnwrap(try await svc.ingestLink(page, into: try context()))
        let sc = try XCTUnwrap(SharedContent.decode(from: pf.audioMetadataJSON))
        XCTAssertEqual(sc.type, .url)
        XCTAssertEqual(sc.urlTitle, "metro.example.org", "no title → the host, never the raw URL")
        XCTAssertEqual(fetcher.recorded.filter { $0 == "GET \(page.absoluteString)" }.count,
                       1 + RetryingLinkFetcher.maxRetries)
    }
}
