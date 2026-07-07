import PDFKit
import QuickLook
import SwiftUI
import UIKit
import XCTest
@testable import SkriftMobile

/// Tests for the re-founded note body (NoteBodyView): the marker round-trip and
/// debounced write-back, caret carry across external rebuilds, the mode
/// precedence the old TranscriptBodyView swap-tested, and the karaoke word map.
final class NoteBodyTests: XCTestCase {

    @MainActor
    private func makeEditor(transcript: String) -> (NoteBodyView.Coordinator, NoteBodyTextView) {
        let memo = Memo(audioFilename: "memo_edit.m4a", transcript: transcript)
        let coordinator = NoteBodyView.Coordinator(memo: memo, onCommit: {})
        let tv = NoteBodyTextView()
        tv.installAccessoryHosts()
        coordinator.textView = tv
        coordinator.load(force: true)
        return (coordinator, tv)
    }

    // MARK: external rebuilds carry the caret

    @MainActor
    func testRebuildPreservesCaretPosition() {
        let (coordinator, tv) = makeEditor(transcript: "one two three four five")
        tv.selectedRange = NSRange(location: 8, length: 0)
        coordinator.memo.transcript = "one two three four five six"   // changed under us
        coordinator.load(force: false)
        XCTAssertEqual(tv.text, "one two three four five six")        // rebuilt
        XCTAssertEqual(tv.selectedRange, NSRange(location: 8, length: 0))
    }

    @MainActor
    func testRebuildClampsCaretWhenTextShrinks() {
        let (coordinator, tv) = makeEditor(transcript: "a long transcript body")
        tv.selectedRange = NSRange(location: 20, length: 0)
        coordinator.memo.transcript = "tiny"
        coordinator.load(force: false)
        XCTAssertEqual(tv.text, "tiny")
        XCTAssertEqual(tv.selectedRange, NSRange(location: 4, length: 0))
    }

    // MARK: debounced write-back

    @MainActor
    func testCommitDraftWritesBackAndFlagsUserEdited() {
        let (coordinator, tv) = makeEditor(transcript: "hello world")
        tv.attributedText = NSAttributedString(string: "hello brave world")
        coordinator.textViewDidChange(tv)          // marks the draft dirty + schedules
        XCTAssertEqual(coordinator.memo.transcript, "hello world",
                       "the draft must NOT hit the model per keystroke")
        coordinator.commitDraft()                  // debounce fired / end-editing
        XCTAssertEqual(coordinator.memo.transcript, "hello brave world")
        XCTAssertTrue(coordinator.memo.transcriptUserEdited)
        XCTAssertEqual(coordinator.memo.transcriptStatus, .done)
    }

    @MainActor
    func testCommitDraftIsNoOpWhenClean() {
        let (coordinator, _) = makeEditor(transcript: "hello world")
        coordinator.memo.transcriptUserEdited = false
        coordinator.commitDraft()                  // nothing typed
        XCTAssertFalse(coordinator.memo.transcriptUserEdited)
        XCTAssertEqual(coordinator.memo.transcript, "hello world")
    }

    @MainActor
    func testClearingBodyCommitsNilTranscript() {
        let (coordinator, tv) = makeEditor(transcript: "hello world")
        tv.attributedText = NSAttributedString(string: "   ")
        coordinator.textViewDidChange(tv)
        coordinator.commitDraft()
        XCTAssertNil(coordinator.memo.transcript)
    }

    // MARK: quote-protected captures

    @MainActor
    func testCaptureCommitReprependsQuoteVerbatim() {
        let c1 = "> To live is to suffer.\n\nMy ramble about it."
        var meta = MemoMetadata()
        meta.bookTitle = "A Book"
        meta.bookAuthor = "Somebody"
        let memo = Memo.make(transcript: c1, metadata: meta)   // captureQuote is C2-gated
        XCTAssertNotNil(memo.captureQuote, "fixture must parse as a capture")
        let coordinator = NoteBodyView.Coordinator(memo: memo, onCommit: {})
        let tv = NoteBodyTextView()
        tv.installAccessoryHosts()
        coordinator.textView = tv
        coordinator.load(force: true)
        XCTAssertFalse(tv.text.contains(">"), "editor must hold only the ramble")

        tv.attributedText = NSAttributedString(string: "My EDITED ramble.")
        coordinator.textViewDidChange(tv)
        coordinator.commitDraft()
        XCTAssertTrue(coordinator.memo.transcript?.hasPrefix("> To live is to suffer.") == true,
                      "the stored quote block must be untouchable")
        XCTAssertTrue(coordinator.memo.transcript?.contains("My EDITED ramble.") == true)
    }

    // MARK: marker round-trip

    @MainActor
    func testImageMarkersRoundTripThroughAttributedText() {
        let (coordinator, tv) = makeEditor(transcript: "before [[img_001]] after")
        XCTAssertEqual(coordinator.reconstruct(tv.attributedText), "before [[img_001]] after")
    }

    // MARK: mode precedence (ported from the TranscriptBodyView swap)

    func testModePrecedence() {
        XCTAssertEqual(NoteBody.mode(isPlaying: true, status: .transcribing), .playing,
                       "playback wins over the in-flight guard")
        XCTAssertEqual(NoteBody.mode(isPlaying: true, status: .done), .playing)
        XCTAssertEqual(NoteBody.mode(isPlaying: false, status: .transcribing), .reading,
                       "an in-flight transcription is read-only")
        XCTAssertEqual(NoteBody.mode(isPlaying: false, status: .done), .editing)
        XCTAssertEqual(NoteBody.mode(isPlaying: false, status: .failed), .editing)
    }
}

/// The raw⇄display transform (chunk 4 — live checklists join the image markers).
final class BodyTransformTests: XCTestCase {

