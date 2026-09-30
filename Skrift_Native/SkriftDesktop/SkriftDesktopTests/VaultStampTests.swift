import XCTest

/// `VaultStamp` — the exported-note contract (roadmap i14: a future Obsidian plugin
/// reads these keys, so the format is pinned here on purpose).
final class VaultStampTests: XCTestCase {

    private let id = UUID(uuidString: "7C3F2A1B-0000-4000-8000-000000000001")!

    private func note(_ body: String = "The body.", title: String = "A note") -> String {
        """
        ---
        title: "\(title)"
        lastTouched:
        author: Tuur
        tags:
          - work
        ---

        \(body)
        """
    }

    // MARK: - writing

    func testApplyStampsIDHashAndARealTimestamp() throws {
        let out = VaultStamp.apply(to: note(), id: id, touchedAt: Date(timeIntervalSince1970: 1_785_000_000))
        let marks = try XCTUnwrap(VaultStamp.read(out))
        XCTAssertEqual(marks.id, id)
        XCTAssertFalse(marks.hash.isEmpty)
        XCTAssertTrue(out.contains("\(VaultStamp.touchedKey): 2026-07-"))
    }

    /// The stamp must reuse the EXISTING `lastTouched:` line rather than adding a second
    /// one — a duplicate YAML key is invalid and Obsidian rejects the whole block.
    func testApplyReplacesTheEmptyLastTouchedInPlace() {
        let out = VaultStamp.apply(to: note(), id: id)
        let occurrences = out.components(separatedBy: "\n").filter { $0.hasPrefix("\(VaultStamp.touchedKey):") }
        XCTAssertEqual(occurrences.count, 1)
    }

    func testStampingIsIdempotentAndStable() {
        let once = VaultStamp.apply(to: note(), id: id, touchedAt: Date(timeIntervalSince1970: 1_785_000_000))
        let twice = VaultStamp.apply(to: once, id: id, touchedAt: Date(timeIntervalSince1970: 1_785_000_000))
        XCTAssertEqual(once, twice, "re-stamping the same content at the same time must not churn the file")
    }

    /// Only Skrift's own compiler output gets stamped. A file with no frontmatter is
    /// something we don't own — inventing a YAML block in it would be an edit.
    func testTextWithoutFrontmatterIsLeftAlone() {
        let plain = "Just a note someone wrote.\n"
        XCTAssertEqual(VaultStamp.apply(to: plain, id: id), plain)
        XCTAssertNil(VaultStamp.read(plain))
    }

    // MARK: - the three questions

    func testAbsentFileIsSafeToCreate() {
        XCTAssertEqual(VaultStamp.standing(of: nil), .absent)
    }

    /// Q1 — is it ours? An unstamped file must read as foreign, which is what stops the
    /// Mac replacing a hand-authored note whose title collides.
    func testUnstampedFileReadsAsForeign() {
        XCTAssertEqual(VaultStamp.standing(of: note()), .foreign)
        XCTAssertEqual(VaultStamp.standing(of: "no frontmatter at all"), .foreign)
    }

    func testOurOwnUntouchedOutputIsSafeToOverwrite() throws {
        let written = VaultStamp.apply(to: note(), id: id)
        guard case .untouched(let marks) = VaultStamp.standing(of: written) else {
            return XCTFail("expected untouched, got \(VaultStamp.standing(of: written))")
        }
        XCTAssertEqual(marks.id, id)
    }

    /// Q2 — a body edit is detected.
    func testABodyEditIsDetected() {
        let written = VaultStamp.apply(to: note(), id: id)
        let edited = written + "\n\nA thought I added in Obsidian.\n"
        guard case .userEdited(let marks) = VaultStamp.standing(of: edited) else {
            return XCTFail("expected userEdited, got \(VaultStamp.standing(of: edited))")
        }
        XCTAssertEqual(marks.id, id, "still identifiably the same note")
    }

    /// …and so is a FRONTMATTER edit, which is the whole reason the hash spans the
    /// frontmatter: adding a tag in Obsidian's properties panel must count as an edit,
    /// not silently lose to the next export.
    func testATagAddedInObsidianIsDetected() {
        let written = VaultStamp.apply(to: note(), id: id)
        let edited = written.replacingOccurrences(of: "  - work", with: "  - work\n  - ideas")
        guard case .userEdited = VaultStamp.standing(of: edited) else {
            return XCTFail("a frontmatter edit must register as a user edit")
        }
    }

    /// A retitled note is still detected as edited rather than as a different note.
    func testARenameInObsidianIsAnEditNotANewNote() throws {
        let written = VaultStamp.apply(to: note(title: "A note"), id: id)
        let edited = written.replacingOccurrences(of: "title: \"A note\"", with: "title: \"Renamed by hand\"")
        guard case .userEdited(let marks) = VaultStamp.standing(of: edited) else {
            return XCTFail("expected userEdited")
        }
        XCTAssertEqual(marks.id, id)
    }

    /// Q3 — the id survives being filed out of the inbox, because it's in the file and
    /// not in a remembered path. This is what stops a moved note becoming a duplicate.
    func testTheIDIdentifiesTheNoteRegardlessOfWhereItLives() throws {
        let written = VaultStamp.apply(to: note(), id: id)
        // "Moving" a file changes its path, never its bytes.
        XCTAssertEqual(try XCTUnwrap(VaultStamp.read(written)).id, id)
    }

    // MARK: - fingerprint mechanics

    /// Self-reference is impossible, so the hash covers everything BUT its own line —
    /// verified by the fact that rewriting that line alone doesn't change the value.
    func testFingerprintIgnoresOnlyItsOwnLine() {
        let written = VaultStamp.apply(to: note(), id: id)
        let tampered = VaultStamp.upsert(written, key: VaultStamp.hashKey, value: "deadbeef")
        XCTAssertEqual(VaultStamp.fingerprint(of: written), VaultStamp.fingerprint(of: tampered))
        guard case .userEdited = VaultStamp.standing(of: tampered) else {
            return XCTFail("a tampered hash must not validate")
        }
    }

    /// A nested key (`daylight:`'s children are indented) must never be mistaken for a
    /// top-level one.
    func testIndentedKeysAreNotTopLevel() {
        let fm = "daylight:\n  sunrise: \"06:12\"\nskriftID: \(id.uuidString)"
        XCTAssertEqual(VaultStamp.value(of: "skriftID", in: fm), id.uuidString)
        XCTAssertNil(VaultStamp.value(of: "sunrise", in: fm), "indented ⇒ not a top-level scalar")
    }

    /// The empty `lastTouched:` state distinguishes "present but blank" from "absent".
    func testPresentButEmptyKeyReadsAsEmptyNotMissing() throws {
        let fm = try XCTUnwrap(VaultStamp.frontmatter(note()))
        XCTAssertEqual(VaultStamp.value(of: VaultStamp.touchedKey, in: fm), "")
        XCTAssertNil(VaultStamp.value(of: "nosuchkey", in: fm))
    }
}
