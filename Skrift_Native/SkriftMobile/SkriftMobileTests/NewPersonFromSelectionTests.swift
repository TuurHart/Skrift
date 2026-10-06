import XCTest
import UIKit
@testable import SkriftMobile

/// Q330 / D184: long-pressing or selecting a word the app does not know offers "New person…" in the
/// note's text menu, prefilled with the trimmed selection; never for blank runs or names the note
/// already shows.
final class NewPersonFromSelectionTests: XCTestCase {

    private var window: UIWindow!

    @MainActor
    private func makeEditor(transcript: String) -> (NoteBodyView.Coordinator, NoteBodyTextView) {
        let memo = Memo(audioFilename: "m.m4a", transcript: transcript)
        let coordinator = NoteBodyView.Coordinator(memo: memo, onCommit: { _ in })
        let tv = NoteBodyTextView()
        tv.installAccessoryHosts()
        window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 800))
        window.addSubview(tv)
        window.makeKeyAndVisible()
        tv.frame = window.bounds
        coordinator.textView = tv
        coordinator.load(force: true)
        tv.layoutIfNeeded()
        return (coordinator, tv)
    }

    private func titles(_ menu: UIMenu?) -> [String] {
        (menu?.children ?? []).compactMap { ($0 as? UIAction)?.title }
    }

    @MainActor
    func testMenuOffersNewPersonForAPlainWord() {
        let text = "I met Zephyrine today"
        let (c, tv) = makeEditor(transcript: text)
        let r = (text as NSString).range(of: "Zephyrine")
        let menu = c.textView(tv, editMenuForTextIn: r, suggestedActions: [])
        XCTAssertEqual(titles(menu), [NameActionLabel.newPerson])
        XCTAssertEqual(NameActionLabel.newPerson, "New person…")
    }

    @MainActor
    func testMenuKeepsTheSystemActionsAfterOurs() {
        let text = "I met Zephyrine today"
        let (c, tv) = makeEditor(transcript: text)
        let r = (text as NSString).range(of: "Zephyrine")
        let copy = UIAction(title: "Copy") { _ in }
        let menu = c.textView(tv, editMenuForTextIn: r, suggestedActions: [copy])
        XCTAssertEqual(titles(menu), [NameActionLabel.newPerson, "Copy"])
    }

    @MainActor
    func testNoOfferForAnEmptyOrWhitespaceSelection() {
        let text = "I met   Zephyrine today"
        let (c, tv) = makeEditor(transcript: text)
        XCTAssertNil(c.textView(tv, editMenuForTextIn: NSRange(location: 3, length: 0), suggestedActions: []))
        let gap = (text as NSString).range(of: "   ")
        XCTAssertNil(c.textView(tv, editMenuForTextIn: gap, suggestedActions: []))
    }

    @MainActor
    func testNoOfferForAnAlreadyLinkedName() {
        let text = "I met Zephyrine today"
        let (c, tv) = makeEditor(transcript: text)
        let r = (text as NSString).range(of: "Zephyrine")
        let span = NameSpan(offset: r.location, length: r.length, alias: "Zephyrine", tier: .linked,
                            canonical: "[[Zephyrine Quill]]", candidates: [])
        c.updateSpans([span])
        XCTAssertNil(c.textView(tv, editMenuForTextIn: r, suggestedActions: []),
                     "a linked name has its own tap flow; the default menu stays")
        // A selection that merely touches the linked word is hidden too.
        let touching = NSRange(location: r.location + 4, length: 6)
        XCTAssertNil(c.textView(tv, editMenuForTextIn: touching, suggestedActions: []))
        // A neighbouring plain word is still offered.
        let other = (text as NSString).range(of: "today")
        XCTAssertNotNil(c.textView(tv, editMenuForTextIn: other, suggestedActions: []))
    }

    @MainActor
    func testChoosingTheItemHandsTheTrimmedSelectionToTheEditor() throws {
        let text = "I met Zephyrine today"
        let (c, tv) = makeEditor(transcript: text)
        var received: String?
        c.onNewPersonFromSelection = { received = $0 }
        let padded = NSRange(location: 5, length: 11)           // " Zephyrine "
        XCTAssertEqual((text as NSString).substring(with: padded), " Zephyrine ")
        let menu = try XCTUnwrap(c.textView(tv, editMenuForTextIn: padded, suggestedActions: []))
        let action = try XCTUnwrap(menu.children.first as? UIAction)
        action.performWithSender(nil, target: nil)
        XCTAssertEqual(received, "Zephyrine")
        let made = try XCTUnwrap(PersonEditCore.materialise(
            fullName: try XCTUnwrap(received), aliases: [try XCTUnwrap(received)], short: "", original: nil))
        XCTAssertEqual(made.person.canonical, NamesMerge.normaliseCanonical("Zephyrine"))
        XCTAssertEqual(made.person.aliases, ["Zephyrine"])
    }

    // MARK: the shared rule (pure)

    func testSelectionOfferRule() {
        let none: [NSRange] = []
        XCTAssertEqual(NewPersonFromName.selectionOffer(text: "  Marloes ", selection: NSRange(location: 0, length: 10),
                                                        knownRanges: none, people: []), "Marloes")
        XCTAssertNil(NewPersonFromName.selectionOffer(text: "   ", selection: NSRange(location: 0, length: 3),
                                                      knownRanges: none, people: []))
        XCTAssertNil(NewPersonFromName.selectionOffer(text: "two\nlines", selection: NSRange(location: 0, length: 9),
                                                      knownRanges: none, people: []))
        XCTAssertNil(NewPersonFromName.selectionOffer(text: "a\u{FFFC}b", selection: NSRange(location: 0, length: 3),
                                                      knownRanges: none, people: []))
        let known = Person(canonical: "[[Marloes Vos]]", aliases: ["Marloes"], lastModifiedAt: "2026-01-01T00:00:00Z")
        XCTAssertNil(NewPersonFromName.selectionOffer(text: "marloes", selection: NSRange(location: 0, length: 7),
                                                      knownRanges: none, people: [known]),
                     "an existing person's alias is not a new person")
    }
}