    func testPiecesSplitTextImagesAndTasks() {
        let raw = "intro [[img_001]]\n- [ ] buy milk\n- [x] done\ntail"
        let pieces = BodyTransform.pieces(of: raw)
        let kinds: [BodyTransform.Segment] = pieces.map(\.segment)
        XCTAssertEqual(kinds, [
            .text("intro "), .image(1), .text("\n"),
            .task(checked: false), .text(" buy milk\n"),
            .task(checked: true), .text(" done\ntail"),
        ])
    }

    func testTaskRequiresLineStart() {
        let pieces = BodyTransform.pieces(of: "mention - [ ] mid-line")
        XCTAssertEqual(pieces.count, 1, "a mid-line '- [ ]' is prose, not a task")
    }

    func testIndentStaysText() {
        let pieces = BodyTransform.pieces(of: "  - [X] indented")
        XCTAssertEqual(pieces.map(\.segment),
                       [.text("  "), .task(checked: true), .text(" indented")])
    }

    func testDisplayRangeAccountsForTasksAndImages() {
        // raw: "- [ ] see [[img_001]] Jack" — span over "Jack" (raw 22..26)
        let raw = "- [ ] see [[img_001]] Jack"
        let jack = (raw as NSString).range(of: "Jack")
        let display = BodyTransform.displayRange(forRaw: jack, in: raw)
        // task "- [ ]" (5→1) saves 4; the mid-line img becomes a display BLOCK
        // (\n + glyph + \n, 11→3) saving 8 → display loc = 22-12
        XCTAssertEqual(display, NSRange(location: jack.location - 12, length: 4))
    }

    func testImageBreaksMakeMidSentencePhotosBlocks() {
        func breaks(_ raw: String) -> (Bool, Bool) {
            let piece = BodyTransform.pieces(of: raw).first {
                if case .image = $0.segment { return true }; return false
            }!
            return BodyTransform.imageBreaks(for: piece, in: raw)
        }
        XCTAssertTrue(breaks("was fantastic [[img_001]] and then") == (true, true),
                      "mid-sentence photo needs both breaks")
        XCTAssertTrue(breaks("look\n[[img_001]]\nafter") == (false, false),
                      "a photo already on its own line needs none")
        XCTAssertTrue(breaks("[[img_001]] tail") == (false, true))
        XCTAssertTrue(breaks("head [[img_001]]") == (true, false))
    }

    @MainActor
    func testChecklistRoundTripsThroughTheEditor() {
        let raw = "- [ ] buy milk\n- [x] call Jack"
        let memo = Memo(audioFilename: "memo_t.m4a", transcript: raw)
        let coordinator = NoteBodyView.Coordinator(memo: memo, onCommit: {})
        let tv = NoteBodyTextView()
        tv.installAccessoryHosts()
        coordinator.textView = tv
        coordinator.load(force: true)
        XCTAssertEqual(coordinator.reconstruct(tv.attributedText), raw, "byte-exact round trip")
        XCTAssertEqual(tv.text.filter { $0 == "\u{FFFC}" }.count, 2, "both prefixes are checkbox glyphs")
    }

    @MainActor
    func testToggleFlipsTheRawSyntax() {
        let memo = Memo(audioFilename: "memo_t2.m4a", transcript: "- [ ] buy milk")
        let coordinator = NoteBodyView.Coordinator(memo: memo, onCommit: {})
        let tv = NoteBodyTextView()
        tv.installAccessoryHosts()
        coordinator.textView = tv
        coordinator.load(force: true)
        coordinator.toggleTask(at: 0)
        XCTAssertEqual(memo.transcript, "- [x] buy milk")
        XCTAssertTrue(memo.transcriptUserEdited)
        coordinator.toggleTask(at: 0)
        XCTAssertEqual(memo.transcript, "- [ ] buy milk")
    }
}

/// Memo↔memo link syntax + editor round-trip (chunk 5).
final class MemoLinkTests: XCTestCase {

    private let idA = UUID(uuidString: "AAAAAAAA-1111-2222-3333-444444444444")!

    func testLinkBuildsSafeSyntax() {
        XCTAssertEqual(MemoLinkSyntax.link(id: idA, title: "Trip | notes [[x]]"),
                       "[[memo:\(idA.uuidString)|Trip   notes x]]")
        XCTAssertEqual(MemoLinkSyntax.link(id: idA, title: "  "),
                       "[[memo:\(idA.uuidString)|Untitled]]")
    }

    func testOccurrencesAndTargets() {
        let text = "See [[memo:\(idA.uuidString)|Harbor]] and plain [[Hotel]]."
        let occs = MemoLinkSyntax.occurrences(in: text)
        XCTAssertEqual(occs.count, 1)
        XCTAssertEqual(occs.first?.id, idA)
        XCTAssertEqual(occs.first?.title, "Harbor")
        XCTAssertEqual(MemoLinkSyntax.targets(in: text), [idA])
    }

    func testExportRewriteFallbackAndPrecise() {
        let text = "See [[memo:\(idA.uuidString)|Harbor]]."
        XCTAssertEqual(MemoLinkSyntax.exportRewrite(text), "See [[Harbor]].")
        XCTAssertEqual(MemoLinkSyntax.exportRewrite(text, resolveStem: { _ in "Harbor walk-AAAAAAAA" }),
                       "See [[Harbor walk-AAAAAAAA|Harbor]].")
        XCTAssertEqual(MemoLinkSyntax.exportRewrite("no links"), "no links")
    }

    func testCompilerEmitsWikilinkNotRawSyntax() {
        let input = CompilerInput(filename: "m.m4a",
                                  transcript: "Body with [[memo:\(idA.uuidString)|Harbor]].",
                                  enhancedTitle: "T")
        let md = Compiler.compile(input, author: "A")
        XCTAssertFalse(md.contains("[[memo:"), "raw memo-link syntax must never reach the vault")
        XCTAssertTrue(md.contains("[[Harbor]]"))
    }

