import XCTest

extension XCTestCase {
    /// A fresh, existing temp directory, removed when the test finishes. The one temp-dir
    /// helper for this test bundle (Q248) — don't define a private `tempDir()` per class.
    func makeTempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            XCTFail("could not create temp dir \(dir.path): \(error)")
        }
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }
}
