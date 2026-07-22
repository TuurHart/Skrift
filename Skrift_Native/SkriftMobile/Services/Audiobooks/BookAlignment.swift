import CryptoKit
import Foundation
import NaturalLanguage
import ZIPFoundation

/// 📖 spike 6 — productize alignment (`LANES-2026-07-21C/BASE.md`, spikes 1–5 GO). Turns an
/// attached ePub/text file + the per-file ASR transcript sidecars (`BookTranscript.swift`) into
/// per-file `FileAlignment` sidecars via `AlignmentCore` (Shared/Pipeline, spikes 4–5) — the
/// TRUE book text, timed, sentence-by-sentence, for the read-along surfaces (LANE_UI) to render
/// instead of raw ASR. Mirrors `BookTranscriptStore`'s on-disk shape (atomic JSON, schema-gated,
/// same book folder) and `AudiobookCloudSync`'s transcript sync block field-for-field.
///
/// TIME BASIS = (fileIndex, file-local seconds) for `AlignedSentence.start/end`, same as
/// `FileTranscript` — global time is `book.fileStartTimes[fileIndex] + sentence.start`.
///
/// ARCHITECTURAL NOTE (see `PLAN_CORE.md`): `AlignmentCore.flattenBook` numbers a
/// `MatchedRange.bookWordStart/bookWordEnd` LOCAL TO EACH `Block` PASSED IN, resetting per
/// block. `EPubParse` emits one `EPubBlock` per paragraph (many per spine file, same
/// `sourceFile` repeated) — feeding those straight in would make a matched run spanning two
/// paragraphs of one file produce nonsense word-count math. `mergeBlocksByFile` concatenates
/// adjacent same-`sourceFile` blocks into ONE `Block` per epub-internal file first (semantics-
/// preserving for the aligner — same token stream, same anchors/DP/coverage/verdict, only the
/// REPORTING granularity changes), which is what makes `bookWordStart/bookWordEnd` safe to use
/// directly as slice bounds in `assembleSentences`.

// MARK: - Contract types (pinned — LANES-2026-07-21C/BASE.md cross-lane seam, LANE_UI consumes)

/// One sentence of published book text, timed via alignment. `words` carries ONLY the words
/// that landed inside a matched range, with the aligner's EXACT per-word times
/// (`MatchedRange.wordTimes`, 2026-07-22 — the earlier linear re-distribution drifted seconds
/// over pauses); `text` is always the FULL original sentence substring regardless of how many
/// of its words got timed. A sentence with zero timed words is dropped entirely by
/// `assembleSentences` (it never appears here).
struct AlignedSentence: Codable, Equatable, Sendable {
    /// Published book text, display-ready (the original substring — punctuation/spacing intact).
    var text: String
    /// FILE-LOCAL seconds (first timed word's start).
    var start: TimeInterval
    /// FILE-LOCAL seconds (last timed word's end).
    var end: TimeInterval
    /// Transcript (ASR) word-index range covering `[start, end]` — the fallback splice
    /// (`ft.words[wordStart..<wordEnd]`) a consumer renders instead of `text`/`words` when
    /// `confidence` is too low to trust the book text placement (BASE.md: < 0.5).
    var wordStart: Int
    /// Exclusive.
    var wordEnd: Int
    /// Fraction of this sentence's book words the aligner DIRECT-matched to a transcript word
    /// (2026-07-22: interpolated words no longer count — a mostly-guessed sentence should fall
    /// back to ASR text, which the old timed-fraction never captured).
    var confidence: Double
    /// Book words with per-word times (karaoke), in order — a subset of the sentence's full word
    /// count when some words fell in an unmatched span.
    var words: [WordTiming]
    /// The ePub spine path (or the plain-text filename for a `.txt` attach) this sentence's text
    /// came from.
    var sourceFile: String?
}

/// One TOC entry resolved to a place in the timed sentence stream — `sentenceIndex` is LOCAL to
/// the `FileAlignment` it lives in. Persisted (not re-derived from the epub each time) so a
/// receiver with no epub file can rebuild `Audiobook.epubChapters` from synced sidecars alone.
struct ChapterMark: Codable, Equatable, Sendable {
    var title: String
    var sentenceIndex: Int
}