    @MainActor
    func testMemoLinkRoundTripsThroughTheEditor() {
        let raw = "Start [[memo:\(idA.uuidString)|Harbor]] end"
        let memo = Memo(audioFilename: "memo_l.m4a", transcript: raw)
        let coordinator = NoteBodyView.Coordinator(memo: memo, onCommit: {})
        let tv = NoteBodyTextView()
        tv.installAccessoryHosts()
        coordinator.textView = tv
        coordinator.load(force: true)
        XCTAssertEqual(tv.text.filter { $0 == "\u{FFFC}" }.count, 1, "the link renders as one chip")
        XCTAssertEqual(coordinator.reconstruct(tv.attributedText), raw, "byte-exact round trip")
    }

    func testEscrowStripsAndReattachRestores() {
        let raw = "See [[memo:\(idA.uuidString)|Harbor walk]] for detail."
        let (stripped, links) = MemoLinkSyntax.escrowForEditing(raw)
        XCTAssertEqual(stripped, "See Harbor walk for detail.", "the LLM reads natural prose")
        XCTAssertEqual(links.count, 1)
        // A benign copy-edit that recases the title still reattaches (surface kept).
        let edited = "See harbor walk for the detail."
        XCTAssertEqual(MemoLinkSyntax.reattach(edited: edited, links: links),
                       "See [[memo:\(idA.uuidString)|harbor walk]] for the detail.")
    }

    func testReattachFailsWhenTheTitleWasEditedAway() {
        let raw = "See [[memo:\(idA.uuidString)|Harbor walk]]."
        let (_, links) = MemoLinkSyntax.escrowForEditing(raw)
        XCTAssertNil(MemoLinkSyntax.reattach(edited: "See the waterfront stroll.", links: links),
                     "a lost title must force the caller's fallback to the unedited body")
    }

    func testSanitiserNeverLinksInsideALinkTitle() {
        // "Hendri" is a distinctive, auto-linkable name — but INSIDE a memo-link
        // title it must stay untouched (nested [[…]] would corrupt the syntax).
        let hendri = Person(canonical: "[[Hendri van Niekerk]]",
                            aliases: ["Hendri van Niekerk", "Hendri"], short: "Hendri",
                            lastModifiedAt: "2026-07-07T00:00:00.000Z")
        let raw = "Talked to Hendri about [[memo:\(idA.uuidString)|Lunch with Hendri]]."
        let out = Sanitiser.process(text: raw, people: [hendri]).sanitised
        XCTAssertTrue(out.contains("[[memo:\(idA.uuidString)|Lunch with Hendri]]"),
                      "the link title must survive byte-exact — got: \(out)")
        XCTAssertTrue(out.contains("[[Hendri van Niekerk"),
                      "the prose mention outside the link still auto-links — got: \(out)")
    }

    @MainActor
    func testInsertMemoLinkReplacesTheTypedTrigger() {
        let memo = Memo(audioFilename: "memo_l2.m4a", transcript: "Hello ")
        let coordinator = NoteBodyView.Coordinator(memo: memo, onCommit: {})
        let tv = NoteBodyTextView()
        tv.installAccessoryHosts()
        coordinator.textView = tv
        coordinator.load(force: true)
        // Simulate typing "[[" at the end (the trigger the picker replaces).
        tv.textStorage.append(NSAttributedString(string: "[["))
        tv.selectedRange = NSRange(location: tv.textStorage.length, length: 0)
        coordinator.textViewDidChange(tv)      // detects the trigger
        coordinator.insertMemoLink(id: idA, title: "Harbor")
        XCTAssertEqual(memo.transcript, "Hello [[memo:\(idA.uuidString)|Harbor]] ")
    }
}

/// Doc scan (chunk 9): PDF rendering + the capture-memo construction contract.
final class DocScannerTests: XCTestCase {

    private func page(text: String) -> UIImage {
        let size = CGSize(width: 600, height: 800)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            (text as NSString).draw(at: CGPoint(x: 40, y: 80),
                                    withAttributes: [.font: UIFont.boldSystemFont(ofSize: 44),
                                                     .foregroundColor: UIColor.black])
        }
    }

    func testRenderPDFHoldsEveryPage() throws {
        let data = try XCTUnwrap(DocScanner.renderPDF(pages: [page(text: "ONE"), page(text: "TWO")]))
        let doc = try XCTUnwrap(PDFDocument(data: data))
        XCTAssertEqual(doc.pageCount, 2)
        XCTAssertNil(DocScanner.renderPDF(pages: []))
    }

    func testRecognizeTextReadsThePages() async {
        let text = await DocScanner.recognizeText(pages: [page(text: "INVOICE 7788")])
        XCTAssertTrue(text.uppercased().contains("INVOICE"), "got: '\(text)'")
    }

    func testScanMemoIsASearchableFileCapture() {
        // The construction contract the scanner mirrors from the share drainer.
        let sc = SharedContent(type: .file, text: "INVOICE 7788",
                               filePath: "file_X.pdf", fileName: "Scan.pdf",
                               mimeType: "application/pdf")
        let memo = Memo.make(audioFilename: "", transcript: nil, sharedContent: sc)
        XCTAssertTrue(memo.isShareCapture, "empty audioFilename + sharedContent = capture")
        XCTAssertTrue(memo.matches(query: "invoice"), "the OCR text is searchable")
    }
}

/// Locked notes (chunk 8): the session gate's logic with an injected authenticator.
final class LockGateTests: XCTestCase {

    @MainActor
    func testGateBlocksUntilUnlockedAndRelocksAll() async {
        let gate = LockGate.shared
        gate.relockAll()
        gate.authenticate = { _ in true }          // user passes Face ID
        let memo = Memo(title: "Secret", transcript: "hidden")
        memo.locked = true
        XCTAssertTrue(gate.isLocked(memo))
        let ok = await gate.unlock(memo.id)
        XCTAssertTrue(ok)
        XCTAssertFalse(gate.isLocked(memo), "session unlock opens the content")
        gate.relockAll()                            // backgrounding
        XCTAssertTrue(gate.isLocked(memo))
    }

