import XCTest
import Foundation

/// Q500 (C280): a directory-locating accessor creates its folder at most once per process
/// launch, never on every access. `AppPaths.ensureDirectory` is the one place that calls
/// `createDirectory`; it counts each real call.
final class DirectoryCreateOnceTests: XCTestCase {

    func testRepeatedAccessNeverCreatesAgain() {
        // Warm: the first read of each may create (once per launch).
        _ = AppPaths.appSupportDirectory
        _ = AppPaths.recordingsDirectory
        _ = AppPaths.audioOutputDirectory
        _ = AppPaths.namesFile; _ = AppPaths.settingsFile; _ = AppPaths.storeFile
        let before = AppPaths.createDirectoryCallCount
        for _ in 0..<500 {
            _ = AppPaths.appSupportDirectory
            _ = AppPaths.recordingsDirectory
            _ = AppPaths.audioOutputDirectory
            _ = AppPaths.namesFile
            _ = AppPaths.settingsFile
            _ = AppPaths.storeFile
            _ = AppPaths.memoCloudStoreFile
            _ = AppPaths.memoCloudFirstImportStamp
        }
        XCTAssertEqual(AppPaths.createDirectoryCallCount, before, "no createDirectory after the first read")
    }

    func testEnsureDirectoryCreatesOncePerPath() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("once_\(UUID().uuidString)/a/b")
        addTeardownBlock { try? FileManager.default.removeItem(at: dir.deletingLastPathComponent().deletingLastPathComponent()) }
        let before = AppPaths.createDirectoryCallCount
        XCTAssertEqual(AppPaths.ensureDirectory(dir), dir)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.path))
        for _ in 0..<100 { AppPaths.ensureDirectory(dir) }
        AppPaths.ensureDirectory(URL(fileURLWithPath: dir.path + "/"))   // same path, other spelling
        XCTAssertEqual(AppPaths.createDirectoryCallCount, before + 1)
    }

    func testTheAccessorsAreTheSameFolderEveryRead() {
        XCTAssertEqual(AppPaths.recordingsDirectory, AppPaths.recordingsDirectory)
        XCTAssertEqual(AppPaths.recordingsDirectory.deletingLastPathComponent().standardizedFileURL,
                       AppPaths.appSupportDirectory.standardizedFileURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: AppPaths.appSupportDirectory.path))
    }
}