/// One audio file's alignment result — the on-disk sidecar shape
/// (`alignment_f<n>.json`, beside `transcript_f<n>.json`).
struct FileAlignment: Codable, Equatable, Sendable {
    /// Bumped if the on-disk shape changes — an older sidecar then reads as absent (re-aligned).
    /// 1→2 (2026-07-22): word times became EXACT (per-word from the aligner) instead of
    /// linearly re-distributed across matched ranges, and `confidence` became the
    /// direct-matched fraction. The schema-gated load treats v1 sidecars as missing, so
    /// every attached book silently re-aligns on its next open (alignIfNeeded) — the
    /// drifted-highlight fix reaches existing installs without any user action.
    static let currentSchema = 2

    var schema: Int = currentSchema
    /// Which file of the book this covers (`Audiobook.files` index).
    var fileIndex: Int
    /// `"<Int(coveredUpTo)>:<wordCount>"` of the transcript sidecar THIS alignment was computed
    /// against — `BookAlignmentStore.isFresh` recomputes this from the CURRENT local transcript
    /// and compares (see `signature(forTranscript:)`).
    var transcriptSignature: String
    /// SHA-256 hex of the attached ePub's bytes at alignment time (diagnostic / future
    /// invalidation hook — not currently compared anywhere; the ePub itself never syncs).
    var epubSignature: String
    /// `AlignmentCore.Verdict.rawValue` ("aligned" / "partial" / "rejected").
    var verdict: String
    var chapterMarks: [ChapterMark] = []
    var sentences: [AlignedSentence] = []

    /// The staleness key: matches `signature(forTranscript:)` computed from the transcript
    /// sidecar this alignment was run against. A CURRENT transcript sidecar's signature
    /// differing from this means the book has been transcribed further since — stale.
    static func signature(forTranscript ft: FileTranscript) -> String {
        "\(Int(ft.coveredUpTo)):\(ft.words.count)"
    }

    /// This file's contribution to `AudiobookCloudSync`'s alignment change-signature
    /// (`"<fileIndex>:<verdict>:<sentenceCount>"`) — joined with "|" across a book's files
    /// there, mirroring `localTranscriptSignature`'s shape exactly.
    func cloudSignaturePart() -> String {
        "\(fileIndex):\(verdict):\(sentences.count)"
    }
}

// MARK: - Store

/// On-disk home for the per-book, per-file ALIGNMENT sidecars. One JSON per audio file, beside
/// its transcript sidecar: `Documents/audiobooks/<id>/alignment_f<n>.json`. Same shape/contract
/// as `BookTranscriptStore` (atomic write, schema-gated read) — a `final class` (not a struct)
/// per the pinned cross-lane contract. Immutable state only (`directory`) — safe to use from any
/// isolation context, never mutated after init.
final class BookAlignmentStore: Sendable {
    let directory: URL

    init(directory: URL = AppPaths.documentsDirectory.appendingPathComponent("audiobooks", isDirectory: true)) {
        self.directory = directory
    }

    func folder(forBookID id: UUID) -> URL {
        directory.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    func sidecarURL(bookID: UUID, fileIndex: Int) -> URL {
        folder(forBookID: bookID).appendingPathComponent("alignment_f\(fileIndex).json")
    }

    /// Schema-gated load; nil when missing, unreadable, or an old/foreign schema.
    func fileAlignment(bookID: UUID, fileIndex: Int) -> FileAlignment? {
        guard let data = try? Data(contentsOf: sidecarURL(bookID: bookID, fileIndex: fileIndex)),
              let fa = try? JSONDecoder().decode(FileAlignment.self, from: data),
              fa.schema == FileAlignment.currentSchema
        else { return nil }
        return fa
    }

    /// Atomically persist one file's alignment (write temp → replace), creating the book folder
    /// if needed.
    func save(_ fa: FileAlignment, bookID: UUID) throws {
        let folder = folder(forBookID: bookID)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(fa)
        try data.write(to: sidecarURL(bookID: bookID, fileIndex: fa.fileIndex), options: .atomic)
    }

    /// Fresh = `fa.transcriptSignature` matches the CURRENT transcript sidecar's signature for
    /// that file. False (never fresh) when that transcript can't be loaded at all — there's
    /// nothing to compare against, so the caller treats it the same as stale.
    func isFresh(_ fa: FileAlignment, bookID: UUID, fileIndex: Int, audioURL: URL) -> Bool {
        let transcriptStore = BookTranscriptStore(directory: directory)
        let sig = transcriptStore.signature(forFileAt: audioURL)
        guard let ft = transcriptStore.load(bookID: bookID, fileIndex: fileIndex, expectedSignature: sig) else {
            return false
        }
        return fa.transcriptSignature == FileAlignment.signature(forTranscript: ft)
    }
}

// MARK: - Runner

enum BookAlignmentRunner {