    @MainActor
    func testFailedAuthKeepsTheGateShut() async {
        let gate = LockGate.shared
        gate.relockAll()
        gate.authenticate = { _ in false }         // user cancels / fails
        let memo = Memo(title: "Secret", transcript: "hidden")
        memo.locked = true
        let ok = await gate.unlock(memo.id)
        XCTAssertFalse(ok)
        XCTAssertTrue(gate.isLocked(memo))
    }

    @MainActor
    func testUnlockedFlagNeverGates() {
        let memo = Memo(title: "Open", transcript: "visible")
        XCTAssertFalse(LockGate.shared.isLocked(memo))
    }
}

/// Reminders (chunk 7): the pure reconcile plan + preset date math.
final class ReminderPlanTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let idA = UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000001")!
    private let idB = UUID(uuidString: "BBBBBBBB-0000-0000-0000-000000000002")!

    func testDesiredSchedulesOnlyFutureLiveReminders() {
        let desired = ReminderPlan.desired(memos: [
            (id: idA, remindAt: now.addingTimeInterval(3600), deleted: false),   // future ✓
            (id: idB, remindAt: now.addingTimeInterval(-60), deleted: false),    // past → inert
            (id: UUID(), remindAt: now.addingTimeInterval(3600), deleted: true), // trashed → silent
            (id: UUID(), remindAt: nil, deleted: false),                         // none
        ], now: now)
        XCTAssertEqual(desired.map(\.memoID), [idA])
    }

    func testDiffAddsRemovesAndReschedules() {
        let at = now.addingTimeInterval(3600)
        let moved = now.addingTimeInterval(7200)
        let desired = [ReminderPlan.Entry(memoID: idA, fireAt: moved),
                       ReminderPlan.Entry(memoID: idB, fireAt: at)]
        let pending: [(id: String, fireAt: Date?)] = [
            (id: ReminderPlan.idPrefix + idA.uuidString, fireAt: at),            // date moved → replace
            (id: ReminderPlan.idPrefix + UUID().uuidString, fireAt: at),         // cleared → remove
            (id: "unrelated-notification", fireAt: nil),                         // not ours → untouched
        ]
        let (add, remove) = ReminderPlan.diff(desired: desired, pending: pending)
        XCTAssertEqual(Set(add.map(\.memoID)), [idA, idB], "moved reschedules, new schedules")
        XCTAssertEqual(remove.count, 2)
        XCTAssertFalse(remove.contains("unrelated-notification"))
    }

    func testDiffLeavesUnchangedAlone() {
        let at = now.addingTimeInterval(3600)
        let desired = [ReminderPlan.Entry(memoID: idA, fireAt: at)]
        let (add, remove) = ReminderPlan.diff(
            desired: desired,
            pending: [(id: ReminderPlan.idPrefix + idA.uuidString, fireAt: at)])
        XCTAssertTrue(add.isEmpty)
        XCTAssertTrue(remove.isEmpty)
    }

    func testPresets() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Lisbon")!
        let morning = cal.date(from: DateComponents(year: 2026, month: 7, day: 7, hour: 10))!
        let evening = ReminderPresets.thisEvening(from: morning, calendar: cal)
        XCTAssertEqual(cal.component(.hour, from: evening!), 18)
        let night = cal.date(from: DateComponents(year: 2026, month: 7, day: 7, hour: 21))!
        XCTAssertNil(ReminderPresets.thisEvening(from: night, calendar: cal), "18:00 already past")
        let tomorrow = ReminderPresets.tomorrowMorning(from: night, calendar: cal)!
        XCTAssertEqual(cal.component(.day, from: tomorrow), 8)
        XCTAssertEqual(cal.component(.hour, from: tomorrow), 9)
        let week = ReminderPresets.nextWeek(from: morning, calendar: cal)!
        XCTAssertEqual(cal.component(.day, from: week), 14)
    }
}

/// Photo OCR (chunk 6): the synced manifest field + the search matcher + a
/// real Vision pass over a rendered fixture.
final class PhotoTextTests: XCTestCase {

    func testManifestTextFieldIsAdditive() throws {
        // Old payloads (no `text`) decode to nil = "not indexed yet".
        let legacy = #"{"filename":"photo_x_001.jpg","offsetSeconds":2.5}"#.data(using: .utf8)!
        let entry = try JSONDecoder().decode(ImageManifestEntry.self, from: legacy)
        XCTAssertNil(entry.text)
        // Round-trips once set.
        var indexed = entry
        indexed.text = "HARBOR 42"
        let back = try JSONDecoder().decode(ImageManifestEntry.self,
                                            from: JSONEncoder().encode(indexed))
        XCTAssertEqual(back.text, "HARBOR 42")
    }

    func testSearchMatchesPhotoTextAndTitle() {
        var meta = MemoMetadata()
        meta.imageManifest = [ImageManifestEntry(filename: "p.jpg", offsetSeconds: 0, text: "Flight BA-2490 gate 14")]
        let memo = Memo.make(transcript: "spoken words only", metadata: meta)
        memo.title = "Airport dash"
        XCTAssertTrue(memo.matches(query: "ba-2490"), "OCR text must be searchable")
        XCTAssertTrue(memo.matches(query: "airport"), "the TITLE must be searchable (was a gap)")
        XCTAssertTrue(memo.matches(query: "spoken"))
        XCTAssertFalse(memo.matches(query: "zeppelin"))
        XCTAssertTrue(memo.matches(query: "  "), "blank query matches everything")
    }

