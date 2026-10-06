import XCTest

/// Q330 / D184: the offer rule behind "New person…" in the Mac note's right-click menu
/// (`NewPersonFromName.selectionOffer`, shared with the phone's text menu).
final class NewPersonFromSelectionRuleTests: XCTestCase {

    private func person(_ canonical: String, aliases: [String]) -> Person {
        Person(canonical: canonical, aliases: aliases, short: nil,
               voiceEmbeddings: nil, lastModifiedAt: "2026-01-01T00:00:00.000Z")
    }

    func testPlainWordIsOfferedTrimmed() {
        let text = "I met Marloes today"
        let r = (text as NSString).range(of: " Marloes ")
        XCTAssertEqual(NewPersonFromName.selectionOffer(text: (text as NSString).substring(with: r),
                                                        selection: r, knownRanges: [], people: []),
                       "Marloes")
    }

    func testWhitespaceAndEmptyAreNotOffered() {
        XCTAssertNil(NewPersonFromName.selectionOffer(text: "  \n ", selection: NSRange(location: 0, length: 4),
                                                      knownRanges: [], people: []))
        XCTAssertNil(NewPersonFromName.selectionOffer(text: "", selection: NSRange(location: 2, length: 0),
                                                      knownRanges: [], people: []))
    }

    func testAlreadyLinkedNameIsNotOffered() {
        let text = "I met [[Marloes Vos|Marloes]] today"
        let link = Sanitiser.linkOccurrences(in: text).map(\.range)
        XCTAssertFalse(link.isEmpty)
        let sel = (text as NSString).range(of: "Marloes")
        XCTAssertNil(NewPersonFromName.selectionOffer(text: "Marloes", selection: sel,
                                                      knownRanges: link, people: []))
    }

    func testKnownPersonsAliasIsNotOffered() {
        let people = [person("[[Marloes Vos]]", aliases: ["Marloes"])]
        XCTAssertNil(NewPersonFromName.selectionOffer(text: "marloes", selection: NSRange(location: 0, length: 7),
                                                      knownRanges: [], people: people))
    }

    func testMultiLineOrAttachmentRunsAreNotOffered() {
        XCTAssertNil(NewPersonFromName.selectionOffer(text: "a\nb", selection: NSRange(location: 0, length: 3),
                                                      knownRanges: [], people: []))
        XCTAssertNil(NewPersonFromName.selectionOffer(text: "a\u{FFFC}", selection: NSRange(location: 0, length: 2),
                                                      knownRanges: [], people: []))
    }
}
