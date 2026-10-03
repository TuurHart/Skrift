import XCTest
import Foundation
import SwiftUI

/// Q172 (P73, C239): logic the phone and the Mac each typed out is now ONE Shared function
/// both apps call. One case per function. Identical body in the phone and Mac test targets
/// (the phone copy adds `@testable import SkriftMobile`): same input, same output.
final class TwinLogicSharedTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func daysAgo(_ n: Int) -> Date { now.addingTimeInterval(-Double(n) * 86_400) }
    private func memo(days: Int, transcript: String = "hello", deletedDaysAgo: Int? = nil) -> Memo {
        let id = UUID()
        return Memo(id: id, audioFilename: "memo_\(id.uuidString).m4a", recordedAt: daysAgo(days),
                    title: nil, transcript: transcript, transcriptStatus: .done, significance: 0,
                    deletedAt: deletedDaysAgo.map { daysAgo($0) })
    }

    // setexp-08: appTheme → ColorScheme (phone SkriftApp, Mac AppTheme).
    func testThemePreferenceMapping() {
        XCTAssertEqual(ThemePreference.key, "appTheme")
        XCTAssertEqual(ThemePreference.defaultRaw, "dark")
        XCTAssertEqual(ThemePreference.mode("light"), .light)
        XCTAssertEqual(ThemePreference.mode("auto"), .system)
        XCTAssertEqual(ThemePreference.mode("dark"), .dark)
        XCTAssertEqual(ThemePreference.mode("anything-else"), .dark, "unknown stays dark")
        XCTAssertEqual(ThemePreference.colorScheme("light"), .light)
        XCTAssertNil(ThemePreference.colorScheme("auto"), "auto follows the system")
        XCTAssertEqual(ThemePreference.colorScheme("dark"), .dark)
        XCTAssertEqual(ThemePreference.colorScheme(""), .dark)
    }

    // setexp-36: the 75-word summary floor (iPad PolishEscrow, Mac AppSettings/BatchRunner).
    func testSummaryRuleThresholdAndWordCount() {
        XCTAssertEqual(SummaryRule.defaultMinWords, 75)
        XCTAssertEqual(SummaryRule.wordCount("  one two\nthree\tfour  "), 4)
        let short = Array(repeating: "w", count: 74).joined(separator: " ")
        let enough = Array(repeating: "w", count: 75).joined(separator: " ")
        XCTAssertFalse(SummaryRule.meetsThreshold(short))
        XCTAssertTrue(SummaryRule.meetsThreshold(enough))
        XCTAssertTrue(SummaryRule.meetsThreshold("a b", minWords: 0), "a 0 override keeps every summary")
    }

    // note-tags-04: tag library ranking (phone NotesRepository.allTags, Mac TagLibrary + properties).
    func testTagRankingMostUsedFirstTiesByKey() {
        let counts = TagRules.counts([["work", "idea"], ["idea"], ["zebra", "apple"], ["work"]])
        XCTAssertEqual(counts, ["work": 2, "idea": 2, "zebra": 1, "apple": 1])
        XCTAssertEqual(TagRules.mostUsedFirst(counts), ["idea", "work", "apple", "zebra"])
        XCTAssertEqual(TagRules.mostUsedFirst([:]), [])
    }

    // setexp-31: add a custom word (phone CustomWordsView, Mac SettingsView).
    func testAddingCustomWordTrimsAndRefusesDuplicates() {
        XCTAssertEqual(VocabularySyncCore.adding("  Skrift \n", to: ["Tuur"]), ["Tuur", "Skrift"])
        XCTAssertNil(VocabularySyncCore.adding("   ", to: ["Tuur"]), "empty adds nothing")
        XCTAssertNil(VocabularySyncCore.adding("tuur", to: ["Tuur"]), "case-insensitive duplicate")
        XCTAssertEqual(VocabularySyncCore.adding("x", to: []), ["x"])
    }

    // setexp-102: the names list order (phone store order, Mac Settings list).
    func testNamesSortByKeyNameCaseInsensitive() {
        let people = ["[[Zoe Adams]]", "[[bob Stone]]", "[[Alice Moore]]"].map {
            Person(canonical: $0, lastModifiedAt: "2026-01-01T00:00:00.000Z")
        }
        XCTAssertEqual(NamesMerge.sortPeople(people).map(\.canonical),
                       ["[[Alice Moore]]", "[[bob Stone]]", "[[Zoe Adams]]"])
    }

    // list-sidebar-89: soft delete, bringBack's inverse (phone repository, 5 Mac sites).
    func testSoftDeleteStampsDeleteAndPurgeClockTogether() {
        let m = memo(days: 10)
        WayOut.softDelete(m, now: now)
        XCTAssertEqual(m.deletedAt, now)
        XCTAssertEqual(m.trashSeenAt, now)
        XCTAssertEqual(MemoLifecycle.trashClockStart(m), now, "the purge clock runs at once")
        WayOut.bringBack(m, now: now)
        XCTAssertNil(m.deletedAt)
    }

    // FadingSweep (phone) vs MacFadingSweep: the one loop over sweepDue.
    func testSweepFadingMovesOnlyDueLiveNotes() {
        let due = memo(days: 61), fresh = memo(days: 5), alreadyGone = memo(days: 90, deletedDaysAgo: 1)
        var moved: [UUID] = []
        let n = MemoLifecycle.sweepFading(live: [due, fresh, alreadyGone], now: now) {
            moved.append($0.id)
            WayOut.softDelete($0, now: self.now)
        }
        XCTAssertEqual(n, 1)
        XCTAssertEqual(moved, [due.id])
        XCTAssertEqual(due.deletedAt, now)
        XCTAssertNil(fresh.deletedAt)
    }

    func testSweepFadingSparesABacklinkedNote() {
        let target = memo(days: 61)
        let linker = memo(days: 1, transcript: "see " + MemoLinkSyntax.link(id: target.id, title: "that"))
        var moved = 0
        MemoLifecycle.sweepFading(live: [target, linker], now: now) { _ in moved += 1 }
        XCTAssertEqual(moved, 0, "a note another note links to never fades")
        XCTAssertNil(target.deletedAt)
    }

    // books-102: the lenient metadata reader (was the Mac's own PhoneMetadata).
    func testLenientMetadataReadsPartialAndLegacyBlobs() {
        let partial = Data(#"{"location":{"placeName":"Lisbon"},"weather":{"conditions":"Sun","temperature":21.5},"dayPeriod":"morning","steps":12,"bookTitle":"B"}"#.utf8)
        let meta = MemoMetadata.lenient(from: partial)
        XCTAssertEqual(meta?.location?.placeName, "Lisbon")
        XCTAssertEqual(meta?.weather?.temperature, 21.5)
        XCTAssertEqual(meta?.dayPeriod, "morning")
        XCTAssertEqual(meta?.steps, 12)
        XCTAssertEqual(meta?.bookTitle, "B")
        XCTAssertNil(try? JSONDecoder().decode(MemoMetadata.self, from: partial), "the strict schema refuses it")
        XCTAssertNil(MemoMetadata.lenient(from: nil))
        XCTAssertNil(MemoMetadata.lenient(from: Data("not json".utf8)))
    }

    // capture-import-14: the picture-only body (phone share drainer, Mac drop).
    func testPictureOnlyBodyOneMarkerPerParagraph() {
        XCTAssertEqual(MixedBundle.pictureOnlyBody(count: 3), "[[img_001]]\n\n[[img_002]]\n\n[[img_003]]")
        XCTAssertEqual(MixedBundle.pictureOnlyBody(count: 1), "[[img_001]]")
        XCTAssertEqual(MixedBundle.pictureOnlyBody(count: 0), "")
    }
}