    @MainActor
    func testVisionRecognizesRenderedText() async {
        // Render an unambiguous fixture and run the REAL recognizer.
        let size = CGSize(width: 600, height: 200)
        let image = UIGraphicsImageRenderer(size: size).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            ("SKRIFT HARBOR 42" as NSString).draw(
                at: CGPoint(x: 40, y: 70),
                withAttributes: [.font: UIFont.boldSystemFont(ofSize: 48),
                                 .foregroundColor: UIColor.black])
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ocr-fixture-\(UUID().uuidString).jpg")
        try? image.jpegData(compressionQuality: 0.9)?.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let text = await PhotoTextIndexer.recognize(at: url)
        XCTAssertTrue(text.uppercased().contains("HARBOR"),
                      "Vision should read the rendered fixture — got: '\(text)'")
    }

    func testRecognizeMissingFileReturnsEmpty() async {
        let text = await PhotoTextIndexer.recognize(
            at: URL(fileURLWithPath: "/nonexistent/photo.jpg"))
        XCTAssertEqual(text, "")
    }
}

/// P1#1 churn guards (device round 1, build 31 — "selection handles follow
/// the viewport"): an unchanged span set must NOT re-run the full attribute
/// rewrite (SwiftUI re-evals storm during interactive keyboard dismiss), and
/// a styling pass must never move a live selection.
final class TierStylingChurnTests: XCTestCase {

    @MainActor
    private func makeEditor(transcript: String) -> (NoteBodyView.Coordinator, NoteBodyTextView) {
        let memo = Memo(audioFilename: "memo_churn.m4a", transcript: transcript)
        let coordinator = NoteBodyView.Coordinator(memo: memo, onCommit: {})
        let tv = NoteBodyTextView()
        tv.installAccessoryHosts()
        coordinator.textView = tv
        coordinator.load(force: true)
        return (coordinator, tv)
    }

    private func underlinePresent(_ tv: UITextView, at location: Int) -> Bool {
        tv.textStorage.attribute(.underlineStyle, at: location, effectiveRange: nil) != nil
    }

    @MainActor
    func testUnchangedSpansSkipTheRestyle() {
        let (coordinator, tv) = makeEditor(transcript: "hello Jack world")
        let jack = NameSpan(offset: 6, length: 4, alias: "Jack", tier: .suggested,
                            canonical: "Jack Sparrow", candidates: [])
        coordinator.updateSpans([jack])
        XCTAssertTrue(underlinePresent(tv, at: 7), "first pass must style the span")

        // Strip the styling by hand; an UNCHANGED span set must not repaint it
        // (the skip is the fix — restyling per SwiftUI re-eval reflowed the
        // text under live selection handles).
        tv.textStorage.removeAttribute(.underlineStyle,
                                       range: NSRange(location: 0, length: tv.textStorage.length))
        coordinator.updateSpans([jack])
        XCTAssertFalse(underlinePresent(tv, at: 7), "unchanged spans must skip the rewrite")

        // A REAL change must still restyle.
        var linked = jack
        linked.tier = .linked
        coordinator.updateSpans([linked])
        let color = tv.textStorage.attribute(.foregroundColor, at: 7, effectiveRange: nil) as? UIColor
        XCTAssertEqual(color, UIColor(Color.skNameLinked), "a changed tier must repaint")
    }

    @MainActor
    func testRestyleKeepsALiveSelection() {
        let (coordinator, tv) = makeEditor(transcript: "hello Jack world")
        tv.selectedRange = NSRange(location: 6, length: 4)      // "Jack" selected
        coordinator.updateSpans([NameSpan(offset: 6, length: 4, alias: "Jack", tier: .ambiguous,
                                          canonical: nil, candidates: [])])
        XCTAssertEqual(tv.selectedRange, NSRange(location: 6, length: 4),
                       "styling must never move a live selection")
    }
}

/// Attachment tap resolution (device round 1, build 31): a tap in the empty
/// space beside a PORTRAIT photo must NOT open the viewer (P1#2 — the caret-
/// adjacency probe was too greedy), and a checkbox tap must toggle even when
/// the caret snaps past the glyph (P1#6 — probe too tight). The resolver is
/// anchored on the touched character and gated on the glyph's drawn rect.
final class AttachmentHitTests: XCTestCase {

    private var window: UIWindow!

