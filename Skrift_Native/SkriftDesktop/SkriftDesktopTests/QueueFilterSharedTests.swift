import XCTest

/// Q282 (D167, C115, C61): a note is Done once PROCESSED, on phone, iPad and Mac — 'exported'
/// is the destination row's own state, never the Needs Work / Done filter. ONE shared
/// `QueueFilter.admits` decides chip membership; the Mac adapter (`MacListFilter.inChip`) only
/// supplies the facts. Synthetic notes only.
final class QueueFilterSharedTests: XCTestCase {

    private func memo(rated: Bool, locked: Bool = false) -> Memo {
        let m = Memo(audioFilename: "x.m4a", transcript: "some words", transcriptStatus: .done,
                     significance: rated ? 0.5 : 0)
        m.locked = locked
        return m
    }

    private func row(enhance: StepStatus = .pending, export: StepStatus = .pending,
                     id: String = UUID().uuidString) -> PipelineFile {
        let f = PipelineFile(id: id, filename: "x.m4a", sourceType: .audio, uploadedAt: Date())
        f.significance = 0.5
        f.transcript = "some words"
        f.steps = ProcessingSteps(transcribe: .done, sanitise: .done, enhance: enhance, export: export)
        return f
    }

    private func chips(_ admits: (QueueFilter) -> Bool) -> Set<QueueFilter> {
        Set(QueueFilter.allCases.filter(admits))
    }

    // MARK: - the one predicate

    func testTheTruthTable() {
        XCTAssertEqual(chips { $0.admits(rated: true, processed: false, locked: false) }, [.all, .needsWork])
        XCTAssertEqual(chips { $0.admits(rated: true, processed: true, locked: false) }, [.all, .done])
        XCTAssertEqual(chips { $0.admits(rated: true, processed: true, locked: true) }, [.all, .done],
                       "lock gates the eyes, not the pipeline")
        XCTAssertEqual(chips { $0.admits(rated: false, processed: false, locked: false) }, [.all, .notRated])
        XCTAssertEqual(chips { $0.admits(rated: false, processed: false, locked: true) }, [.all])
    }

    // MARK: - Mac pipeline rows: processed, never exported

    func testProcessedButNotExportedRowIsDone() {
        let f = MacListFilter()
        let r = row(enhance: .done, export: .pending)
        XCTAssertEqual(chips { c in var g = f; g.chip = c; return g.inChip(r) }, [.all, .done],
                       "D167: a processed note is Done before it is exported")
    }

    func testExportFlagNeverMakesARowDone() {
        let f = MacListFilter()
        let r = row(enhance: .pending, export: .done)
        XCTAssertEqual(chips { c in var g = f; g.chip = c; return g.inChip(r) }, [.all, .needsWork])
    }

    func testRowPolishedOnAnotherDeviceIsDone() {
        let id = UUID()
        let r = row(enhance: .pending, id: id.uuidString)
        let f = MacListFilter(processedIDs: [id])
        XCTAssertEqual(chips { c in var g = f; g.chip = c; return g.inChip(r) }, [.all, .done],
                       "the iPad's polish (a synced MemoEnhancement) makes the Mac row Done too")
    }

    func testProcessedIDsReadsOnlyPassesThatRan() {
        let ran = MemoEnhancement(memoID: UUID(), copyedit: "c", title: "t", summary: "s", processedAt: Date())
        let retitled = MemoEnhancement(memoID: UUID(), title: "only a title")
        XCTAssertEqual(MacListFilter.processedIDs(enhancements: [ran, retitled]), [ran.memoID])
    }

    // MARK: - stranded memos: no longer in every chip

    func testStrandedMemoAnswersNeedsWorkOrDone() {
        let waiting = memo(rated: true)
        let polished = memo(rated: true)
        let f = MacListFilter(processedIDs: [polished.id])
        XCTAssertEqual(chips { c in var g = f; g.chip = c; return g.inChip(waiting) }, [.all, .needsWork],
                       "an unprocessed stranded note must not sit in Done")
        XCTAssertEqual(chips { c in var g = f; g.chip = c; return g.inChip(polished) }, [.all, .done])
    }

    // MARK: - the Mac and the phone answer the same memo the same way

    func testMacMemoRowAgreesWithTheSharedMemoRule() {
        let memos = [memo(rated: true), memo(rated: true), memo(rated: false),
                     memo(rated: false, locked: true), memo(rated: true, locked: true)]
        let enhanced: Set<UUID> = [memos[1].id, memos[4].id]
        for c in QueueFilter.allCases {
            let mac = MacListFilter(chip: c, processedIDs: enhanced)
            for m in memos {
                XCTAssertEqual(mac.inChip(m), c.admits(m, enhancedIDs: enhanced), "\(c)")
            }
        }
    }
}
