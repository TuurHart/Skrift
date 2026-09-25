import XCTest
import Foundation
import SwiftData

/// Q58 — sweep E twins + dead code (`plan/sweep-e-shared-twins.md`, `plan/sweep-d-mac.md`,
/// BUGS §4 2026-09-25 rows). One case per fix, scoped to what `./gate.sh`'s `UnitTests`
/// (MLX-free, host-less) target can reach — it compiles `Shared/` but NOT the Mac app's
/// `Features/` (where `LockGate+PipelineFile.swift` and `SkriftFormat` live) or the
/// `SkriftMobile` module (where the phone's `VocabularyCloudSync` re-warm lives). Those
/// two fixes are pinned at the shared layer each app's real call site routes through, and
/// separately verified to compile+link by the full `SkriftDesktop` app build this session
/// also ran (Q58 report).
final class SweepETwinsTests: XCTestCase {

    // MARK: - 1. Mac lock check routes through NoteVisibility.contentVisible — the ONE
    // predicate `LockGate+PipelineFile.isLocked` (Mac) and `LockGate+Memo.isLocked`
    // (phone) both now call, instead of the Mac's old inline reimplementation.

    func testNoteVisibilityPredicateMatchesLockedUnlockedTruthTable() {
        // Never locked → always visible, regardless of session state.
        XCTAssertTrue(NoteVisibility.contentVisible(locked: false, unlockedThisSession: false))
        XCTAssertTrue(NoteVisibility.contentVisible(locked: false, unlockedThisSession: true))
        // Locked + not unlocked this session → gated.
        XCTAssertFalse(NoteVisibility.contentVisible(locked: true, unlockedThisSession: false))
        // Locked + unlocked this session → visible.
        XCTAssertTrue(NoteVisibility.contentVisible(locked: true, unlockedThisSession: true))
    }