    @MainActor
    private func makeLaidOutEditor(memo: Memo) -> (NoteBodyView.Coordinator, NoteBodyTextView) {
        let coordinator = NoteBodyView.Coordinator(memo: memo, onCommit: {})
        let tv = NoteBodyTextView()
        tv.installAccessoryHosts()
        window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 800))
        window.addSubview(tv)
        window.makeKeyAndVisible()
        tv.frame = window.bounds
        coordinator.textView = tv
        coordinator.load(force: true)
        tv.layoutIfNeeded()
        if let tlm = tv.textLayoutManager {
            tlm.ensureLayout(for: tlm.documentRange)     // headless TextKit 2 layout
        }
        return (coordinator, tv)
    }

    /// First character index carrying `key`, or nil.
    @MainActor
    private func attachmentIndex(_ key: NSAttributedString.Key, in tv: UITextView) -> Int? {
        var found: Int?
        tv.textStorage.enumerateAttribute(key, in: NSRange(location: 0, length: tv.textStorage.length)) {
            value, range, stop in
            if value != nil { found = range.location; stop.pointee = true }
        }
        return found
    }

    @MainActor
    func testTapBesidePortraitPhotoIsNotAPhotoTap() throws {
        // A 200×800 portrait source renders narrower than the content width —
        // real empty space exists to its right (the P1#2 repro geometry).
        let filename = "photo_hit_test_001.jpg"
        let url = AppPaths.recordingsDirectory.appendingPathComponent(filename)
        try? FileManager.default.createDirectory(at: AppPaths.recordingsDirectory,
                                                 withIntermediateDirectories: true)
        let img = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 800)).image { ctx in
            UIColor.systemTeal.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 200, height: 800))
        }
        try XCTUnwrap(img.jpegData(compressionQuality: 0.8)).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        var meta = MemoMetadata()
        meta.imageManifest = [ImageManifestEntry(filename: filename, offsetSeconds: 0)]
        let memo = Memo.make(transcript: "look\n[[img_001]]\nafter", metadata: meta)
        let (coordinator, tv) = makeLaidOutEditor(memo: memo)

        let idx = try XCTUnwrap(attachmentIndex(NoteBodyView.Coordinator.markerKey, in: tv))
        let rect = try XCTUnwrap(tv.rects(forCharacterRange: NSRange(location: idx, length: 1)).first)
        XCTAssertLessThan(rect.width, 200, "portrait photo must render narrower than the page")

        XCTAssertEqual(coordinator.attachmentAction(at: CGPoint(x: rect.midX, y: rect.midY)),
                       .openImage(marker: 1), "a tap ON the photo opens the viewer")
        XCTAssertNil(coordinator.attachmentAction(at: CGPoint(x: rect.maxX + 40, y: rect.midY)),
                     "a tap in the empty space RIGHT of the photo is caret placement, not a photo tap")
    }

    @MainActor
    func testCheckboxTapTogglesWithFingerSlopRegardlessOfCaret() throws {
        let memo = Memo.make(transcript: "- [ ] buy milk")
        let (coordinator, tv) = makeLaidOutEditor(memo: memo)

        let idx = try XCTUnwrap(attachmentIndex(NoteBodyView.Coordinator.taskKey, in: tv))
        let rect = try XCTUnwrap(tv.rects(forCharacterRange: NSRange(location: idx, length: 1)).first)

        // The caret sits far away — the resolver must not care (the P1#6 miss
        // was exactly a caret that snapped somewhere unhelpful).
        tv.selectedRange = NSRange(location: tv.textStorage.length, length: 0)

        XCTAssertEqual(coordinator.attachmentAction(at: CGPoint(x: rect.midX, y: rect.midY)),
                       .toggleTask(at: idx))
        XCTAssertEqual(coordinator.attachmentAction(at: CGPoint(x: rect.maxX + 8, y: rect.midY)),
                       .toggleTask(at: idx), "a near-miss inside the finger slop still toggles")
        XCTAssertNil(coordinator.attachmentAction(at: CGPoint(x: rect.maxX + 40, y: rect.midY)),
                     "a tap on the task TEXT is editing, not a toggle")
    }

    @MainActor
    func testStaleTouchPointIsNotReplayed() {
        let tv = NoteBodyTextView()
        tv.noteTouchDown(CGPoint(x: 10, y: 10))
        XCTAssertNotNil(tv.recentTouchPoint)
        // Simulate staleness by aging the stash beyond the 0.6 s window.
        let exp = expectation(description: "staleness window elapses")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { exp.fulfill() }
        wait(for: [exp], timeout: 2)
        XCTAssertNil(tv.recentTouchPoint, "a keyboard-driven caret move must not replay an old touch")
    }
}

/// Photo display-block (signed off 2026-07-07, mocks/accessory-bar-v2.html
/// §#11): a mid-sentence photo renders as its own paragraph via TAGGED
/// display-only newlines — the raw keeps the marker mid-sentence, and no
/// inherited attribute can corrupt the round-trip.
final class PhotoBlockDisplayTests: XCTestCase {

    @MainActor
    private func makeEditor(transcript: String) -> (NoteBodyView.Coordinator, NoteBodyTextView) {
        let memo = Memo(audioFilename: "memo_block.m4a", transcript: transcript)
        let coordinator = NoteBodyView.Coordinator(memo: memo, onCommit: {})
        let tv = NoteBodyTextView()
        tv.installAccessoryHosts()
        coordinator.textView = tv
        coordinator.load(force: true)
        return (coordinator, tv)
    }

    @MainActor
    func testMidSentencePhotoRendersAsBlockAndRoundTrips() {
        let raw = "was fantastic [[img_001]] and then we walked"
        let (c, tv) = makeEditor(transcript: raw)
        XCTAssertTrue(tv.text.contains("\n\u{FFFC}\n"),
                      "the photo must sit on its own display line")
        XCTAssertEqual(c.reconstruct(tv.attributedText), raw,
                       "the raw keeps the marker mid-sentence — breaks are display-only")
    }

    @MainActor
    func testPhotoAlreadyOnOwnLineGainsNoExtraBreaks() {
        let raw = "look\n[[img_001]]\nafter"
        let (c, tv) = makeEditor(transcript: raw)
        XCTAssertEqual(tv.text, "look\n\u{FFFC}\nafter", "no doubled newlines")
        XCTAssertEqual(c.reconstruct(tv.attributedText), raw)
    }

    @MainActor
    func testTypedTextInheritingDisplayTagSurvivesReconstruct() {
        let (c, tv) = makeEditor(transcript: "a [[img_001]] b")
        // Simulate UIKit inheriting the display-only tag onto typed text.
        let typed = NSMutableAttributedString(string: "x")
        typed.addAttribute(NoteBodyView.Coordinator.displayOnlyKey, value: true,
                           range: NSRange(location: 0, length: 1))
        tv.textStorage.append(typed)
        XCTAssertTrue(c.reconstruct(tv.attributedText).hasSuffix("bx"),
                      "typed text must never vanish, even with a leaked display tag")
    }

    @MainActor
    func testInheritedMarkerKeyOnTypedTextEmitsNoSyntax() {
        let (c, tv) = makeEditor(transcript: "a [[img_001]] b")
        let typed = NSMutableAttributedString(string: "x")
        typed.addAttribute(NoteBodyView.Coordinator.markerKey, value: 1,
                           range: NSRange(location: 0, length: 1))
        tv.textStorage.append(typed)
        let out = c.reconstruct(tv.attributedText)
        XCTAssertEqual(out.components(separatedBy: "[[img_001]]").count, 2,
                       "exactly ONE marker — inherited keys on plain text emit no syntax")
        XCTAssertTrue(out.hasSuffix("bx"))
    }
}

