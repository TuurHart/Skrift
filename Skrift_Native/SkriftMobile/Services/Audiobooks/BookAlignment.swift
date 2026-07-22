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
    /// Which ATTACHED TEXT (an entry in `Audiobook.attachedTextFilenames`) produced this
    /// sentence (schema 3, multi-text, 2026-07-22). Distinct from `sourceFile` (that text's OWN
    /// internal spine path) — `textFile` is the outer attached filename, the key
    /// `mergeSentences`/`textSummary`/`removeText` filter and merge by once a book can carry
    /// more than one text. Always non-nil on anything produced by `assembleSentences` when a
    /// real `textFile` is passed; the schema gate keeps pre-3 sidecars from ever decoding into
    /// a live `FileAlignment`, so a merged, on-disk sentence is never found with this nil.
    var textFile: String? = nil
}

/// One attached text's alignment outcome for ONE audio file (schema 3, pinned —
/// `LANES-2026-07-22D/BASE.md`). One entry per `(fileIndex, textFilename)` pair lives in that
/// file's `FileAlignment.sources`; `BookTextSummary` reads these to build the "Book text" sheet
/// without touching any sentence data.
struct AlignmentSource: Codable, Equatable, Sendable {
    /// The attached file in the book folder (an entry in `Audiobook.attachedTextFilenames`).
    var textFilename: String
    /// `EPubBook.title` (OPF `dc:title`) at alignment time — display name; nil → caller falls
    /// back to the filename (a `.txt` attach, or an ePub with no `dc:title`).
    var title: String?
    /// `AlignmentCore.Verdict.rawValue` for THIS text against THIS file specifically (distinct
    /// from `FileAlignment.verdict`, which is the file-level best-of across every source).
    var verdict: String
    /// `AlignmentCore.Result.coverageBook` for THIS file — fraction of this text's book words
    /// that got a time from this file's transcript (0…1).
    var coverage: Double
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
    /// 2→3 (2026-07-22): MULTI-TEXT — `sources` (per-attached-text verdict/coverage) and
    /// `AlignedSentence.textFile` (which attached text a sentence came from) are new; a v2
    /// sidecar has neither, so it reads as absent and every attached text re-aligns fresh on
    /// the book's next open (`alignIfNeeded` iterates `Audiobook.attachedTextFilenames` —
    /// `LANES-2026-07-22D/BASE.md`).
    static let currentSchema = 3

    var schema: Int = currentSchema
    /// Which file of the book this covers (`Audiobook.files` index).
    var fileIndex: Int
    /// `"<Int(coveredUpTo)>:<wordCount>"` of the transcript sidecar THIS alignment was computed
    /// against — `BookAlignmentStore.isFresh` recomputes this from the CURRENT local transcript
    /// and compares (see `signature(forTranscript:)`). ONE value shared by every attached text's
    /// contribution to this file (a property of the audio file's transcript, not of a text) — a
    /// transcript change re-aligns EVERY attached text against this file, not just one.
    var transcriptSignature: String
    /// SHA-256 hex of the MOST RECENTLY (re)aligned text's bytes for this file (diagnostic /
    /// future invalidation hook — not currently compared anywhere; text files themselves never
    /// sync). Schema 3: with multiple texts this is no longer "the" ePub's signature, just
    /// whichever text's pass touched this file last — harmless given it's unused.
    var epubSignature: String
    /// File-level verdict — the BEST across `sources` (aligned > partial > rejected), schema 3.
    /// One poorly-matching attached text must never regress what another, better-matching text
    /// already achieved for this file: `AlignedSentenceSource`/`epubChapters` both gate on this
    /// being `.aligned` before trusting/showing ANY of this file's `sentences` at all.
    var verdict: String
    var chapterMarks: [ChapterMark] = []
    /// Every attached text's sentences for this file, MERGED (schema 3) — collisions (time
    /// overlap between two different texts' sentences) resolved by higher `confidence`, tie by
    /// earlier attach order (`BookAlignmentRunner.mergeSentences`). Internally non-overlapping.
    var sentences: [AlignedSentence] = []
    /// One entry per attached text that has been aligned against this file (schema 3) — the
    /// "Book text" sheet's data source (`BookTextSummary`), and what `verdict` is derived from.
    var sources: [AlignmentSource] = []

    /// The staleness key: matches `signature(forTranscript:)` computed from the transcript
    /// sidecar this alignment was run against. A CURRENT transcript sidecar's signature
    /// differing from this means the book has been transcribed further since — stale.
    static func signature(forTranscript ft: FileTranscript) -> String {
        "\(Int(ft.coveredUpTo)):\(ft.words.count)"
    }