    struct AttachSummary: Equatable {
        var alignedFiles: Int
        var rejectedFiles: Int
        var totalFiles: Int
    }

    enum AttachError: LocalizedError, Equatable {
        case bookMissing
        case copyFailed
        case unreadable

        var errorDescription: String? {
            switch self {
            case .bookMissing: return "That audiobook couldn’t be found."
            case .copyFailed: return "The file couldn’t be copied into Skrift."
            case .unreadable: return "That file doesn’t look like a readable ePub or text file."
            }
        }
    }

    // MARK: Attach

    /// Copy the picked file into the book folder (original filename kept), parse it, align every
    /// file with a covered transcript sidecar against it, save the sidecars, derive
    /// `epubChapters`, and update the book (`epubFilename` + `epubChapters`, `modifiedAt`
    /// bumped). Rejected-everywhere still writes sidecars (verdict recorded) — the UI decides
    /// what to tell the user from `AttachSummary`/the sidecars' verdicts.
    static func attach(bookFileAt url: URL, bookID: UUID) async throws -> AttachSummary {
        guard let book = await MainActor.run(body: { AudiobookLibraryStore.shared.book(id: bookID) }) else {
            throw AttachError.bookMissing
        }
        let folder = BookTranscriptStore().folder(forBookID: bookID)
        let filename = url.lastPathComponent
        let dest = folder.appendingPathComponent(filename)

        // Bare closure (no explicit `() throws -> T in` signature) so the compiler infers the
        // async+throws effects from the `let outcome: AttachOutcome =` context — matches
        // `AudiobookImporter.importSingleFile`'s exact "copy + parse off main" shape.
        let outcome: AttachOutcome = try await Task.detached(priority: .userInitiated) {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try AudiobookImporter.materializingCopy(from: url, to: dest)
            } catch {
                throw AttachError.copyFailed
            }

            let epubBook = try parseBookFile(at: dest)
            let alignBlocks = mergeBlocksByFile(epubBook.blocks)
            let epubSig = (try? Data(contentsOf: dest)).map(sha256Hex) ?? ""

            let transcriptStore = BookTranscriptStore()
            var fileAlignments: [Int: FileAlignment] = [:]
            var aligned = 0, rejected = 0, total = 0
            for i in book.files.indices {
                let audioURL = folder.appendingPathComponent(book.files[i])
                let sig = transcriptStore.signature(forFileAt: audioURL)
                guard let ft = transcriptStore.load(bookID: bookID, fileIndex: i, expectedSignature: sig),
                      !ft.words.isEmpty else { continue }
                total += 1
                let fileResult = alignFile(ft: ft, against: alignBlocks)
                fileAlignments[i] = FileAlignment(
                    fileIndex: i,
                    transcriptSignature: FileAlignment.signature(forTranscript: ft),
                    epubSignature: epubSig,
                    verdict: fileResult.verdict.rawValue,
                    sentences: fileResult.sentences
                )
                if fileResult.verdict == .aligned { aligned += 1 }
                if fileResult.verdict == .rejected { rejected += 1 }
            }
            return AttachOutcome(fileAlignments: fileAlignments, toc: epubBook.toc,
                                 aligned: aligned, rejected: rejected, total: total)
        }.value

        await finishAlign(bookID: bookID, toc: outcome.toc, justAligned: outcome.fileAlignments,
                          epubFilename: filename)
        return AttachSummary(alignedFiles: outcome.aligned, rejectedFiles: outcome.rejected,
                             totalFiles: outcome.total)
    }

    private struct AttachOutcome {
        var fileAlignments: [Int: FileAlignment]
        var toc: [EPubTOCEntry]
        var aligned: Int
        var rejected: Int
        var total: Int
    }

    // MARK: Incremental re-align

