import XCTest
import SwiftData

/// Q303 (PRIVACY): headless `-snapshot*` modes never read the live Dev store. Two layers:
/// the stores themselves go in-memory under any `-snapshot*` flag, and Snapshot.swift
/// itself builds only in-memory containers and hands the sidebar an explicit (never nil)
/// quiet-row fixture. The app target is not compiled into this host-less bundle, so the
/// second layer reads the source file.
final class SnapshotIsolationQ303Tests: XCTestCase {

    func testEverySnapshotModeRequestsIsolation() {
        let modes = ["-snapshot", "-snapshot-light", "-snapshot-capture", "-snapshot-shell",
                     "-snapshot-sidebar-selection", "-snapshot-capture-corpus", "-snapshot-journal"]
        for m in modes {
            XCTAssertTrue(HeadlessIsolation.isRequested(arguments: ["Skrift", m, "/tmp/x.png"]), m)
        }
        XCTAssertTrue(HeadlessIsolation.isRequested(arguments: ["Skrift", "-isolatedRun"]))
    }

    func testNormalLaunchIsNotIsolated() {
        XCTAssertFalse(HeadlessIsolation.isRequested(arguments: ["Skrift"]))
        XCTAssertFalse(HeadlessIsolation.isRequested(arguments: ["Skrift", "-demo"]))
    }

    /// The configuration the snapshot path builds is memory-only and CloudKit-free.
    func testSnapshotContainerConfigIsInMemory() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        XCTAssertTrue(config.isStoredInMemoryOnly)
        let container = try ModelContainer(
            for: Schema([PipelineFile.self, Memo.self, MemoAsset.self, MemoEnhancement.self]),
            configurations: config)
        XCTAssertTrue(container.configurations.allSatisfy { $0.isStoredInMemoryOnly })
    }

    // MARK: - Snapshot.swift source scan

    private var snapshotSource: String {
        get throws {
            // .../SkriftDesktop/SkriftDesktopTests/<this file> -> .../SkriftDesktop/Features/Shell/Snapshot.swift
            let url = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("Features/Shell/Snapshot.swift")
            return try String(contentsOf: url, encoding: .utf8)
        }
    }

    func testSnapshotFileOnlyBuildsInMemoryContainers() throws {
        let lines = try snapshotSource.components(separatedBy: "\n")
        var found = 0
        for (i, line) in lines.enumerated() where line.contains("ModelContainer(") {
            found += 1
            let window = lines[i..<min(i + 4, lines.count)].joined(separator: "\n")
            XCTAssertTrue(window.contains("isStoredInMemoryOnly: true"),
                          "Snapshot.swift:\(i + 1) builds a ModelContainer that is not in-memory")
        }
        XCTAssertGreaterThan(found, 5, "scan found no containers; the path in this test is stale")
    }

    func testSnapshotFileNeverTouchesTheLiveStores() throws {
        let code = try snapshotSource.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        XCTAssertFalse(code.contains("MemoCloudStore.container"))
        XCTAssertFalse(code.contains("MemoCloudStore.syncContainer"))
        XCTAssertFalse(code.contains("SharedStore.container"))
    }

    func testEverySidebarInSnapshotGetsAnExplicitQuietRowFixture() throws {
        let lines = try snapshotSource.components(separatedBy: "\n")
        var found = 0
        for (i, line) in lines.enumerated() where line.contains("SidebarView(") {
            found += 1
            let window = lines[i..<min(i + 4, lines.count)].joined(separator: "\n")
            XCTAssertTrue(window.contains("fixtureCloudMemos:"),
                          "Snapshot.swift:\(i + 1) SidebarView falls back to the live CloudKit store")
        }
        XCTAssertGreaterThanOrEqual(found, 7)
    }
}
