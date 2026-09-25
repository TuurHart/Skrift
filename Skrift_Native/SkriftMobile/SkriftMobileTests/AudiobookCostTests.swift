import CoreGraphics
import ImageIO
import Observation
import UIKit
import UniformTypeIdentifiers
import XCTest
@testable import SkriftMobile

/// Q57/C218 — one case per audiobook cost fix from `plan/sweep-c-record-books-share.md`:
/// no full sidecar decode on main per reconcile, linear (not O(n²)) sentence merge, a quiet
/// player tick (no whole-view re-render every 0.5 s), and concurrent shared-payload loads.
final class AudiobookCostTests: XCTestCase {

    // MARK: - 1. `BookAlignmentStore.cloudSignaturePart` is cache-served, no full decode on repeat

    func testAlignmentCloudSignatureIsCacheServedNotReDecodedOnRepeat() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("costtest_al_\(UUID().uuidString)")
        let store = BookAlignmentStore(directory: dir)
        let bookID = UUID()
        let sentence = AlignedSentence(text: "Hello.", start: 0, end: 1, wordStart: 0, wordEnd: 1,
                                       confidence: 1, words: [], sourceFile: "f.xhtml", textFile: "a.epub")
        let fa = FileAlignment(fileIndex: 0, transcriptSignature: "1:1", epubSignature: "s",
                               verdict: "aligned", sentences: [sentence],
                               sources: [AlignmentSource(textFilename: "a.epub", title: nil,
                                                         verdict: "aligned", coverage: 1)])
        try store.save(fa, bookID: bookID)

        let first = store.cloudSignaturePart(bookID: bookID, fileIndex: 0)
        XCTAssertEqual(first, fa.cloudSignaturePart())

