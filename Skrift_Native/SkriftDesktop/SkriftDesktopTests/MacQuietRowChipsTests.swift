import XCTest

/// Q107 (C115, D136, D135, C98; parity audit list-sidebar-67/69/71/75/79): the Mac's quiet
/// (unrated) rows follow the phone's `MemoCard.cardModel` — tags, place and weather chips, the
/// amber fading line only inside the 7-day window, no balls when locked, and the "2 versions"
/// pill. `MacQuietCard` is the builder the sidebar calls.
@MainActor
final class MacQuietRowChipsTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func daysAgo(_ n: Double) -> Date { now.addingTimeInterval(-n * 86_400) }

    private func enc<T: Encodable>(_ v: T) -> Data { (try? JSONEncoder().encode(v)) ?? Data() }

    private func memo(daysOld: Double, tags: [String] = [], metadata: MemoMetadata? = nil,
                      significance: Double = 0) -> Memo {
        Memo(audioFilename: "a.m4a", duration: 83, recordedAt: daysAgo(daysOld), tags: tags,
             title: "A note", transcript: "Some words", transcriptStatus: .done, significance: significance,
             metadataData: metadata.map { enc($0) })
    }

    private func card(_ m: Memo, conflicts: Set<UUID> = []) -> NoteCardModel {
        MacQuietCard.model(for: m, selected: false, backlinked: [], conflicts: conflicts, now: now)
    }

    // MARK: chips (list-sidebar-67, -69)

    func testQuietRowCarriesDurationPlaceWeatherAndTagChips() {
        let meta = MemoMetadata(location: LocationInfo(latitude: 38.7, longitude: -9.1, placeName: "Lisbon"),
                                weather: WeatherInfo(conditions: "Clear", temperature: 18, temperatureUnit: "C"))
        let m = card(memo(daysOld: 1, tags: ["daily", "harbour"], metadata: meta))
        XCTAssertEqual(m.chips.map(\.text), ["1:23", "Lisbon", "18°", "#daily", "#harbour"])
        XCTAssertEqual(m.chips.filter(\.isTag).map(\.text), ["#daily", "#harbour"])
        XCTAssertTrue(m.quiet)
    }

    func testQuietRowChipsEqualThePhoneCardsChips() {
        // The phone builds the same chips from the same shared builder.
        let meta = MemoMetadata(location: LocationInfo(latitude: 0, longitude: 0, placeName: "Porto"))
        let note = memo(daysOld: 1, tags: ["x"], metadata: meta)
        XCTAssertEqual(card(note).chips, NoteCardBuilder.content(for: note.cardFacts()).chips)
    }

    // MARK: the fading line (list-sidebar-75, D136)

    func testNoStandingSpineLineOnACalmQuietRow() {
        let m = card(memo(daysOld: 10))
        XCTAssertNil(m.fadingLine, "10 days old: 20 days left, nothing to warn about")
        XCTAssertNil(m.quietLine, "the faint spine line on every quiet row is gone")
    }

    func testAmberLineAppearsOnlyInsideTheSevenDayWindow() {
        // Fades at day 30: day 22 is the first day inside the window.
        XCTAssertNil(card(memo(daysOld: 21)).fadingLine)
        XCTAssertNotNil(card(memo(daysOld: 23)).fadingLine)
        XCTAssertNotNil(card(memo(daysOld: 29)).fadingLine)
    }

    func testMacLineIsTheSameStringThePhoneShows() {
        let note = memo(daysOld: 25)
        XCTAssertEqual(card(note).fadingLine, MemoSpine.rowClockLine(for: note, backlinked: [], now: now))
        XCTAssertTrue(card(note).fadingLine?.hasPrefix("starts fading") == true)
    }

    func testAFadingNoteShowsItsDeleteDate() {
        XCTAssertTrue(card(memo(daysOld: 40)).fadingLine?.hasPrefix("moves to Recently Deleted") == true)
    }

    // MARK: balls (list-sidebar-71)

    func testUnratedQuietRowShowsThreeHollowBalls() {
        XCTAssertEqual(card(memo(daysOld: 1)).balls, 0)
    }

    func testLockedRowsCarryNoBallsQuietOrRated() {
        let quiet = memo(daysOld: 1)
        quiet.locked = true
        XCTAssertNil(card(quiet).balls)
        XCTAssertTrue(card(quiet).locked)
        // The rated Mac row's locked card (the other half of the parity) drops them too.
        XCTAssertNil(LockedRow.card(stamp: "x", title: "t", selected: false, quiet: false).balls)
    }

    func testLockedRowShowsNoChipsAndNoLine() {
        let m = memo(daysOld: 25, tags: ["secret"])
        m.locked = true
        let c = card(m)
        XCTAssertTrue(c.chips.isEmpty)
        XCTAssertNil(c.fadingLine)
        XCTAssertNil(c.snippet)
    }

    // MARK: the 2-versions pill (list-sidebar-79, C98)

    func testQuietRowWithTwoVersionsWearsThePill() {
        let m = memo(daysOld: 1)
        XCTAssertNil(card(m).statusPill)
        XCTAssertEqual(card(m, conflicts: [m.id]).statusPill, .twoVersions)
    }

    func testLockedQuietRowAlsoWearsThePill() {
        let m = memo(daysOld: 1)
        m.locked = true
        XCTAssertEqual(card(m, conflicts: [m.id]).statusPill, .twoVersions)
    }

    func testPillReadsTheLiveWatchByDefault() {
        let m = memo(daysOld: 1)
        EditConflictWatch.shared.set([m.id])
        defer { EditConflictWatch.shared.set([]) }
        XCTAssertEqual(MacQuietCard.model(for: m, selected: false, backlinked: [], conflicts: EditConflictWatch.shared.ids).statusPill, .twoVersions)
    }

    // MARK: a stranded rated memo keeps its honest waiting line and its own balls

    func testStrandedRatedMemoKeepsWaitingLine() {
        let m = memo(daysOld: 1, significance: 0.6)
        let c = card(m)
        XCTAssertEqual(c.quietLine, WayOutRules.strandedLine(for: m))
        XCTAssertEqual(c.balls, ThreeBallScale.step(for: 0.6))
        XCTAssertNil(c.fadingLine, "a rated note is not on the fade clock")
    }
}
