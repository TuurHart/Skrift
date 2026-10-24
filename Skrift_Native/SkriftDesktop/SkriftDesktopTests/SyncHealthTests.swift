import XCTest
import SwiftData
import CloudKit

/// Q485 (C155, R47, D48, D217/D218; mock `mocks/Q484-sync-health.html`): iCloud full or signed
/// out shows on the list at once, a waiting note is marked "Not synced yet", and a different
/// iCloud account stops syncing (the orphan sweep included) until the old account returns or he
/// copies the Mac's notes into the new one. Synthetic stores and injected CloudKit errors only.
@MainActor
final class SyncHealthTests: XCTestCase {

    private let note = UUID()
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: - injected export errors → state

    func testAQuotaErrorShowsTheBannerAtOnce() {
        var h = SyncHealth()
        h.noteChanged([note], at: t0)
        h.exportEnded(startedAt: t0.addingTimeInterval(1), error: CKError(.quotaExceeded))

        XCTAssertEqual(h.problem, .quotaFull)
        XCTAssertEqual(h.unsynced(now: t0.addingTimeInterval(2)), [note], "a problem marks the note without the grace")
        let b = try? XCTUnwrap(h.banner(unsyncedCount: 1, device: "this Mac"))
        XCTAssertEqual(b?.title, "iCloud is full")
        XCTAssertEqual(b?.line, "1 note hasn't synced. They're safe on this Mac and go up once iCloud has room.")
        XCTAssertEqual(b?.opensSheet, false)
        XCTAssertEqual(h.noteReason, "iCloud is full")
    }

    func testTheMirrorsBarePartialFailureReadsAsFull() {
        // FB13773922: the mirror posts a full iCloud as a partial failure with no per-item errors.
        let bare = NSError(domain: CKError.errorDomain, code: CKError.Code.partialFailure.rawValue)
        XCTAssertEqual(SyncHealth.classify(bare), .quotaFull)
        let signedOut = NSError(domain: CKError.errorDomain, code: CKError.Code.partialFailure.rawValue,
                                userInfo: [CKPartialErrorsByItemIDKey: ["r1": CKError(.notAuthenticated)]])
        XCTAssertEqual(SyncHealth.classify(signedOut), .signedOut)
        let wrapped = NSError(domain: NSCocoaErrorDomain, code: 134_400,
                              userInfo: [NSUnderlyingErrorKey: CKError(.quotaExceeded)])
        XCTAssertEqual(SyncHealth.classify(wrapped), .quotaFull)
    }

    func testANetworkErrorIsNotAProblemTheUserCanFix() {
        var h = SyncHealth()
        h.noteChanged([note], at: t0)
        h.exportEnded(startedAt: t0, error: CKError(.networkUnavailable))
        XCTAssertNil(h.problem)
        XCTAssertNil(h.banner(unsyncedCount: 1, device: "this Mac"), "a single waiting note never gets the banner")
        XCTAssertTrue(h.unsynced(now: t0.addingTimeInterval(30)).isEmpty, "still inside the minute")
        XCTAssertEqual(h.unsynced(now: t0.addingTimeInterval(61)), [note], "late: the pill and the note line")
        XCTAssertEqual(h.noteReason, "waiting for iCloud")
    }

    func testAnExportThatWorksClearsWhatItCarriedAndTheFailure() {
        var h = SyncHealth()
        let later = UUID()
        h.noteChanged([note], at: t0)
        h.exportEnded(startedAt: t0.addingTimeInterval(1), error: CKError(.quotaExceeded))
        h.noteChanged([later], at: t0.addingTimeInterval(20))

        h.exportEnded(startedAt: t0.addingTimeInterval(10), error: nil)

        XCTAssertNil(h.problem, "the next upload that works clears the banner")
        XCTAssertEqual(Set(h.pending.keys), [later], "a change made after the export started still waits")
    }

    func testSignedOutSaysSoAndIsNotASwitch() {
        var h = SyncHealth()
        h.accountSeen(.available(recordName: "_A"))
        h.accountSeen(.noAccount)
        XCTAssertEqual(h.problem, .signedOut)
        XCTAssertFalse(h.isStopped)
        XCTAssertEqual(h.banner(unsyncedCount: 0, device: "this iPhone")?.title, "Not signed in to iCloud")
        h.accountSeen(.available(recordName: "_A"))
        XCTAssertNil(h.problem)
    }

    // MARK: - account change → stopped

    func testAnAccountChangeStopsSyncingAndSaysSo() {
        var h = SyncHealth()
        h.accountSeen(.available(recordName: "_A"))
        XCTAssertFalse(h.isStopped, "the first account seen is adopted")

        h.accountSeen(.available(recordName: "_B"))

        XCTAssertTrue(h.isStopped)
        XCTAssertEqual(h.problem, .accountSwitched)
        let b = h.banner(unsyncedCount: 0, device: "this Mac")
        XCTAssertEqual(b?.title, "A different iCloud account")
        XCTAssertEqual(b?.opensSheet, true, "What now")
        XCTAssertFalse(b?.line.contains("deleted") ?? true, "Apple wipes the store on a switch: no 'Nothing here was deleted'")
        XCTAssertEqual(h.noteReason, "syncing is stopped")
    }

