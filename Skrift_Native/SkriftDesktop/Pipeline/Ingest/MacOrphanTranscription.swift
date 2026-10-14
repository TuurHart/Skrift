import Foundation
import SwiftData

/// The Mac's backstop for a memo stuck in `.transcribing` because the device that recorded it
/// is gone (C264, R75). The phone's launch recovery adopts such a memo too, but only when some
/// phone launches; the Mac sweeps on every reconcile, so the note never spins forever.
///
/// Who may adopt is the shared `OrphanedTranscribing` rule (another device's memo only after
/// 30 quiet minutes, C154/C97). On top of it, the Mac needs the synced AUDIO blob (the thing it
/// transcribes), and a `transcriptUserEdited` memo is never re-transcribed (C263): it is only
/// released from the spinner with its words untouched, as the phone does.
///
/// Adopting writes the RAW transcript back to the `Memo` exactly as the phone's
/// `runTranscription` would (body, confidence, markers, status, word timings); the Mac's
/// rated-note pipeline then treats it like any phone transcript. Rating still gates the
/// polish: an unrated orphan gets its words and nothing else.
@MainActor
enum MacOrphanTranscription {

    /// `rerun` = adopt and transcribe; `release` = user-edited, end the spinner only.
    struct Plan: Equatable {
        var rerun: [UUID] = []
        var release: [UUID] = []
    }

    /// Ids currently being transcribed by `adopt`, so an overlapping sweep never runs one twice.
    static var inFlight: Set<UUID> = []

    /// Pure discovery over the memos a sweep already fetched. `hasAudio` answers from the
    /// blob-free asset-kind index, so nothing heavy is touched here.
    static func plan(memos: [Memo], hasAudio: (UUID) -> Bool,
                     thisDevice: String, now: Date) -> Plan {
        var plan = Plan()
        var seen: Set<UUID> = []
        for memo in memos where memo.deletedAt == nil && seen.insert(memo.id).inserted {
            guard !memo.audioFilename.isEmpty,
                  OrphanedTranscribing.mayRecover(memo, thisDevice: thisDevice, now: now) else { continue }
            if memo.transcriptUserEdited {
                plan.release.append(memo.id)
            } else if !inFlight.contains(memo.id), hasAudio(memo.id) {
                plan.rerun.append(memo.id)
            }
        }
        return plan
    }

    /// C263: end the spinner on a user-edited orphan, words untouched. Returns how many moved.
    @discardableResult
    static func release(_ ids: [UUID], in context: ModelContext) throws -> Int {
        var count = 0
        for id in ids {
            guard let memo = fetchMemo(id, in: context), memo.transcriptStatus == .transcribing,
                  memo.transcriptUserEdited else { continue }
            let hasText = !(memo.transcript ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            memo.transcriptStatus = hasText ? .done : .failed
            count += 1
        }
        if count > 0 { try context.save() }
        return count
    }

    /// Transcribe each adopted memo from its synced audio blob and land the words. One at a time
    /// (model-bound). Every memo is re-checked right before landing: if its owner came back and
    /// finished, or somebody edited it meanwhile, the Mac's result is dropped.
    /// Returns how many memos got a transcript.
    @discardableResult
    static func adopt(_ ids: [UUID], in context: ModelContext, transcriber: any Transcribing,
                      thisDevice: String, now: @escaping () -> Date = Date.init) async -> Int {
        let todo = ids.filter { !inFlight.contains($0) }
        inFlight.formUnion(todo)
        defer { inFlight.subtract(todo) }
        var landed = 0
        for id in todo {
            guard let memo = fetchMemo(id, in: context), stillAdoptable(memo, thisDevice: thisDevice, now: now()),
                  let audio = audioBlob(id, in: context) else { continue }
            let ext = (memo.audioFilename as NSString).pathExtension
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("orphan_\(id.uuidString).\(ext.isEmpty ? "m4a" : ext)")
            let manifest = memo.metadata?.imageManifest ?? []
            do {
                try audio.write(to: url)
                defer { try? FileManager.default.removeItem(at: url) }
                let result = try await transcriber.transcribe(audioURL: url, imageManifest: manifest)
                guard let fresh = fetchMemo(id, in: context),
                      stillAdoptable(fresh, thisDevice: thisDevice, now: now()) else { continue }
                land(result, on: fresh, in: context)
                try context.save()
                if fresh.transcriptStatus == .done { landed += 1 }
            } catch {
                AppLog.cloudkit.error("orphan transcription FAILED for \(id, privacy: .public): \(error)")
            }
        }
        return landed
    }

    /// Write a transcription result onto the memo, the way the phone's `runTranscription` does.
    static func land(_ result: TranscriptionResult, on memo: Memo, in context: ModelContext) {
        let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let manifest = memo.metadata?.imageManifest ?? []
        memo.transcript = text.isEmpty ? nil : BodyV2.committed(BodyV2.Input(
            text: result.text, words: result.wordTimings, manifest: manifest,
            source: result.wordTimings.isEmpty ? .typed : .speech,
            clipStarts: MixedBundle.breakStarts(memo.metadata?.clipManifest ?? [])))
        memo.transcriptConfidence = result.confidence
        memo.transcriptMarkersInjected = result.markersInjected
        memo.transcriptStatus = text.isEmpty ? .failed : .done
        guard !result.wordTimings.isEmpty, let data = try? JSONEncoder().encode(result.wordTimings) else { return }
        let memoID = memo.id
        let kind = MemoAsset.Kind.wordTimings
        let existing = try? context.fetch(FetchDescriptor<MemoAsset>(
            predicate: #Predicate { $0.memoID == memoID && $0.kind == kind }))
        if let wt = existing?.first {
            wt.blob = data
            wt.byteCount = data.count
        } else {
            // The phone's sidecar name (`WordTimingsStore.filename(for:)`).
            context.insert(MemoAsset(memoID: memoID, kind: kind, filename: "wt_\(memoID.uuidString).json", blob: data))
        }
    }

    private static func stillAdoptable(_ memo: Memo, thisDevice: String, now: Date) -> Bool {
        memo.deletedAt == nil && !memo.transcriptUserEdited
            && OrphanedTranscribing.mayRecover(memo, thisDevice: thisDevice, now: now)
    }

    private static func fetchMemo(_ id: UUID, in context: ModelContext) -> Memo? {
        var d = FetchDescriptor<Memo>(predicate: #Predicate { $0.id == id })
        d.fetchLimit = 1
        return (try? context.fetch(d))?.first
    }

    private static func audioBlob(_ id: UUID, in context: ModelContext) -> Data? {
        let kind = MemoAsset.Kind.audio
        let rows = (try? context.fetch(FetchDescriptor<MemoAsset>(
            predicate: #Predicate { $0.memoID == id && $0.kind == kind }))) ?? []
        return rows.first(where: { !$0.blob.isEmpty })?.blob
    }
}