/// Checklist Return-continuation (round-1 P2#8, the Notes idiom): Return in a
/// task line grows the list; Return on an empty item dissolves it. Driven
/// through the real shouldChangeTextIn delegate over the display text.
final class ChecklistContinuationTests: XCTestCase {

    @MainActor
    private func makeEditor(transcript: String) -> (NoteBodyView.Coordinator, NoteBodyTextView) {
        let memo = Memo(audioFilename: "memo_check.m4a", transcript: transcript)
        let coordinator = NoteBodyView.Coordinator(memo: memo, onCommit: {})
        let tv = NoteBodyTextView()
        tv.installAccessoryHosts()
        coordinator.textView = tv
        coordinator.load(force: true)
        return (coordinator, tv)
    }

    /// Simulate pressing Return at `caret` through the delegate, applying the
    /// default insertion only when the coordinator didn't handle it.
    @MainActor
    private func pressReturn(_ c: NoteBodyView.Coordinator, _ tv: NoteBodyTextView, at caret: Int) {
        tv.selectedRange = NSRange(location: caret, length: 0)
        if c.textView(tv, shouldChangeTextIn: NSRange(location: caret, length: 0),
                      replacementText: "\n") {
            tv.textStorage.replaceCharacters(in: NSRange(location: caret, length: 0), with: "\n")
        }
    }

    @MainActor
    func testReturnAtEndOfTaskLineContinuesTheList() {
        let (c, tv) = makeEditor(transcript: "- [ ] buy milk")
        pressReturn(c, tv, at: tv.textStorage.length)
        c.commitDraft()
        XCTAssertEqual(c.memo.transcript, "- [ ] buy milk\n- [ ] ",
                       "Return must open a fresh unchecked item")
    }

    @MainActor
    func testReturnMidLineSplitsIntoTwoItems() {
        let (c, tv) = makeEditor(transcript: "- [ ] buy milk")
        // Display: [box]" buy milk" — caret after "buy" (box=1 + " buy"=4 → 5).
        pressReturn(c, tv, at: 5)
        c.commitDraft()
        XCTAssertEqual(c.memo.transcript, "- [ ] buy\n- [ ] milk",
                       "the split tail keeps its text, separator space consumed")
    }

    @MainActor
    func testReturnOnEmptyItemEndsTheList() {
        let (c, tv) = makeEditor(transcript: "- [ ] buy milk\n- [ ] ")
        pressReturn(c, tv, at: tv.textStorage.length)
        c.commitDraft()
        // Notes semantics: the box dissolves into an empty PLAIN line (the
        // caret parks there), so the raw keeps the line break — but no box.
        XCTAssertEqual(c.memo.transcript, "- [ ] buy milk\n",
                       "Return on an empty item must dissolve the box, not add another")
        XCTAssertEqual(tv.selectedRange.location, tv.textStorage.length,
                       "the caret parks on the now-plain empty line")
    }

    @MainActor
    func testReturnOnPlainLineIsUntouched() {
        let (c, tv) = makeEditor(transcript: "plain text line")
        pressReturn(c, tv, at: tv.textStorage.length)
        c.commitDraft()
        XCTAssertEqual(c.memo.transcript, "plain text line",
                       "trailing whitespace trims on commit; no box was added")
        XCTAssertFalse(BodyTransform.containsTaskSyntax(c.memo.transcript ?? ""))
    }

    // MARK: accessory ☑ (bar v2, signed off 2026-07-07)

    @MainActor
    func testAccessoryToggleMakesCaretLineAChecklistItem() {
        let (c, tv) = makeEditor(transcript: "buy milk\nplain below")
        tv.selectedRange = NSRange(location: 3, length: 0)          // inside "buy milk"
        XCTAssertFalse(c.caretInTaskLine())
        c.toggleChecklistAtCaret()
        XCTAssertTrue(c.caretInTaskLine(), "the ☑ state must light up")
        c.commitDraft()
        XCTAssertEqual(c.memo.transcript, "- [ ] buy milk\nplain below")
    }

    @MainActor
    func testAccessoryToggleDissolvesAnExistingBox() {
        let (c, tv) = makeEditor(transcript: "- [ ] buy milk")
        tv.selectedRange = NSRange(location: 4, length: 0)
        XCTAssertTrue(c.caretInTaskLine())
        c.toggleChecklistAtCaret()
        XCTAssertFalse(c.caretInTaskLine())
        c.commitDraft()
        XCTAssertEqual(c.memo.transcript, "buy milk", "un-task keeps the text")
    }
}

/// Accessory 📷 camera source (round-1 P2): the system-camera wrapper must
/// forward the captured image, and the simulator must stay library-only.
final class CameraImagePickerTests: XCTestCase {

    @MainActor
    func testSimulatorHasNoCamera() {
        XCTAssertFalse(CameraImagePicker.isAvailable,
                       "the sim gate keeps Take Photo out of camera-less environments")
    }

    @MainActor
    func testDelegateForwardsCapturedImage() {
        var received: UIImage?
        let picker = CameraImagePicker { received = $0 }
        let coordinator = picker.makeCoordinator()
        let image = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).image { _ in }
        coordinator.imagePickerController(UIImagePickerController(),
                                          didFinishPickingMediaWithInfo: [.originalImage: image])
        XCTAssertNotNil(received, "a capture must reach onCapture")
    }
}

/// Markup save-back plumbing (round-1 P2#10): QuickLook must run in
/// .updateContents (write INTO the photo file), edits must reach onEdited,
/// and the thumbnail cache must self-invalidate when the file is rewritten.
final class MarkupSaveBackTests: XCTestCase {