    /// Cheap no-op-guarded re-align: no `epubFilename` on the book, the attached file missing
    /// from disk (receiver device — nothing to compute locally), or every file's sidecar already
    /// fresh ⇒ returns fast. Otherwise re-parses the (already-attached) file and re-runs
    /// alignment for the stale files only, then reconciles chapter marks + `epubChapters` across
    /// the WHOLE book (not just the files touched this pass) so the "first TOC match wins,
    /// globally" invariant can't drift between files aligned now and files aligned earlier.
    static func alignIfNeeded(bookID: UUID) async {
        guard let book = await MainActor.run(body: { AudiobookLibraryStore.shared.book(id: bookID) }),
              let epubFilename = book.epubFilename else { return }
        let folder = BookTranscriptStore().folder(forBookID: bookID)
        let bookFileURL = folder.appendingPathComponent(epubFilename)
        guard FileManager.default.fileExists(atPath: bookFileURL.path) else { return }

        let transcriptStore = BookTranscriptStore()
        let alignmentStore = BookAlignmentStore()
        var staleIndices: [Int] = []
        for i in book.files.indices {
            let audioURL = folder.appendingPathComponent(book.files[i])
            guard FileManager.default.fileExists(atPath: audioURL.path) else { continue }
            let sig = transcriptStore.signature(forFileAt: audioURL)
            guard let ft = transcriptStore.load(bookID: bookID, fileIndex: i, expectedSignature: sig),
                  !ft.words.isEmpty else { continue }
            if let fa = alignmentStore.fileAlignment(bookID: bookID, fileIndex: i),
               alignmentStore.isFresh(fa, bookID: bookID, fileIndex: i, audioURL: audioURL) {
                continue   // up to date
            }
            staleIndices.append(i)
        }
        guard !staleIndices.isEmpty else {
            // SELF-HEAL (2026-07-22 device catch): nothing to re-align, but the DERIVED
            // chapter list may still disagree with what's stored — e.g. sidecars written
            // by a build whose derivation let rejected files claim TOC entries (the
            // phantom-chapters bug). Recomputing from disk is a cheap pure pass; persist
            // only on a real difference, so the routine book-open case writes nothing.
            let current: [FileAlignment?] = book.files.indices.map {
                alignmentStore.fileAlignment(bookID: bookID, fileIndex: $0)
            }
            let derived = epubChapters(from: current, fileStartTimes: book.fileStartTimes,
                                       bookDuration: book.duration,
                                       detected: book.detectedChapters,
                                       fileDurations: book.fileDurations)
            if !derived.isEmpty || book.epubChapters?.isEmpty == false, book.epubChapters != derived {
                await MainActor.run {
                    guard var fresh = AudiobookLibraryStore.shared.book(id: bookID) else { return }
                    fresh.epubChapters = derived
                    fresh.modifiedAt = Date()
                    AudiobookLibraryStore.shared.update(fresh)
                    AudiobookSession.shared.refreshFromStore()
                }
                DevLog.log("bookAlign[\(bookID)] self-heal: epubChapters re-derived (\(derived.count) entries)")
            }
            return
        }

        // Bare closure, as in `attach` — the outer `let` annotation supplies the async+throws-
        // free effect signature the compiler needs (this closure only ever returns, never throws;
        // `parseBookFile`'s error is swallowed via `try?` since `alignIfNeeded` has no error path).
        let realigned: (fa: [Int: FileAlignment], toc: [EPubTOCEntry])? = await Task.detached(priority: .utility) {
            guard let epubBook = try? parseBookFile(at: bookFileURL) else {
                DevLog.log("bookAlign[\(bookID)] re-parse failed for \(epubFilename) — skipping re-align")
                return nil
            }
            let alignBlocks = mergeBlocksByFile(epubBook.blocks)
            var fileAlignments: [Int: FileAlignment] = [:]
            let epubSig = (try? Data(contentsOf: bookFileURL)).map(sha256Hex) ?? ""
            for i in staleIndices {
                let audioURL = folder.appendingPathComponent(book.files[i])
                let sig = transcriptStore.signature(forFileAt: audioURL)
                guard let ft = transcriptStore.load(bookID: bookID, fileIndex: i, expectedSignature: sig),
                      !ft.words.isEmpty else { continue }
                let fileResult = alignFile(ft: ft, against: alignBlocks)
                fileAlignments[i] = FileAlignment(
                    fileIndex: i,
                    transcriptSignature: FileAlignment.signature(forTranscript: ft),
                    epubSignature: epubSig,
                    verdict: fileResult.verdict.rawValue,
                    sentences: fileResult.sentences
                )
            }
            return (fileAlignments, epubBook.toc)
        }.value

        guard let realigned, !realigned.fa.isEmpty else { return }
        await finishAlign(bookID: bookID, toc: realigned.toc, justAligned: realigned.fa)
    }

