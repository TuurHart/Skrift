import XCTest

/// B3 — vault tag-whitelist scan. Verified against a SYNTHETIC temp vault (never the
/// user's real vault — privacy).
final class VaultTagScannerTests: XCTestCase {

    func testFrontmatterTagsBlockList() {
        XCTAssertEqual(VaultTagScanner.frontmatterTags("title: x\ntags:\n  - work\n  - ideas"), ["work", "ideas"])
    }
    func testFrontmatterTagsInlineForms() {
        XCTAssertEqual(VaultTagScanner.frontmatterTags("tags: [work, ideas]"), ["work", "ideas"])
        XCTAssertEqual(VaultTagScanner.frontmatterTags("tags: work, ideas"), ["work", "ideas"])
    }

    func testCollectMergesFrontmatterAndInlineLowercasedDeduped() {
        var tags = Set<String>()
        VaultTagScanner.collectTags(from: "---\ntags: [Work]\n---\nbody with #swift and #2024 and #Work dup.", into: &tags)
        XCTAssertEqual(tags, ["work", "swift"])   // lowercased, numeric-only #2024 dropped, dup merged
    }

    func testScanTempVaultIgnoresNonMarkdown() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("vault_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try "---\ntags:\n  - alpha\n---\nhi".write(to: dir.appendingPathComponent("a.md"), atomically: true, encoding: .utf8)
        try "no frontmatter but #beta here".write(to: dir.appendingPathComponent("b.md"), atomically: true, encoding: .utf8)
        try "not markdown #gamma".write(to: dir.appendingPathComponent("c.txt"), atomically: true, encoding: .utf8)
        XCTAssertEqual(VaultTagScanner.scan(root: dir), ["alpha", "beta"])
    }
}