    /// This file's contribution to `AudiobookCloudSync`'s alignment change-signature
    /// (`"<fileIndex>:<verdict>:<sentenceCount>:<textCount>"`) — joined with "|" across a
    /// book's files there, mirroring `localTranscriptSignature`'s shape exactly. Schema 3 adds
    /// `textCount` (`sources.count`, 2026-07-22): the old three fields keep their exact prefix
    /// shape (minimal disruption to existing sync history), `textCount` adds visibility when the
    /// NUMBER of texts contributing to a file changes even if that happens to leave the other
    /// three scalars unchanged (a cheap aggregate signature, not a content hash — same
    /// imprecision `localTranscriptSignature` already accepts).
    func cloudSignaturePart() -> String {
        "\(fileIndex):\(verdict):\(sentences.count):\(sources.count)"
    }
}

/// The "Book text" sheet's data (schema 3, pinned — `LANES-2026-07-22D/BASE.md`) — produced by
/// `BookAlignmentRunner.textSummary(bookID:)`, a pure read over the on-disk sidecars.
struct BookTextSummary: Equatable, Sendable {
    struct PerText: Equatable, Sendable {
        var filename: String
        /// nil → caller shows the filename.
        var title: String?
        /// Sum of `spans`' lengths (the gap-bridged numbers — "one segment, not confetti").
        var coveredSeconds: TimeInterval
        /// GLOBAL book time, merged/sorted — the sheet's timeline bar draws these directly (the
        /// mock's variant B: real aligned spans, never a per-file approximation).
        var spans: [ClosedRange<TimeInterval>]
        /// 1-based audio files this text aligned (verdict `.aligned`) against.
        var fileNumbers: [Int]
    }
    /// Attach order (`Audiobook.attachedTextFilenames`'s order).
    var perText: [PerText]
    var totalCoveredSeconds: TimeInterval
    var bookDuration: TimeInterval
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