    func testTheOldAccountComingBackResumes() {
        var h = SyncHealth()
        h.accountSeen(.available(recordName: "_A"))
        h.accountSeen(.available(recordName: "_B"))
        h.accountSeen(.unknown)
        XCTAssertTrue(h.isStopped, "an unknown account proves nothing")
        h.accountSeen(.available(recordName: "_A"))
        XCTAssertFalse(h.isStopped)
    }

    func testCopyAdoptsTheNewAccountOnlyOnHisTap() {
        var h = SyncHealth()
        h.accountSeen(.available(recordName: "_A"))
        h.accountSeen(.available(recordName: "_B"))
        h.accountSeen(.available(recordName: "_B"))
        XCTAssertTrue(h.isStopped, "seeing the new account again never resumes on its own")
        h.adoptCurrentAccount()
        XCTAssertFalse(h.isStopped)
        XCTAssertEqual(h.syncedAccount, "_B")
        h.accountSeen(.available(recordName: "_A"))
        XCTAssertTrue(h.isStopped, "now the old one is the different account")
    }

    func testAStopSurvivesARelaunch() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "q485-\(UUID().uuidString)"))
        var h = SyncHealth()
        h.accountSeen(.available(recordName: "_A"))
        h.accountSeen(.available(recordName: "_B"))
        h.noteChanged([note], at: t0)
        SyncHealthStore.save(h, defaults)
        XCTAssertEqual(SyncHealthStore.load(defaults), h)
        XCTAssertTrue(SyncHealthStore.load(defaults).isStopped)
    }

    // MARK: - the What now sheet

    func testThePhoneSheetSendsHimBackToTheOldAccount() {
        var h = SyncHealth()
        h.noteChanged([note], at: t0)
        let w = h.whatNow(device: "this iPhone", deviceKind: "iPhone", notesHere: 0, settingsPath: "Settings")
        XCTAssertEqual(w.title, "Syncing is stopped")
        XCTAssertTrue(w.facts[0].hasPrefix("Your notes are in the iCloud account you used before. Sign back into it"))
        XCTAssertEqual(w.facts[1], "1 note made here hadn't synced yet, so it may be gone.")
        XCTAssertFalse(w.facts.joined().contains("still on"))
    }

    func testTheMacSheetCountsTheNotesStillHere() {
        let w = SyncHealth().whatNow(device: "this Mac", deviceKind: "Mac", notesHere: 48, settingsPath: "System Settings")
        XCTAssertEqual(w.facts.first, "Your 48 notes are still on this Mac.")
        XCTAssertEqual(w.facts.last, "To sync again, sign back into the iCloud account you used before, in System Settings › your name.")
        XCTAssertTrue(w.lead.hasPrefix("This Mac was syncing with a different iCloud account."))
    }

    // MARK: - the pill

    func testThePillReplacesProgressNeverAnErrorOrTwoVersions() {
        let progress = NoteCardModel.Pill(label: "Enhancing", kind: .progress)
        let error = NoteCardModel.Pill(label: "Failed", kind: .error)
        XCTAssertEqual(NoteCardModel.Pill.withSync(progress, unsynced: true), .notSynced)
        XCTAssertEqual(NoteCardModel.Pill.withSync(nil, unsynced: true), .notSynced)
        XCTAssertEqual(NoteCardModel.Pill.withSync(error, unsynced: true), error)
        XCTAssertEqual(NoteCardModel.Pill.withSync(.twoVersions, unsynced: true), .twoVersions)
        XCTAssertEqual(NoteCardModel.Pill.withSync(progress, unsynced: false), progress)
        XCTAssertEqual(NoteCardModel.Pill.notSynced.label, "Not synced yet")
    }

    func testAQuietRowCarriesThePill() {
        let memo = Memo(id: note, audioFilename: "m.m4a", recordedAt: t0, transcript: "Words.",
                        transcriptStatus: .done, transcriptConfidence: 0.9, significance: 0)
        let card = MacQuietCard.model(for: memo, selected: false, backlinked: [], conflicts: [], unsynced: [note])
        XCTAssertEqual(card.statusPill, .notSynced)
    }

    // MARK: - local saves → pending notes

    func testASaveNamesTheNotesItTouched() throws {
        let c = try ModelContainer(for: Memo.self, MemoAsset.self, MemoEnhancement.self, MemoEditHead.self,
                                   configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let ctx = ModelContext(c)
        let other = UUID()
        ctx.insert(Memo(id: note, audioFilename: "a.m4a", recordedAt: t0, transcript: "A.", transcriptStatus: .done,
                        transcriptConfidence: 0.9, significance: 0.6))
        ctx.insert(MemoEnhancement(memoID: other, copyedit: "B.", title: "B", enhancedByDeviceID: "mac", enhancedAt: t0))
        var saved: [PersistentIdentifier] = []
        let token = NotificationCenter.default.addObserver(forName: ModelContext.didSave, object: ctx, queue: nil) {
            saved += SyncHealthSaves.identifiers(in: $0)
        }
        defer { NotificationCenter.default.removeObserver(token) }
        try ctx.save()

        XCTAssertEqual(SyncHealthSaves.noteIDs(for: saved, in: ctx), [note, other])
    }

    // MARK: - a stop halts the orphan sweep (Q487)

    private func stores() throws -> (cloud: ModelContext, local: ModelContext) {
        let cloud = try ModelContainer(for: Memo.self, MemoAsset.self, MemoEnhancement.self, MemoEditHead.self,
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let local = try ModelContainer(for: PipelineFile.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return (ModelContext(cloud), ModelContext(local))
    }

    private func pass(_ s: (cloud: ModelContext, local: ModelContext), stopped: Bool, out: URL) -> ReconcileV2.PassOutcome {
        ReconcileV2.pass(cloud: s.cloud, local: s.local, context: V2.context(device: "mac-test", outputDir: out),
                         firstImportDone: true, syncStopped: stopped)
    }

    func testAStoppedPassTrashesNothingAndAuthorsNothing() throws {
        let s = try stores()
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("q485-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: out) }
        // Three phone notes reach the Mac; then the store changes account and two vanish
        // (≤ 2 orphans pass Q487's quarter rule, so only the stop protects them).
        let ids = (0..<3).map { _ in UUID() }
        for id in ids {
            s.cloud.insert(Memo(id: id, audioFilename: "memo_\(id.uuidString).m4a", recordedAt: t0,
                                transcript: "Words.", transcriptStatus: .done, transcriptConfidence: 0.9, significance: 0.6))
            s.cloud.insert(MemoAsset(memoID: id, kind: MemoAsset.Kind.audio, filename: "memo_\(id.uuidString).m4a",
                                     blob: Data("AUDIO".utf8)))
        }
        try s.cloud.save()
        pass(s, stopped: false, out: out)
        let rows = try s.local.fetch(FetchDescriptor<PipelineFile>())
        XCTAssertEqual(rows.count, 3)
        for id in ids.prefix(2) {
            for m in try s.cloud.fetch(FetchDescriptor<Memo>(predicate: #Predicate { $0.id == id })) { s.cloud.delete(m) }
        }
        try s.cloud.save()

        let stopped = pass(s, stopped: true, out: out)

        XCTAssertEqual(stopped.orphansTrashed, 0)
        XCTAssertEqual(stopped.authored, 0)
        XCTAssertTrue(try s.local.fetch(FetchDescriptor<PipelineFile>()).allSatisfy { $0.deletedAt == nil },
                      "another account's store never trashes the Mac's rows")
        XCTAssertEqual(pass(s, stopped: false, out: out).orphansTrashed, 2, "the same pass unstopped would have")
    }

    // MARK: - D218: the Mac copies its notes into the new account

    func testCopyPutsEveryLiveMacRowIntoTheNewAccount() throws {
        let s = try stores()
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("q485-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let audio = scratch.appendingPathComponent("take.m4a")
        try Data("AUDIO".utf8).write(to: audio)

        let row = PipelineFile(id: UUID().uuidString, filename: "take.m4a", path: audio.path, sourceType: .audio)
        row.isLocalImport = true
        row.transcript = "The kiln is booked on Thursday."
        row.enhancedCopyedit = "The kiln is booked for Thursday."
        row.enhancedTitle = "Kiln week"
        row.memoTitleIsHis = true
        row.tags = ["studio"]
        row.significance = 0.6
        row.locked = true
        let trashed = PipelineFile(id: UUID().uuidString, filename: "gone.m4a", path: audio.path, sourceType: .audio)
        trashed.deletedAt = t0
        for r in [row, trashed] { s.local.insert(r) }
        try s.local.save()

        XCTAssertEqual(ReconcileV2.AccountCopy.copy([row, trashed], into: s.cloud, deviceID: "mac-test", now: t0), 1)

        let id = try XCTUnwrap(UUID(uuidString: row.id))
        let memo = try XCTUnwrap(try s.cloud.fetch(FetchDescriptor<Memo>(predicate: #Predicate { $0.id == id })).first)
        XCTAssertEqual(memo.tags, ["studio"])
        XCTAssertEqual(memo.title, "Kiln week")
        XCTAssertTrue(memo.locked)
        XCTAssertEqual(memo.significance, 0.6)
        let polish = try s.cloud.fetch(FetchDescriptor<MemoEnhancement>(predicate: #Predicate { $0.memoID == id })).first
        XCTAssertEqual(polish?.copyedit, "The kiln is booked for Thursday.")
        XCTAssertEqual(try s.cloud.fetchCount(FetchDescriptor<MemoAsset>(predicate: #Predicate { $0.memoID == id })), 1, "the audio")
        XCTAssertNotNil(row.syncedSourceEditedAt, "the row counts as linked, so no sweep calls it an orphan")
        XCTAssertEqual(try s.cloud.fetchCount(FetchDescriptor<Memo>()), 1, "a trashed row is not copied")
        XCTAssertEqual(ReconcileV2.AccountCopy.copy([row], into: s.cloud, deviceID: "mac-test"), 0, "a second tap copies nothing twice")
    }
}