    @MainActor
    func testPreviewRunsInUpdateContentsMode() {
        let view = MarkupPreviewView(url: URL(fileURLWithPath: "/tmp/x.jpg"))
        let coordinator = view.makeCoordinator()
        let mode = coordinator.previewController(QLPreviewController(),
                                                 editingModeFor: URL(fileURLWithPath: "/tmp/x.jpg") as NSURL)
        XCTAssertEqual(mode, .updateContents, "markup must save back into the file, not a copy")
    }

    @MainActor
    func testDidUpdateContentsFiresOnEdited() {
        var edited = false
        let view = MarkupPreviewView(url: URL(fileURLWithPath: "/tmp/x.jpg")) { edited = true }
        let coordinator = view.makeCoordinator()
        coordinator.previewController(QLPreviewController(),
                                      didUpdateContentsOf: URL(fileURLWithPath: "/tmp/x.jpg") as NSURL)
        XCTAssertTrue(edited, "a save-back must reach the re-mirror/re-OCR chain")
    }

    @MainActor
    func testThumbnailCacheInvalidatesWhenFileRewritten() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("thumb-\(UUID().uuidString).jpg")
        defer { try? FileManager.default.removeItem(at: url) }

        func write(_ size: CGSize, stampedAt date: Date) throws {
            let img = UIGraphicsImageRenderer(size: size).image { ctx in
                UIColor.systemRed.setFill()
                ctx.fill(CGRect(origin: .zero, size: size))
            }
            try XCTUnwrap(img.jpegData(compressionQuality: 0.9)).write(to: url)
            try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
        }

        try write(CGSize(width: 40, height: 40), stampedAt: Date(timeIntervalSinceNow: -60))
        let before = try XCTUnwrap(MemoImageLoader.thumbnail(at: url, maxWidth: 100))
        XCTAssertEqual(before.size.width, before.size.height, accuracy: 1)

        // A markup save rewrites the file (different content, new mtime) —
        // the next load must decode fresh, not serve the cached square.
        try write(CGSize(width: 80, height: 40), stampedAt: Date())
        let after = try XCTUnwrap(MemoImageLoader.thumbnail(at: url, maxWidth: 100))
        XCTAssertEqual(after.size.width, after.size.height * 2, accuracy: 2,
                       "the rewritten file must yield a fresh thumbnail (mtime-keyed cache)")
    }
}

/// Share-out + stats helpers (chunk 2 survey folds).
final class MemoShareTests: XCTestCase {

    func testMarkdownComposesTitleAndStripsMarkers() {
        let md = MemoShare.markdown(title: "Evening walk",
                                    body: "First line. [[img_001]] Second line.")
        XCTAssertEqual(md, "# Evening walk\n\nFirst line.  Second line.")
        XCTAssertFalse(md.contains("[[img"))
    }

    func testMarkdownWithoutTitleIsJustTheBody() {
        XCTAssertEqual(MemoShare.markdown(title: "  ", body: "Body."), "Body.")
        XCTAssertEqual(MemoShare.markdown(title: nil, body: "Body."), "Body.")
    }

    func testMarkdownCollapsesMarkerOnlyParagraphs() {
        let md = MemoShare.markdown(title: nil, body: "Before.\n\n[[img_001]]\n\nAfter.")
        XCTAssertEqual(md, "Before.\n\n\nAfter.".replacingOccurrences(of: "\n\n\n", with: "\n\n"))
    }

    func testWordCountSkipsMarkers() {
        XCTAssertEqual(MemoShare.wordCount(of: "one two [[img_001]] three"), 3)
        XCTAssertEqual(MemoShare.wordCount(of: nil), 0)
        XCTAssertEqual(MemoShare.wordCount(of: "  "), 0)
    }
}

/// The karaoke word map: display-text word ranges must align with the timings
/// sidecar's word indexing (whitespace-delimited spoken words; attachment glyphs
/// are not words).
final class KaraokeMapTests: XCTestCase {

    func testPlainWords() {
        let ranges = KaraokeMap.wordRanges(in: "one two  three" as NSString)
        XCTAssertEqual(ranges.count, 3)
        XCTAssertEqual(ranges[0], NSRange(location: 0, length: 3))
        XCTAssertEqual(ranges[1], NSRange(location: 4, length: 3))
        XCTAssertEqual(ranges[2], NSRange(location: 9, length: 5))
    }

    func testNewlinesSplitWords() {
        let ranges = KaraokeMap.wordRanges(in: "alpha\nbeta\n\ngamma" as NSString)
        XCTAssertEqual(ranges.count, 3)
    }

    func testAttachmentGlyphIsNotAWord() {
        let text = "before \u{FFFC} after" as NSString
        let ranges = KaraokeMap.wordRanges(in: text)
        XCTAssertEqual(ranges.count, 2)
        XCTAssertEqual(text.substring(with: ranges[1]), "after")
    }

    func testAttachmentGluedToWordCountsOnce() {
        let text = "word\u{FFFC} next" as NSString
        let ranges = KaraokeMap.wordRanges(in: text)
        XCTAssertEqual(ranges.count, 2, "a glued attachment must not add a word")
    }

    func testWordIndexAtCharIndex() {
        let ranges = KaraokeMap.wordRanges(in: "one two three" as NSString)
        XCTAssertEqual(KaraokeMap.wordIndex(at: 0, in: ranges), 0)
        XCTAssertEqual(KaraokeMap.wordIndex(at: 5, in: ranges), 1)
        XCTAssertEqual(KaraokeMap.wordIndex(at: 3, in: ranges), 0, "whitespace maps to the word just read")
        XCTAssertEqual(KaraokeMap.wordIndex(at: 12, in: ranges), 2)
        XCTAssertNil(KaraokeMap.wordIndex(at: 0, in: []))
    }
}