        // Corrupt the sidecar's BYTES (a real decode would fail — invalid JSON) but keep its
        // size + modification date IDENTICAL, so the cache-freshness key still matches. A
        // second call returning the SAME (correct) answer proves it was cache-served, not
        // re-decoded — a re-decode of garbage bytes would return nil instead.
        let url = store.sidecarURL(bookID: bookID, fileIndex: 0)
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attrs[.size] as? Int) ?? 0
        try Data(repeating: 0x2E, count: size).write(to: url)
        try FileManager.default.setAttributes(attrs, ofItemAtPath: url.path)

        let second = store.cloudSignaturePart(bookID: bookID, fileIndex: 0)
        XCTAssertEqual(second, first, "same-signature sidecar must be cache-served (Q57/C218)")

        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: - 2. `BookAlignmentRunner.mergeSentences` — linear, output unchanged incl. seam overlap

    private func sentence(_ textFile: String, start: TimeInterval, end: TimeInterval,
                          confidence: Double = 1) -> AlignedSentence {
        AlignedSentence(text: "x", start: start, end: end, wordStart: 0, wordEnd: 1, confidence: confidence,
                        words: [], sourceFile: "f.xhtml", textFile: textFile)
    }

    func testMergeSentencesLinearAtScaleAndSeamOverlapStillSurvives() {
        // Seam-overlap regression (2026-07-23 Odyssey round, BookAlignmentTests' original
        // case): same-text hairline time overlaps must never contest each other.
        let seamIncoming = [sentence("a.epub", start: 158.9, end: 165.8),
                            sentence("a.epub", start: 165.6, end: 181.9),
                            sentence("a.epub", start: 181.9, end: 188.8)]
        let seamMerged = BookAlignmentRunner.mergeSentences(into: [], adding: seamIncoming, textRank: ["a.epub": 0])
        XCTAssertEqual(seamMerged.count, 3, "same-text seam fuzz is not a collision")

        // Scale case: N disjoint `keep` sentences (text A) + N disjoint `incoming` sentences
        // (text B), interleaved so every OTHER incoming sentence collides with exactly one
        // keep sentence. A quadratic scan (the old code) does N*N/2 overlap checks here; the
        // sorted-binary-search merge does O(N log N) — this only finishes promptly if that
        // held.
        let n = 6000
        var keep: [AlignedSentence] = []
        keep.reserveCapacity(n)
        for i in 0..<n { keep.append(sentence("a.epub", start: Double(i) * 10, end: Double(i) * 10 + 4, confidence: 0.5)) }
        var incoming: [AlignedSentence] = []
        incoming.reserveCapacity(n)
        for i in 0..<n {
            // Half land inside a keep sentence's span (contest it, win on confidence);
            // half land in the gap between keep sentences (no conflict).
            let start = i.isMultiple(of: 2) ? Double(i) * 10 + 1 : Double(i) * 10 + 6
            incoming.append(sentence("b.epub", start: start, end: start + 1, confidence: 0.9))
        }

        let start = Date()
        let merged = BookAlignmentRunner.mergeSentences(into: keep, adding: incoming, textRank: ["a.epub": 0, "b.epub": 1])
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertLessThan(elapsed, 5.0, "mergeSentences must be near-linear, not O(n²) (Q57/C218)")

        // Correctness: every incoming sentence's higher confidence (0.9 > 0.5) wins its
        // collision, so ALL n incoming sentences survive; only the half of `keep` that was
        // never contested (the odd-i gap-landing ones never touch a keep sentence at all —
        // wait, every even i contests keep[i]) survive too.
        let survivingKeep = merged.filter { $0.textFile == "a.epub" }.count
        let survivingIncoming = merged.filter { $0.textFile == "b.epub" }.count
        XCTAssertEqual(survivingIncoming, n, "every b.epub sentence beats or avoids its keep neighbor")
        XCTAssertEqual(survivingKeep, n / 2, "only the untouched half of a.epub survives")
        XCTAssertEqual(merged.count, n + n / 2)
    }

    // MARK: - 3. `AudiobookSession` is `@Observable`, not `ObservableObject`

    func testAudiobookSessionIsObservableNotObservableObject() {
        // Q57/C218: ObservableObject's single combined `objectWillChange` re-rendered
        // EVERY view holding `.shared` on every 0.5 s playback tick, even ones that never
        // read `currentTime` (mini player, library rows, chapters sheet, …). `@Observable`
        // tracks per-property, isolating the tick to only the views that read it.
        func requiresObservable(_ value: some Observable) -> Bool { true }
        XCTAssertTrue(requiresObservable(AudiobookSession.shared),
                     "AudiobookSession must conform to Observable (compiles only if it does)")
    }

    // MARK: - 4. `SharePayloadLoader.loadImages` — concurrent, provider order preserved

    private func solidPNG(side: CGFloat) -> Data {
        // Force scale 1 — the default `UIGraphicsImageRenderer` scale is the SIMULATOR
        // SCREEN's scale (3x on iPhone 17), so a "4pt" image was rendering as a 12px PNG.
        // That's a fixed ×3 offset on every width, NOT an order mismatch: it made the
        // first assertion (12.0 vs expected 4.0) look like a collision-order bug when the
        // concurrency/order code was actually correct throughout.
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format)
        let img = renderer.image { _ in
            UIColor.red.setFill()
            UIRectFill(CGRect(x: 0, y: 0, width: side, height: side))
        }
        return img.pngData()!
    }

    func testLoadImagesConcurrentPreservesProviderOrder() async throws {
        // Distinct pixel widths per provider — decoding each RESULT item's width back out
        // proves item i really is provider i's image, regardless of which concurrent task
        // (Q57/C218: a `TaskGroup`, was a sequential `for` loop) finished first.
        let widths: [CGFloat] = [4, 8, 12, 16, 20, 24, 28, 32]
        let providers = widths.map { NSItemProvider(item: solidPNG(side: $0) as NSData, typeIdentifier: UTType.png.identifier) }

        let payload = await SharePayloadLoader.loadImages(from: providers)
        XCTAssertEqual(payload.imageItems.count, widths.count)

        for (i, item) in payload.imageItems.enumerated() {
            guard let src = CGImageSourceCreateWithData(item.data as CFData, nil),
                  let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
                  let w = props[kCGImagePropertyPixelWidth] as? CGFloat
            else { XCTFail("undecodable output image at index \(i)"); continue }
            XCTAssertEqual(w, widths[i], "provider order must survive concurrent loading")
        }
    }
}