    // MARK: - 2. Vocab re-warm on `.adoptRemote` — pinned at the shared core both
    // adapters (phone `VocabularyCloudSync`, Mac `VocabularyCloudSync`) build on.
    // The Mac adapter's own `.adoptRemote` → `VocabularyBooster.shared.prewarm` call
    // is exercised by `VocabularySyncCoreTests`; the phone now mirrors it
    // (`SkriftMobile/Services/VocabularyCloudSync.swift:22-27`) — not reachable from
    // this target, so this case pins that BOTH platforms see `.adoptRemote` (the
    // signal each adapter's re-warm branches on) for the identical input.
    @MainActor
    func testAdoptRemoteSignalIsPlatformAgnostic() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: VocabularyRecord.self, configurations: config)
        let context = container.mainContext
        let remoteWords = ["Skrift", "Goodfriday"]
        context.insert(VocabularyRecord(words: remoteWords, modifiedAt: Date()))
        try context.save()

        let records = (try? context.fetch(FetchDescriptor<VocabularyRecord>())) ?? []
        let outcome = VocabularySyncCore.reconcile(
            localWords: [], localModifiedAt: .distantPast, records: records,
            insert: { context.insert($0) }, delete: { context.delete($0) })
        switch outcome {
        case .adoptRemote(let words, _):
            XCTAssertEqual(words, remoteWords)
        default:
            XCTFail("expected .adoptRemote — both adapters' re-warm branches key off this case")
        }
    }

    // MARK: - 3. NamesStore.pruneOldTombstones — now wired into both NamesCloudSync.run

    private func tempNamesStore() -> NamesStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("sweepE_names_\(UUID().uuidString).json")
        return NamesStore(fileURL: url)
    }

    func testTombstoneInsideRetentionWindowSurvivesPrune() {
        let store = tempNamesStore()
        let recent = ISO8601.string(from: Date().addingTimeInterval(-5 * 86_400)) // 5 days ago
        _ = store.save(NamesData(lastModifiedAt: ISO8601.now(), people: [
            Person(canonical: "[[Gone]]", lastModifiedAt: recent, deleted: true),
        ]))
        let pruned = store.pruneOldTombstones(maxAgeDays: 90)
        XCTAssertEqual(pruned, 0)
        XCTAssertEqual(store.load().people.map(\.canonical), ["[[Gone]]"])
    }

    func testPruneWithNoOldTombstonesLeavesFileBytesUnchanged() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("sweepE_names_\(UUID().uuidString).json")
        let store = NamesStore(fileURL: url)
        let recent = ISO8601.string(from: Date().addingTimeInterval(-1 * 86_400))
        _ = store.save(NamesData(lastModifiedAt: ISO8601.now(), people: [
            Person(canonical: "[[Live]]", lastModifiedAt: recent),
            Person(canonical: "[[AlsoGone]]", lastModifiedAt: recent, deleted: true),
        ]))
        let before = try Data(contentsOf: url)
        let pruned = store.pruneOldTombstones(maxAgeDays: 90)
        XCTAssertEqual(pruned, 0)
        let after = try Data(contentsOf: url)
        XCTAssertEqual(before, after, "a no-op prune must not rewrite names.json")
    }

    func testPrunePreservesLWWAndVoiceprintUnionForSurvivors() {
        let store = tempNamesStore()
        let old = ISO8601.string(from: Date().addingTimeInterval(-100 * 86_400))    // prunes
        let recent = ISO8601.string(from: Date().addingTimeInterval(-1 * 86_400))   // survives
        let embeddingA = VoiceEmbedding(vector: [0.1, 0.2], condition: "phone-mic")
        let embeddingB = VoiceEmbedding(vector: [0.3, 0.4], condition: "airpods")
        _ = store.save(NamesData(lastModifiedAt: ISO8601.now(), people: [
            Person(canonical: "[[Old]]", lastModifiedAt: old, deleted: true),
            Person(canonical: "[[Jane]]", aliases: ["Janey"], short: "Jane",
                   voiceEmbeddings: [embeddingA, embeddingB], lastModifiedAt: recent),
        ]))
        let pruned = store.pruneOldTombstones(maxAgeDays: 90)
        XCTAssertEqual(pruned, 1)
        let jane = store.load().people.first { $0.canonical == "[[Jane]]" }
        XCTAssertEqual(jane?.lastModifiedAt, recent, "LWW timestamp untouched by pruning a DIFFERENT person")
        XCTAssertEqual(jane?.voiceEmbeddings?.count, 2, "voiceprint union untouched by pruning")
    }

    // MARK: - 4. ONE duration formatter — `SkriftFormat.clock` (m:ss only, no hours) is
    // DELETED; all 6 former call sites (SidebarView, WayOutColumn, NoteProperties,
    // UnpipelinedMemoSheet, NoteToolbar ×2) now route through `.duration(seconds:)`,
    // the same formatter the sidebar already used correctly. `SkriftFormat` lives in
    // `Features/Sidebar/QueueDerivations.swift` (SwiftUI import) — outside what this
    // host-less target compiles; verified instead by the full `SkriftDesktop` app build
    // this session ran, plus the grep below proving zero surviving `.clock` call sites.

    func testClockFormatterCallSitesAreGone() throws {
        let root = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()  // SkriftDesktopTests
            .deletingLastPathComponent()  // SkriftDesktop
            .appendingPathComponent("Features")
        let en = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        var offenders: [String] = []
        while let url = en?.nextObject() as? URL {
            guard url.pathExtension == "swift",
                  let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            if text.contains("SkriftFormat.clock(") { offenders.append(url.lastPathComponent) }
        }
        XCTAssertTrue(offenders.isEmpty, "SkriftFormat.clock should be fully deleted, found in: \(offenders)")
    }

    // MARK: - 5/6. Cached regexes — behavior unchanged after hoisting to `static let`

    func testVaultTagScannerStillMatchesFrontmatterAndHashtagsAfterCaching() {
        let note = """
        ---
        tags: [work, #legacy]
        ---
        Some body text mentioning #urgent and #2fast (numeric-only dropped).
        """
        var tags = Set<String>()
        VaultTagScanner.collectTags(from: note, into: &tags)
        XCTAssertTrue(tags.contains("work"))
        XCTAssertTrue(tags.contains("legacy"))
        XCTAssertTrue(tags.contains("urgent"))
        XCTAssertFalse(tags.contains("2fast"))

        // Calling twice exercises the cached (reused) regex instance, not just a first hit.
        var tagsAgain = Set<String>()
        VaultTagScanner.collectTags(from: note, into: &tagsAgain)
        XCTAssertEqual(tags, tagsAgain)
    }

    func testSpeakerTurnStyleStillMatchesHeadersAfterCaching() {
        let body = "**Jane:** hello there\n**Nick:** hi Jane\n**Jane:** how are you\n"
        let firstPass = SpeakerTurnStyle.turns(in: body, people: [])
        let secondPass = SpeakerTurnStyle.turns(in: body, people: [])
        XCTAssertEqual(firstPass.count, 3)
        XCTAssertEqual(firstPass.map(\.display), secondPass.map(\.display))
    }

    // MARK: - 7. ePub DRM verdict — now surfaced to the user (phone `BookTextFlow`
    // outcome copy); pinned here at the Shared layer this target can reach: the
    // verdict carries a non-empty `reason` string, which is what the surfaced copy
    // (and the Mac's existing `RunFile.swift` debug log line) both need to be useful.

    func testProtectedDRMVerdictCarriesASurfaceableReason() throws {
        let containerXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
          <rootfiles>
            <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
          </rootfiles>
        </container>
        """
        let opf = """
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="2.0" unique-identifier="BookId">
          <metadata/>
          <manifest>
            <item id="ch1" href="chapter1.xhtml" media-type="application/xhtml+xml"/>
          </manifest>
          <spine><itemref idref="ch1"/></spine>
        </package>
        """
        let chapter1 = """
        <?xml version="1.0" encoding="UTF-8"?>
        <html xmlns="http://www.w3.org/1999/xhtml"><body><p>Text.</p></body></html>
        """
        let encryption = """
        <?xml version="1.0" encoding="UTF-8"?>
        <encryption xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
          <EncryptedData xmlns="http://www.w3.org/2001/04/xmlenc#">
            <EncryptionMethod Algorithm="http://www.adobe.com/adept"/>
            <CipherData><CipherReference URI="OEBPS/chapter1.xhtml"/></CipherData>
          </EncryptedData>
        </encryption>
        """
        let rights = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rights xmlns="http://ns.adobe.com/adept"><licenseToken/></rights>
        """
        let entries: [String: Data] = [
            "META-INF/container.xml": containerXML.data(using: .utf8)!,
            "OEBPS/content.opf": opf.data(using: .utf8)!,
            "OEBPS/chapter1.xhtml": chapter1.data(using: .utf8)!,
            "META-INF/encryption.xml": encryption.data(using: .utf8)!,
            "META-INF/rights.xml": rights.data(using: .utf8)!,
        ]
        let book = try EPubParse.parse(entries: entries)
        guard case .protected(let reason) = book.drm else {
            XCTFail("expected .protected, got \(book.drm)")
            return
        }
        XCTAssertFalse(reason.isEmpty, "the surfaced copy needs a non-empty reason to show")
    }
}