    // MARK: - One-file alignment (transcript → AlignmentCore → sentences)

    private struct FileAlignResult {
        var verdict: AlignmentCore.Verdict
        var sentences: [AlignedSentence]
    }

    /// Run `AlignmentCore.align` (defaults) for one audio file's transcript against the whole
    /// book, then assemble sentences per epub source file from the result.
    private static func alignFile(ft: FileTranscript, against alignBlocks: [AlignmentCore.Block]) -> FileAlignResult {
        let transcript = ft.words.map { AlignmentCore.Word(text: $0.word, start: $0.start, end: $0.end) }
        let result = AlignmentCore.align(transcript: transcript, book: alignBlocks)
        var sentences: [AlignedSentence] = []
        for block in alignBlocks {
            sentences += assembleSentences(text: block.text, sourceFile: block.sourceFile,
                                           matchedRanges: result.matchedRanges, transcriptWords: ft.words)
        }
        return FileAlignResult(verdict: result.verdict, sentences: sentences)
    }

    // MARK: - Chapter-mark reconciliation (shared tail for attach / alignIfNeeded)

    /// After (re)aligning `justAligned` (index → freshly-computed `FileAlignment`, not yet
    /// saved), reconcile EVERY file's `chapterMarks` against `toc` — loading the rest from their
    /// existing sidecars — so a TOC entry's "first match" stays correct even when only SOME
    /// files were touched this pass. Saves whichever sidecars' marks changed (including
    /// untouched ones, if reconciliation moved a mark), rebuilds + persists `book.epubChapters`,
    /// optionally stamps `epubFilename`, bumps `modifiedAt`, and refreshes the live session.
    private static func finishAlign(bookID: UUID, toc: [EPubTOCEntry], justAligned: [Int: FileAlignment],
                                    epubFilename: String? = nil) async {
        guard let book = await MainActor.run(body: { AudiobookLibraryStore.shared.book(id: bookID) }) else { return }
        let store = BookAlignmentStore()

        for fa in justAligned.values {
            try? store.save(fa, bookID: bookID)
        }

        var current: [FileAlignment?] = book.files.indices.map { i in
            justAligned[i] ?? store.fileAlignment(bookID: bookID, fileIndex: i)
        }
        let marks = assignChapterMarks(toc: toc, sentencesByFile: current.map { $0?.sentences ?? [] },
                                       verdicts: current.map { $0?.verdict ?? "" })
        for i in current.indices {
            guard var fa = current[i], fa.chapterMarks != marks[i] else { continue }
            fa.chapterMarks = marks[i]
            try? store.save(fa, bookID: bookID)
            current[i] = fa
        }

        let chapters = epubChapters(from: current, fileStartTimes: book.fileStartTimes,
                                    bookDuration: book.duration,
                                    detected: book.detectedChapters,
                                    fileDurations: book.fileDurations)
        await MainActor.run {
            guard var fresh = AudiobookLibraryStore.shared.book(id: bookID) else { return }
            if let epubFilename { fresh.epubFilename = epubFilename }
            fresh.epubChapters = chapters
            fresh.modifiedAt = Date()
            AudiobookLibraryStore.shared.update(fresh)
            AudiobookSession.shared.refreshFromStore()
        }
    }

    // MARK: - File parsing (`.epub` via ZIPFoundation+EPubParse; anything else → single block)