    /// Copy the picked file into the book folder (original filename kept), parse it, align it
    /// against every file with a covered transcript sidecar, MERGE its contribution into
    /// whatever's already on disk (schema 3 — additive, multi-text), derive `epubChapters`, and
    /// update the book (`epubFilenames`/`epubFilename`, `epubChapters`, `modifiedAt` bumped).
    /// Re-attaching an ALREADY-attached filename replaces only that text's own sentences/source
    /// entries (its position in `attachedTextFilenames` — and so its collision tie-break rank —
    /// is unchanged). Rejected-everywhere still writes sidecars (verdict recorded) — the UI
    /// decides what to tell the user from `AttachSummary`/the sidecars' verdicts.
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
            var perFile: [Int: FileAlignResult] = [:]
            var transcriptSigs: [Int: String] = [:]
            var aligned = 0, rejected = 0, total = 0
            for i in book.files.indices {
                let audioURL = folder.appendingPathComponent(book.files[i])
                let sig = transcriptStore.signature(forFileAt: audioURL)
                guard let ft = transcriptStore.load(bookID: bookID, fileIndex: i, expectedSignature: sig),
                      !ft.words.isEmpty else { continue }
                total += 1
                let fileResult = alignFile(ft: ft, against: alignBlocks, textFilename: filename)
                perFile[i] = fileResult
                transcriptSigs[i] = FileAlignment.signature(forTranscript: ft)
                if fileResult.verdict == .aligned { aligned += 1 }
                if fileResult.verdict == .rejected { rejected += 1 }
            }
            return AttachOutcome(perFile: perFile, toc: epubBook.toc, title: epubBook.title, epubSig: epubSig,
                                 transcriptSigs: transcriptSigs, aligned: aligned, rejected: rejected, total: total)
        }.value

        var order = book.attachedTextFilenames
        if !order.contains(filename) { order.append(filename) }

        await mergeAndFinish(
            bookID: bookID,
            results: [filename: outcome.perFile],
            titles: [filename: outcome.title],
            epubSignatures: [filename: outcome.epubSig],
            transcriptSignatures: outcome.transcriptSigs,
            attachOrder: order,
            precomputedTOC: [filename: outcome.toc],
            newlyAttachedFilename: filename
        )
        return AttachSummary(alignedFiles: outcome.aligned, rejectedFiles: outcome.rejected,
                             totalFiles: outcome.total)
    }

    private struct AttachOutcome: Sendable {
        var perFile: [Int: FileAlignResult]
        var toc: [EPubTOCEntry]
        var title: String?
        var epubSig: String
        var transcriptSigs: [Int: String]
        var aligned: Int
        var rejected: Int
        var total: Int
    }

    // MARK: Incremental re-align

    /// Cheap no-op-guarded re-align: no text attached, none of the attached texts' files present
    /// locally (a receiver device — text files never sync, only sidecars do; nothing to compute
    /// locally), or every file's sidecar already fresh ⇒ returns fast. Otherwise re-parses every
    /// LOCALLY-present attached text and re-runs alignment for the stale files only (schema 3:
    /// "stale" is a FILE-level, transcript-driven staleness — a stale file re-tries EVERY
    /// attached text against it, not just one), then reconciles chapter marks + `epubChapters`
    /// across the WHOLE book (not just the files touched this pass) so the "first TOC match
    /// wins, globally" invariant can't drift between files aligned now and files aligned earlier.
    static func alignIfNeeded(bookID: UUID) async {
        guard let book = await MainActor.run(body: { AudiobookLibraryStore.shared.book(id: bookID) }) else { return }
        let folder = BookTranscriptStore().folder(forBookID: bookID)
        var names = book.attachedTextFilenames
        if names.isEmpty {
            // RE-ADOPT (2026-07-22 Odyssey device report): builds before the Codable
            // persistence fix encoded Audiobook WITHOUT the attach fields, so a plain
            // relaunch forgot the attachment — while the attached file + sidecars still
            // sit in the book folder (attach copies the file there; removeText deletes
            // it, so a text file present on disk always means "attached"). Adopt what's
            // on disk and continue; the fresh-sidecar self-heal below then restores
            // `epubChapters` without recomputing anything. Alphabetical order — the
            // original attach order is unrecoverable, and order only tie-breaks
            // sentence collisions between multiple texts.
            names = orphanedAttachedTexts(inFolder: folder, audioFiles: book.files)
            guard !names.isEmpty else { return }
            let adopted = names
            await MainActor.run {
                guard var fresh = AudiobookLibraryStore.shared.book(id: bookID) else { return }
                fresh.epubFilenames = adopted
                fresh.epubFilename = adopted.first
                fresh.modifiedAt = Date()
                AudiobookLibraryStore.shared.update(fresh)
            }
            DevLog.log("bookAlign[\(bookID)] re-adopted orphaned attached texts: \(adopted)")
        }
        let localNames = names.filter { FileManager.default.fileExists(atPath: folder.appendingPathComponent($0).path) }
        guard !localNames.isEmpty else { return }

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
        let realigned: [String: TextAlignOutcome] = await Task.detached(priority: .utility) { () -> [String: TextAlignOutcome] in
            var out: [String: TextAlignOutcome] = [:]
            for textName in localNames {
                let url = folder.appendingPathComponent(textName)
                guard let epubBook = try? parseBookFile(at: url) else {
                    DevLog.log("bookAlign[\(bookID)] re-parse failed for \(textName) — skipping re-align")
                    continue
                }
                let alignBlocks = mergeBlocksByFile(epubBook.blocks)
                let epubSig = (try? Data(contentsOf: url)).map(sha256Hex) ?? ""
                var perFile: [Int: FileAlignResult] = [:]
                for i in staleIndices {
                    let audioURL = folder.appendingPathComponent(book.files[i])
                    let sig = transcriptStore.signature(forFileAt: audioURL)
                    guard let ft = transcriptStore.load(bookID: bookID, fileIndex: i, expectedSignature: sig),
                          !ft.words.isEmpty else { continue }
                    perFile[i] = alignFile(ft: ft, against: alignBlocks, textFilename: textName)
                }
                out[textName] = TextAlignOutcome(perFile: perFile, toc: epubBook.toc, title: epubBook.title, epubSig: epubSig)
            }
            return out
        }.value

        guard !realigned.isEmpty else { return }

        var transcriptSigs: [Int: String] = [:]
        for i in staleIndices {
            let audioURL = folder.appendingPathComponent(book.files[i])
            let sig = transcriptStore.signature(forFileAt: audioURL)
            if let ft = transcriptStore.load(bookID: bookID, fileIndex: i, expectedSignature: sig) {
                transcriptSigs[i] = FileAlignment.signature(forTranscript: ft)
            }
        }

        await mergeAndFinish(
            bookID: bookID,
            results: realigned.mapValues(\.perFile),
            titles: realigned.mapValues(\.title),
            epubSignatures: realigned.mapValues(\.epubSig),
            transcriptSignatures: transcriptSigs,
            attachOrder: names,
            precomputedTOC: realigned.mapValues(\.toc)
        )
    }

    private struct TextAlignOutcome: Sendable {
        var perFile: [Int: FileAlignResult]
        var toc: [EPubTOCEntry]
        var title: String?
        var epubSig: String
    }

    // MARK: - Text summary + removal (📖 multi-text, schema 3 — LANES-2026-07-22D/BASE.md)

    /// The "Book text" sheet's data — one call, pure assembly from the on-disk sidecars + the
    /// book record. `library` defaults to the live singleton; overridable for test isolation
    /// (mirrors `AudiobookCloudSync`'s DI pattern) — callers just write `textSummary(bookID:)`.
    /// nil when the book doesn't exist or has no attached text at all (the sheet's empty state).
    @MainActor
    static func textSummary(bookID: UUID, library: AudiobookLibraryStore = .shared) -> BookTextSummary? {
        guard let book = library.book(id: bookID) else { return nil }
        let names = book.attachedTextFilenames
        guard !names.isEmpty else { return nil }

        let store = BookAlignmentStore(directory: library.directory)
        let fileAlignments: [FileAlignment?] = book.files.indices.map { store.fileAlignment(bookID: bookID, fileIndex: $0) }
        let fileStarts = book.fileStartTimes

        var perText: [BookTextSummary.PerText] = []
        for name in names {
            var intervals: [ClosedRange<TimeInterval>] = []
            var fileNumbers: [Int] = []
            var title: String?
            for (i, fa) in fileAlignments.enumerated() {
                guard let fa else { continue }
                let src = fa.sources.first(where: { $0.textFilename == name })
                if let src {
                    if title == nil { title = src.title }
                    if src.verdict == AlignmentCore.Verdict.aligned.rawValue { fileNumbers.append(i + 1) }
                }
                // Spans/coverage count ONLY files this text ALIGNED (device catch
                // 2026-07-22, round 3: rejected trilogy-sibling files carry spurious
                // matched sentences — without this gate the bar sprinkled confetti
                // across the whole book and read 37% instead of ~21%).
                guard src?.verdict == AlignmentCore.Verdict.aligned.rawValue else { continue }
                let base = fileStarts.indices.contains(i) ? fileStarts[i] : 0
                for s in fa.sentences where s.textFile == name {
                    let lo = base + min(s.start, s.end), hi = base + max(s.start, s.end)
                    intervals.append(lo...hi)
                }
            }
            let spans = mergedSpans(intervals, gapBridge: 30)
            let covered = spans.reduce(0) { $0 + ($1.upperBound - $1.lowerBound) }
            perText.append(BookTextSummary.PerText(filename: name, title: title, coveredSeconds: covered,
                                                    spans: spans, fileNumbers: fileNumbers))
        }

        return BookTextSummary(perText: perText,
                               totalCoveredSeconds: perText.reduce(0) { $0 + $1.coveredSeconds },
                               bookDuration: book.duration)
    }

    /// Detach ONE text: strip its `sources`/sentences from every file's sidecar (other texts
    /// untouched), remove it from the book record (array + legacy-slot fixup —
    /// `detachedTextFields`), delete the file on disk, and re-derive chapters. A file left with
    /// zero remaining sources has its `transcriptSignature` cleared (`strippingText`) so a
    /// future `alignIfNeeded` retries every SURVIVING text against it — otherwise a file whose
    /// ONLY source was the removed text would look "fresh" forever with nothing in it.
    static func removeText(filename: String, bookID: UUID) async {
        guard let book = await MainActor.run(body: { AudiobookLibraryStore.shared.book(id: bookID) }) else { return }
        let folder = BookTranscriptStore().folder(forBookID: bookID)
        let store = BookAlignmentStore()

        var current: [FileAlignment?] = book.files.indices.map { store.fileAlignment(bookID: bookID, fileIndex: $0) }
        for i in current.indices {
            guard let fa = current[i] else { continue }
            let stripped = strippingText(filename, from: fa)
            guard stripped != fa else { continue }
            try? store.save(stripped, bookID: bookID)
            current[i] = stripped
        }

        let fields = detachedTextFields(removing: filename, from: book.attachedTextFilenames)
        current = await reconcileChapters(bookID: bookID, folder: folder,
                                          textFilenames: fields.epubFilenames ?? [], current: current)

        try? FileManager.default.removeItem(at: folder.appendingPathComponent(filename))

        let chapters = epubChapters(from: current, fileStartTimes: book.fileStartTimes,
                                    bookDuration: book.duration, detected: book.detectedChapters,
                                    fileDurations: book.fileDurations)
        await MainActor.run {
            guard var fresh = AudiobookLibraryStore.shared.book(id: bookID) else { return }
            fresh.epubFilenames = fields.epubFilenames
            fresh.epubFilename = fields.epubFilename
            fresh.epubChapters = chapters
            fresh.modifiedAt = Date()
            AudiobookLibraryStore.shared.update(fresh)
            AudiobookSession.shared.refreshFromStore()
        }
    }

    // MARK: - One-file alignment (transcript → AlignmentCore → sentences)

    private struct FileAlignResult: Sendable {
        var verdict: AlignmentCore.Verdict
        /// `AlignmentCore.Result.coverageBook` — feeds `AlignmentSource.coverage` (schema 3).
        var coverage: Double
        var sentences: [AlignedSentence]
    }

    /// Run `AlignmentCore.align` (defaults) for one audio file's transcript against one text's
    /// blocks, then assemble sentences per epub source file from the result — each stamped
    /// `textFile: textFilename` (schema 3) so the merge step can filter/replace by text.
    private static func alignFile(ft: FileTranscript, against alignBlocks: [AlignmentCore.Block],
                                  textFilename: String) -> FileAlignResult {
        let transcript = ft.words.map { AlignmentCore.Word(text: $0.word, start: $0.start, end: $0.end) }
        let result = AlignmentCore.align(transcript: transcript, book: alignBlocks)
        var sentences: [AlignedSentence] = []
        for block in alignBlocks {
            sentences += assembleSentences(text: block.text, sourceFile: block.sourceFile,
                                           matchedRanges: result.matchedRanges, transcriptWords: ft.words,
                                           textFile: textFilename)
        }
        return FileAlignResult(verdict: result.verdict, coverage: result.coverageBook, sentences: sentences)
    }

    // MARK: - Multi-text merge (schema 3 — pure, unit-tested)

    /// File-level verdict = the BEST across a file's `sources` (aligned > partial > rejected).
    /// One poorly-matching attached text must never regress what another, better-matching text
    /// already achieved for that file — `AlignedSentenceSource`/`epubChapters` both gate on the
    /// file-level verdict being `.aligned` before trusting/showing ANY of that file's sentences.
    static func bestVerdict(_ verdicts: [String]) -> String {
        let aligned = AlignmentCore.Verdict.aligned.rawValue
        let partial = AlignmentCore.Verdict.partial.rawValue
        if verdicts.contains(aligned) { return aligned }
        if verdicts.contains(partial) { return partial }
        return AlignmentCore.Verdict.rejected.rawValue
    }

    /// Merges `incoming` (one text's freshly-computed sentences for one file, every entry
    /// sharing `textFile`) into `keep` (that file's current sentences from OTHER texts, assumed
    /// mutually non-overlapping — the caller has already dropped this text's own previous
    /// entries from `keep`). Each incoming sentence either lands cleanly (no time overlap with
    /// anything in `keep`) or CONTESTS every `keep` entry it overlaps AT ONCE: it wins —
    /// displacing all of them — only if its `confidence` beats the toughest of them, tie broken
    /// by `textRank` (lower = earlier attach = tougher to beat). Never a partial swap: a losing
    /// incoming sentence can't blow a hole in another text's coverage for nothing in return.
    /// Deterministic (BASE.md's collision rule).
    static func mergeSentences(into keep: [AlignedSentence], adding incoming: [AlignedSentence],
                               textRank: [String: Int]) -> [AlignedSentence] {
        var result = keep
        for ns in incoming {
            let conflicts = result.indices.filter { result[$0].start < ns.end && ns.start < result[$0].end }
            guard !conflicts.isEmpty else { result.append(ns); continue }
            let maxConfidence = conflicts.map { result[$0].confidence }.max()!
            let tiedAtMax = conflicts.filter { result[$0].confidence == maxConfidence }
            let toughestRank = tiedAtMax.map { textRank[result[$0].textFile ?? ""] ?? Int.max }.min()!
            let nsRank = textRank[ns.textFile ?? ""] ?? Int.max
            let nsWins = ns.confidence > maxConfidence || (ns.confidence == maxConfidence && nsRank < toughestRank)
            guard nsWins else { continue }
            for idx in conflicts.sorted(by: >) { result.remove(at: idx) }
            result.append(ns)
        }
        return result
    }

    /// Merges ONE text's freshly-computed per-file result into `existing` (that file's current
    /// on-disk state, nil if this is the first text ever aligned against it): this text's own
    /// PREVIOUS contribution (`sources`/`sentences` tagged `textFilename`) is dropped wholesale
    /// and replaced by the fresh one (re-attaching the SAME filename "replaces only its own
    /// sentences" — BASE.md); other texts' entries are kept, collisions resolved by
    /// `mergeSentences`. The file-level `verdict` becomes the best-of across all `sources`. Pure
    /// — no I/O.
    static func mergedFileAlignment(
        existing: FileAlignment?, fileIndex: Int, textFilename: String, title: String?,
        verdict: AlignmentCore.Verdict, coverage: Double, sentences: [AlignedSentence],
        transcriptSignature: String, epubSignature: String, textRank: [String: Int]
    ) -> FileAlignment {
        var fa = existing ?? FileAlignment(fileIndex: fileIndex, transcriptSignature: transcriptSignature,
                                           epubSignature: epubSignature,
                                           verdict: AlignmentCore.Verdict.rejected.rawValue)
        let others = fa.sentences.filter { $0.textFile != textFilename }
        fa.sentences = mergeSentences(into: others, adding: sentences, textRank: textRank)
        fa.sources.removeAll { $0.textFilename == textFilename }
        fa.sources.append(AlignmentSource(textFilename: textFilename, title: title,
                                          verdict: verdict.rawValue, coverage: coverage))
        fa.verdict = bestVerdict(fa.sources.map(\.verdict))
        fa.transcriptSignature = transcriptSignature
        fa.epubSignature = epubSignature
        return fa
    }

    /// The inverse of `mergedFileAlignment` — strips ONE text's `sources`/`sentences` entries
    /// from `fa` (other texts, including their sentences/sources, untouched); the file-level
    /// `verdict` becomes the best-of whatever `sources` remain (`.rejected` if none do). A file
    /// left with zero sources has `transcriptSignature` cleared to `""` (never a real signature
    /// shape) so a future `alignIfNeeded` treats it as stale and retries every SURVIVING
    /// attached text against it — otherwise it would look permanently "fresh" with nothing in
    /// it. No-op (returns `fa` unchanged) when this text never touched this file.
    static func strippingText(_ textFilename: String, from fa: FileAlignment) -> FileAlignment {
        var fa = fa
        let touches = fa.sources.contains { $0.textFilename == textFilename }
            || fa.sentences.contains { $0.textFile == textFilename }
        guard touches else { return fa }
        fa.sources.removeAll { $0.textFilename == textFilename }
        fa.sentences.removeAll { $0.textFile == textFilename }
        if fa.sources.isEmpty {
            fa.verdict = AlignmentCore.Verdict.rejected.rawValue
            fa.transcriptSignature = ""
        } else {
            fa.verdict = bestVerdict(fa.sources.map(\.verdict))
        }
        return fa
    }

    /// The book-record fields to write after detaching `filename` from `names` (the book's
    /// CURRENT `attachedTextFilenames`, attach order): the legacy `epubFilename` slot always
    /// mirrors the FIRST remaining text (both nil once none remain) — BASE.md's "legacy slot
    /// fixup." Pure.
    static func detachedTextFields(removing filename: String, from names: [String]) -> (epubFilenames: [String]?, epubFilename: String?) {
        var remaining = names
        remaining.removeAll { $0 == filename }
        return remaining.isEmpty ? (nil, nil) : (remaining, remaining.first)
    }

    /// Merges `intervals` (any order) into sorted, non-overlapping `ClosedRange`s, bridging a
    /// gap of `gapBridge` seconds or less between consecutive kept intervals into one span (so a
    /// handful of narrator-skip-sized gaps reads as one segment, not confetti — the mock's
    /// stated behavior). `gapBridge: 0` simply coalesces true overlaps/adjacencies.
    static func mergedSpans(_ intervals: [ClosedRange<TimeInterval>], gapBridge: TimeInterval) -> [ClosedRange<TimeInterval>] {
        guard !intervals.isEmpty else { return [] }
        let sorted = intervals.sorted { $0.lowerBound < $1.lowerBound }
        var out: [ClosedRange<TimeInterval>] = [sorted[0]]
        for r in sorted.dropFirst() {
            let last = out[out.count - 1]
            if r.lowerBound <= last.upperBound + gapBridge {
                out[out.count - 1] = last.lowerBound...max(last.upperBound, r.upperBound)
            } else {
                out.append(r)
            }
        }
        return out
    }

    // MARK: - Chapter-mark reconciliation (shared tail for attach / alignIfNeeded)

    /// Merges freshly-computed per-`(fileIndex, textFilename)` alignment results into the book's
    /// on-disk sidecars (`mergedFileAlignment`, one call per touched `(file, text)` pair — texts
    /// processed in `attachOrder` so the collision tie-break is deterministic regardless of
    /// dictionary iteration order), saves whichever changed, reconciles chapter marks book-wide
    /// (`reconcileChapters`), rebuilds + persists `book.epubChapters`, optionally stamps the
    /// book's attached-text list (`attach` only — `newlyAttachedFilename`), bumps `modifiedAt`,
    /// and refreshes the live session. `results`/`titles`/`epubSignatures` are keyed by TEXT
    /// FILENAME (not file index); `transcriptSignatures` by file index (one value per file,
    /// shared by every text touching it — a property of the audio file's transcript).
    private static func mergeAndFinish(
        bookID: UUID,
        results: [String: [Int: FileAlignResult]],
        titles: [String: String?],
        epubSignatures: [String: String],
        transcriptSignatures: [Int: String],
        attachOrder: [String],
        precomputedTOC: [String: [EPubTOCEntry]] = [:],
        newlyAttachedFilename: String? = nil
    ) async {
        guard let book = await MainActor.run(body: { AudiobookLibraryStore.shared.book(id: bookID) }) else { return }
        let store = BookAlignmentStore()
        let folder = BookTranscriptStore().folder(forBookID: bookID)
        // Built by hand (not `Dictionary(uniqueKeysWithValues:)`) — `attachOrder` SHOULD be
        // unique by construction (`attach`'s append is duplicate-guarded), but a rank lookup
        // used only to break sentence-collision ties is never worth a crash over; first
        // occurrence wins on the (should-never-happen) duplicate.
        var textRank: [String: Int] = [:]
        for (offset, name) in attachOrder.enumerated() where textRank[name] == nil {
            textRank[name] = offset
        }

        var current: [FileAlignment?] = book.files.indices.map { store.fileAlignment(bookID: bookID, fileIndex: $0) }
        for textName in attachOrder {
            guard let perFile = results[textName] else { continue }
            for (i, result) in perFile {
                guard current.indices.contains(i) else { continue }
                current[i] = mergedFileAlignment(
                    existing: current[i], fileIndex: i, textFilename: textName,
                    title: titles[textName] ?? nil, verdict: result.verdict, coverage: result.coverage,
                    sentences: result.sentences,
                    transcriptSignature: transcriptSignatures[i] ?? current[i]?.transcriptSignature ?? "",
                    epubSignature: epubSignatures[textName] ?? current[i]?.epubSignature ?? "",
                    textRank: textRank)
            }
        }
        for fa in current.compactMap({ $0 }) {
            try? store.save(fa, bookID: bookID)
        }

        current = await reconcileChapters(bookID: bookID, folder: folder, textFilenames: attachOrder,
                                          current: current, precomputedTOC: precomputedTOC)

        let chapters = epubChapters(from: current, fileStartTimes: book.fileStartTimes,
                                    bookDuration: book.duration,
                                    detected: book.detectedChapters,
                                    fileDurations: book.fileDurations)
        // Pullable trace for chapter-source bugs (the Odyssey report was undiagnosable
        // from the devlog): TOC size per text, how many marks landed, what got derived.
        let markCount = current.reduce(0) { $0 + ($1?.chapterMarks.count ?? 0) }
        DevLog.log("bookAlign[\(bookID)] chapters: toc \(precomputedTOC.mapValues(\.count)) → \(markCount) marks → \(chapters.count) epub chapters")
        await MainActor.run {
            guard var fresh = AudiobookLibraryStore.shared.book(id: bookID) else { return }
            if let newlyAttachedFilename {
                var names = fresh.attachedTextFilenames
                if !names.contains(newlyAttachedFilename) { names.append(newlyAttachedFilename) }
                fresh.epubFilenames = names
                fresh.epubFilename = names.first
            }
            fresh.epubChapters = chapters
            fresh.modifiedAt = Date()
            AudiobookLibraryStore.shared.update(fresh)
            AudiobookSession.shared.refreshFromStore()
        }
    }

    /// Rebuilds `chapterMarks` for every file, book-wide, from EVERY text in `textFilenames`:
    /// re-parses each (to recover its TOC — `precomputedTOC` skips a re-parse for texts the
    /// caller already has in hand from this same pass) and calls `perTextChapterMarks` against
    /// ONLY that text's own sentences + own per-file source verdict, unioning the (remapped)
    /// results across texts (marks from different texts can't collide — each names a different,
    /// text-owned sentence). When a text's file ISN'T present locally (attached-text files never
    /// sync — only the sidecars do, so a receiver device can be missing some), its TOC can't be
    /// re-derived; that text's EXISTING on-disk marks are preserved unchanged rather than
    /// dropped, so a partial local re-align can never wipe-and-resync (`sendAlignments` is
    /// ungated) another device's chapters away. Saves whichever sidecars' marks changed.
    private static func reconcileChapters(
        bookID: UUID, folder: URL, textFilenames: [String], current: [FileAlignment?],
        precomputedTOC: [String: [EPubTOCEntry]] = [:]
    ) async -> [FileAlignment?] {
        var unioned = Array(repeating: [ChapterMark](), count: current.count)
        for textName in textFilenames {
            if let toc = precomputedTOC[textName] ?? (try? parseBookFile(at: folder.appendingPathComponent(textName)))?.toc {
                guard !toc.isEmpty else { continue }
                let sourceVerdicts = current.map { $0?.sources.first { $0.textFilename == textName }?.verdict ?? "" }
                let marks = perTextChapterMarks(forText: textName, toc: toc,
                                                fullSentencesByFile: current.map { $0?.sentences ?? [] },
                                                sourceVerdicts: sourceVerdicts)
                for i in marks.indices where unioned.indices.contains(i) { unioned[i].append(contentsOf: marks[i]) }
            } else {
                DevLog.log("bookAlign[\(bookID)] chapter reconcile: \(textName) not present locally — preserving its existing marks")
                for i in current.indices where unioned.indices.contains(i) {
                    guard let fa = current[i] else { continue }
                    for m in fa.chapterMarks where fa.sentences.indices.contains(m.sentenceIndex)
                                                  && fa.sentences[m.sentenceIndex].textFile == textName {
                        unioned[i].append(m)
                    }
                }
            }
        }

        var out = current
        let store = BookAlignmentStore()
        for i in out.indices {
            guard var fa = out[i], fa.chapterMarks != unioned[i] else { continue }
            fa.chapterMarks = unioned[i]
            try? store.save(fa, bookID: bookID)
            out[i] = fa
        }
        return out
    }

    /// One text's chapter marks against the FULL (multi-text) sentence array for each file:
    /// filters to `textFilename`'s own sentences before calling `assignChapterMarks` (unchanged)
    /// — its returned `sentenceIndex` is then LOCAL TO THAT FILTERED SUBARRAY, remapped here back
    /// to indices into `fullSentencesByFile` (what `ChapterMark.sentenceIndex` is always
    /// consumed against downstream, e.g. `epubChapters`'s `fa.sentences[mark.sentenceIndex]`).
    /// Gated on `sourceVerdicts` — THIS TEXT's own per-file verdict, not the file's merged
    /// best-of — so a text that came back rejected against a file never claims that file's TOC
    /// entries even when another, better text made the file's OVERALL verdict "aligned" (the
    /// phantom-chapters protection, generalized to multi-text). Pure — no I/O, no re-parsing;
    /// the caller supplies an already-parsed `toc`.
    static func perTextChapterMarks(forText textFilename: String, toc: [EPubTOCEntry],
                                    fullSentencesByFile: [[AlignedSentence]], sourceVerdicts: [String]) -> [[ChapterMark]] {
        var filteredByFile: [[AlignedSentence]] = []
        var originalIndex: [[Int]] = []
        for full in fullSentencesByFile {
            var filtered: [AlignedSentence] = []
            var idxMap: [Int] = []
            for (idx, s) in full.enumerated() where s.textFile == textFilename {
                filtered.append(s); idxMap.append(idx)
            }
            filteredByFile.append(filtered)
            originalIndex.append(idxMap)
        }
        let localMarks = assignChapterMarks(toc: toc, sentencesByFile: filteredByFile, verdicts: sourceVerdicts)
        return localMarks.indices.map { i in
            localMarks[i].compactMap { m in
                originalIndex[i].indices.contains(m.sentenceIndex)
                    ? ChapterMark(title: m.title, sentenceIndex: originalIndex[i][m.sentenceIndex])
                    : nil
            }
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

    /// Attachable text files (`.epub`/`.txt`) sitting in the book folder that aren't audio
    /// files — the disk is the durable truth for "what's attached" (`attach` copies the file
    /// in, `removeText` deletes it; nothing else ever puts a text file there). Used by
    /// `alignIfNeeded` to re-adopt an attachment a pre-persistence-fix build forgot.
    /// Sorted for determinism.
    static func orphanedAttachedTexts(inFolder folder: URL, audioFiles: [String]) -> [String] {
        let attachable: Set<String> = ["epub", "txt"]
        let audio = Set(audioFiles)
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return entries
            .filter { attachable.contains(URL(fileURLWithPath: $0).pathExtension.lowercased()) && !audio.contains($0) }
            .sorted()
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
        transcriptWords: [WordTiming],
        textFile: String? = nil
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
                confidence: confidence, words: timed, sourceFile: sourceFile, textFile: textFile
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