    /// `.epub` → unzip (ZIPFoundation) + `EPubParse.parse`. Anything else (`.txt` or otherwise)
    /// → ONE `EPubBook`-shaped single-block book (the whole file as one block, empty TOC, no
    /// DRM) built directly — `EPubParse` is ePub-specific and never touched for plain text.
    /// Shared by `attach` (the just-copied file) and `alignIfNeeded` (re-parsing the already-
    /// attached file already on disk). `internal` (not `private`) so the `.txt` path is
    /// directly unit-testable without ZIPFoundation.
    static func parseBookFile(at url: URL) throws -> EPubBook {
        if url.pathExtension.lowercased() == "epub" {
            let archive = try Archive(url: url, accessMode: .read)
            var entries: [String: Data] = [:]
            for entry in archive where entry.type == .file {
                var data = Data()
                _ = try archive.extract(entry) { data.append($0) }
                entries[entry.path] = data
            }
            return try EPubParse.parse(entries: entries)
        }
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw AttachError.unreadable
        }
        return EPubBook(blocks: [EPubBlock(text: text, sourceFile: url.lastPathComponent)], toc: [], drm: .none)
    }

    // MARK: - Block merge (the local-word-index fix — see file header)

    /// Merge adjacent `EPubBlock`s sharing a `sourceFile` into ONE `AlignmentCore.Block` (their
    /// texts joined with a space, in order). Same flattened token stream either way — this only
    /// changes `bookWordStart/bookWordEnd`'s reporting granularity from "local to one paragraph"
    /// to "local to the whole file," which `assembleSentences` needs to be able to trust them as
    /// slice bounds. Degrades gracefully (produces more, smaller merged blocks with a repeated
    /// `sourceFile`) if same-file blocks are ever non-contiguous — `EPubParse` always emits them
    /// contiguously (spine order), so that's a defensive fallback, not the expected path.
    static func mergeBlocksByFile(_ blocks: [EPubBlock]) -> [AlignmentCore.Block] {
        var merged: [AlignmentCore.Block] = []
        for b in blocks {
            if let last = merged.indices.last, merged[last].sourceFile == b.sourceFile {
                merged[last].text += " " + b.text
            } else {
                merged.append(AlignmentCore.Block(text: b.text, sourceFile: b.sourceFile))
            }
        }
        return merged
    }

    // MARK: - Sentence assembly (pure, unit-tested)

    /// Splits `text` (one epub source file's full merged block text — see `mergeBlocksByFile`,
    /// which keeps `matchedRanges`' word-index bounds valid against THIS SAME tokenization) into
    /// sentences, distributing each `matchedRanges` entry's `[start,end]` time linearly across
    /// the words it covers, and slicing `transcriptWords` (this audio file's ASR words,
    /// file-local) for the low-confidence ASR-fallback splice range. Sentences with zero timed
    /// words are DROPPED (front matter / narrator skips the aligner never placed). `matchedRanges`
    /// may span multiple source files (one alignment call covers the whole book) — filtered here
    /// to `sourceFile`.
    static func assembleSentences(
        text: String,
        sourceFile: String,
        matchedRanges: [AlignmentCore.Result.MatchedRange],
        transcriptWords: [WordTiming]
    ) -> [AlignedSentence] {
        let words = tokenizeWithRanges(text)
        guard !words.isEmpty else { return [] }

        var wordTimes = [WordTiming?](repeating: nil, count: words.count)
        var wordDirect = [Bool](repeating: false, count: words.count)
        for range in matchedRanges where range.sourceFile == sourceFile {
            let lo = max(0, range.bookWordStart)
            let hi = min(words.count, range.bookWordEnd)
            guard hi > lo else { continue }
            let count = hi - lo
            if range.wordTimes.count == count {
                // Exact per-word times from the aligner (2026-07-22 device fix: the old
                // linear re-distribution across the range drifted mid-range words by
                // SECONDS over natural pauses — median sentence-end lag ~1 s, p90 +5.6 s
                // measured on the real Steal f0 sidecar; the highlight trailed the voice).
                for k in 0..<count {
                    let wt = range.wordTimes[k]
                    wordTimes[lo + k] = WordTiming(word: words[lo + k].word, start: wt.start, end: wt.end)
                    wordDirect[lo + k] = wt.direct
                }
            } else {
                // Defensive fallback (hand-built fixtures / any future range without the
                // parallel array): the old linear distribution, all words counted direct.
                let span = range.end - range.start
                for k in 0..<count {
                    let t0 = range.start + span * Double(k) / Double(count)
                    let t1 = range.start + span * Double(k + 1) / Double(count)
                    wordTimes[lo + k] = WordTiming(word: words[lo + k].word, start: t0, end: t1)
                    wordDirect[lo + k] = true
                }
            }
        }

        let starts = sentenceStartWordIndices(words: words, text: text)
        var sentences: [AlignedSentence] = []
        for (i, s) in starts.enumerated() {
            let e = i + 1 < starts.count ? starts[i + 1] : words.count
            guard e > s else { continue }
            let timed = (s..<e).compactMap { wordTimes[$0] }
            guard !timed.isEmpty else { continue }   // fully inside an unmatched span — drop
            let sentenceText = String(text[words[s].range.lowerBound..<words[e - 1].range.upperBound])
            let sStart = timed.first!.start
            let sEnd = timed.last!.end
            // DIRECT-matched fraction (2026-07-22, with the exact-times fix): an
            // interpolated word is a guess, not a match — a sentence that's mostly
            // guesses should fall back to ASR text, which timed-count never captured.
            let direct = (s..<e).filter { wordDirect[$0] && wordTimes[$0] != nil }.count
            let confidence = Double(direct) / Double(e - s)
            let asrRange = transcriptIndexRange(transcriptWords, start: sStart, end: sEnd)
            sentences.append(AlignedSentence(
                text: sentenceText, start: sStart, end: sEnd,
                wordStart: asrRange.lowerBound, wordEnd: asrRange.upperBound,
                confidence: confidence, words: timed, sourceFile: sourceFile
            ))
        }
        return sentences
    }

    /// `text` split on whitespace runs, each token paired with its range IN `text` — same token
    /// boundaries as `AlignmentCore`'s own (private) whitespace tokenizer, so a `MatchedRange`'s
    /// word-index bounds line up with this array when `text` is the exact string fed to
    /// `AlignmentCore.align` as that block's `.text` (true after `mergeBlocksByFile`).
    private static func tokenizeWithRanges(_ text: String) -> [(word: String, range: Range<String.Index>)] {
        var out: [(word: String, range: Range<String.Index>)] = []
        var idx = text.startIndex
        while idx < text.endIndex {
            while idx < text.endIndex, text[idx].isWhitespace { idx = text.index(after: idx) }
            guard idx < text.endIndex else { break }
            let start = idx
            while idx < text.endIndex, !text[idx].isWhitespace { idx = text.index(after: idx) }
            out.append((String(text[start..<idx]), start..<idx))
        }
        return out
    }

    /// Word indices (into `words`) that BEGIN a sentence, via `NLTokenizer(.sentence)` over the
    /// REAL text — handles abbreviations/quotes/ellipses correctly (the same tool
    /// `CaptureMath.SentenceSnap` already relies on for spoken text, applied here directly to
    /// prose since the real punctuation is available). Always includes `0` for non-empty input.
    private static func sentenceStartWordIndices(
        words: [(word: String, range: Range<String.Index>)], text: String
    ) -> [Int] {
        guard !words.isEmpty else { return [] }
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var starts: Set<Int> = [0]
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            if let idx = words.firstIndex(where: { $0.range.lowerBound >= range.lowerBound }) {
                starts.insert(idx)
            }
            return true
        }
        return starts.sorted()
    }

    /// Transcript word-index range (into `words`, file-local ASR array) whose time spans overlap
    /// `[start, end]` — the ASR-fallback splice range for a sentence. Empty range when nothing
    /// overlaps. Mirrors `FileTranscript.words(inWindow:)`'s overlap predicate, returning indices
    /// instead of the words themselves.
    static func transcriptIndexRange(_ words: [WordTiming], start: TimeInterval, end: TimeInterval) -> Range<Int> {
        guard end > start, !words.isEmpty else { return 0..<0 }
        var lo = -1, hi = -1
        for (i, w) in words.enumerated() where w.end > start && w.start < end {
            if lo == -1 { lo = i }
            hi = i
        }
        return lo == -1 ? 0..<0 : lo..<(hi + 1)
    }

    // MARK: - Chapter marks + epubChapters (pure — reused by attach / alignIfNeeded / receiveAlignments)

    /// For each `toc` entry (in order), the first `(fileIndex, sentenceIndex)` whose sentence's
    /// `sourceFile` matches — scanning `sentencesByFile` in order, and within a file, its
    /// sentences in order. Returns one `[ChapterMark]` per file (same count/order as
    /// `sentencesByFile`); a TOC entry with no match anywhere is skipped entirely (front matter
    /// the aligner never covered, or an epub-internal file this book's audio never reached).
    /// ONLY `aligned` files may claim a TOC entry (device catch, 2026-07-22: a REJECTED
    /// trilogy-sibling file still carries spurious matched sentences — on the real Steal
    /// pair, 6 front-matter TOC entries f0 couldn't claim were grabbed by rejected f1,
    /// planting phantom chapters with junk times in the book-2 region). `verdicts` runs
    /// parallel to `sentencesByFile`; anything but `aligned` contributes nothing.
    static func assignChapterMarks(toc: [EPubTOCEntry], sentencesByFile: [[AlignedSentence]],
                                   verdicts: [String]) -> [[ChapterMark]] {
        var marks = Array(repeating: [ChapterMark](), count: sentencesByFile.count)
        let aligned = AlignmentCore.Verdict.aligned.rawValue
        for entry in toc {
            for fileIdx in sentencesByFile.indices where verdicts.indices.contains(fileIdx) && verdicts[fileIdx] == aligned {
                if let si = sentencesByFile[fileIdx].firstIndex(where: { $0.sourceFile == entry.sourceFile }) {
                    marks[fileIdx].append(ChapterMark(title: entry.title, sentenceIndex: si))
                    break
                }
            }
        }
        return marks
    }

    /// Derive the book's `epubChapters` from every file's (possibly nil, if never aligned)
    /// `FileAlignment.chapterMarks` + its `sentences[].start`, offset by that file's GLOBAL start
    /// time, sorted, with durations filled in (`ChapterDetector.assemble`'s fixup: each chapter's
    /// duration = the next one's start minus its own, last capped to `bookDuration`) so the
    /// scoped mini-scrubber doesn't collapse to ~0. Pure — works identically for a fresh local
    /// `attach()`/`alignIfNeeded()` or a receiver's synced sidecars (no epub needed here, only
    /// what's already on disk).
    static func epubChapters(from fileAlignments: [FileAlignment?], fileStartTimes: [TimeInterval],
                             bookDuration: TimeInterval,
                             detected: [AudiobookChapter]? = nil,
                             fileDurations: [TimeInterval] = []) -> [AudiobookChapter] {
        var entries: [(title: String, start: TimeInterval, isSeparator: Bool?)] = []
        var alignedSpans: [(start: TimeInterval, end: TimeInterval)] = []
        for (i, fa) in fileAlignments.enumerated() {
            // Non-aligned files never contribute chapters, even if stale sidecars still
            // carry marks (same device catch as `assignChapterMarks` — belt and braces so
            // a receiver deriving from OLD synced sidecars is immune too).
            guard let fa, fa.verdict == AlignmentCore.Verdict.aligned.rawValue else { continue }
            let base = fileStartTimes.indices.contains(i) ? fileStartTimes[i] : 0
            let dur = fileDurations.indices.contains(i) ? fileDurations[i] : 0
            alignedSpans.append((base, dur > 0 ? base + dur : .greatestFiniteMagnitude))
            for mark in fa.chapterMarks where fa.sentences.indices.contains(mark.sentenceIndex) {
                entries.append((mark.title, base + fa.sentences[mark.sentenceIndex].start, nil))
            }
        }
        guard !entries.isEmpty else { return [] }
        // PARTIAL-MATCH MERGE (Tuur's trilogy question, 2026-07-22 + the locked
        // no-bad-info rule): the ePub TOC wins only INSIDE the files it aligned to.
        // A transcript-detected chapter whose start lies OUTSIDE every aligned file's
        // span (the other books of a multi-book audiobook) stays — hiding it would
        // imply those books have no chapters. Separators ride the same rule.
        for ch in detected ?? [] {
            // Half-open with a 1 s shrink at the top: a chapter starting AT an aligned
            // file's end boundary (== the next file's start, e.g. a "Book 2" separator)
            // belongs to the NEXT, unaligned file and must survive the merge.
            let inAligned = alignedSpans.contains { ch.start >= $0.start - 1 && ch.start < $0.end - 1 }
            if !inAligned { entries.append((ch.title, ch.start, ch.isSeparator)) }
        }
        return chaptersWithDurations(entries, bookDuration: bookDuration)
    }

    /// Stable-sort by start (explicit tie-break on original order — never relies on `sorted`'s
    /// stability alone, matching `AlignmentCore.lengthDescThenEarlier`'s own stated philosophy),
    /// then fill in each chapter's duration from the next one's start.
    private static func chaptersWithDurations(_ entries: [(title: String, start: TimeInterval, isSeparator: Bool?)],
                                              bookDuration: TimeInterval) -> [AudiobookChapter] {
        let ordered = entries.enumerated().sorted { a, b in
            a.element.start != b.element.start ? a.element.start < b.element.start : a.offset < b.offset
        }.map(\.element)
        var chapters = ordered.map { AudiobookChapter(title: $0.title, start: $0.start, duration: 0,
                                                      isSeparator: $0.isSeparator) }
        for i in chapters.indices {
            let end = i + 1 < chapters.count ? chapters[i + 1].start : max(bookDuration, chapters[i].start)
            chapters[i].duration = max(0, end - chapters[i].start)
        }
        return chapters
    }

    // MARK: - Misc

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
