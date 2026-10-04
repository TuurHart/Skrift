import Foundation
import SwiftData

/// "Add recording" on the Mac (D173, Q290): a take recorded from an open note's ⋯ lands on THAT
/// note instead of becoming a new one. The phone's shape (`MemoSaver.appendRecordingAsync`):
/// the clip's audio is spliced after the note's own by the shared `AudioClipMerge.append`, the
/// clip's words follow the body after a blank line, its word timings are shifted by the
/// precise base duration, and the combined transcript is marked user-edited (trusted, never
/// re-transcribed).
///
/// Two steps, so the order can't be got wrong:
/// 1. `spliceAudio` (off the main actor). It throws on ANY failure and then the note's audio,
///    text and synced memo are exactly as they were. The caller keeps the clip file.
/// 2. `land` writes the words + new duration onto the row and its synced `Memo` (the raw
///    transcript and the audio asset). The memo MUST get the combined transcript: the reconcile
///    sweep (`MemoCloudUpdate` path 3) copies `memo.transcript` over a row whose transcript
///    differs, which would otherwise erase the appended words from the Mac on the next sweep.
///
/// Pure over an explicit `ModelContext` (no container, no settings), so the host-less unit
/// bundle drives it (`MacAppendRecordingTests`).
enum MacAppendRecording {

    enum AppendError: Error, Equatable {
        /// The row has no audio file of its own (a typed note, a capture).
        case noAudio
    }

    /// Which open notes offer "Add recording": an audio note whose audio is on disk, unlocked,
    /// and not mid-transcription (a running pass would overwrite the appended words).
    static func isOffered(_ file: PipelineFile, locked: Bool) -> Bool {
        file.sourceType == .audio && !file.path.isEmpty && !locked
            && file.transcribeStatus != .processing
    }

    /// The phone's join: the existing body, a blank line, the new words. An empty side drops out.
    static func joined(_ existing: String?, _ addition: String) -> String {
        let a = (existing ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let b = addition.trimmingCharacters(in: .whitespacesAndNewlines)
        if a.isEmpty { return b }
        if b.isEmpty { return a }
        return a + "\n\n" + b
    }

    /// The clip's word timings moved past the note's own audio.
    static func shifted(_ timings: [WordTiming], by offset: TimeInterval) -> [WordTiming] {
        timings.map { WordTiming(word: $0.word, start: $0.start + offset, end: $0.end + offset) }
    }

    /// Step 1: splice `clip` after the row's audio, in place. Throws (and touches nothing) when
    /// the row has no audio, either file is unreadable, or the merge came out short.
    /// Synchronous and CPU-heavy: call it OFF the main actor.
    static func spliceAudio(path: String, clip: URL,
                            log: (String) -> Void = { _ in }) throws -> (merged: TimeInterval, base: TimeInterval) {
        guard !path.isEmpty, FileManager.default.fileExists(atPath: path) else { throw AppendError.noAudio }
        return try AudioClipMerge.append(base: URL(fileURLWithPath: path), addition: clip, log: log)
    }

    /// Step 2: land the take on the row and its synced memo (`memo` nil = a row with no memo yet;
    /// the sweep authors one later from the row, already combined).
    ///
    /// - `text`: the clip's words. Empty = an honest no-text append: the audio + duration still
    ///   land, the body is left alone.
    /// - `splice`: step 1's result; `base` is the offset the clip's timings move by.
    static func land(text: String, timings: [WordTiming],
                     splice: (merged: TimeInterval, base: TimeInterval),
                     on pf: PipelineFile, memo: Memo?, cloud: ModelContext?,
                     people: [Person], author: String,
                     deviceID: String = DeviceID.current(), now: Date = Date()) throws {
        let words = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let audioURL = URL(fileURLWithPath: pf.path)

        // ── the row ──
        if let size = (try? FileManager.default.attributesOfItem(atPath: pf.path))?[.size] as? Int {
            pf.size = size
        }
        pf.audioMetadataJSON = withDuration(splice.merged, in: pf.audioMetadataJSON)
        if !timings.isEmpty, !words.isEmpty {
            pf.wordTimings = pf.wordTimings + shifted(timings, by: splice.base)
        }
        if !words.isEmpty {
            // Body v2 (C10): the combined body is an edit — every picture keeps its place.
            pf.transcript = BodyV2.committed(BodyV2.Input(
                text: joined(pf.transcript, words), manifest: manifest(of: pf),
                source: .speech, userEdited: true))
            // A polished note shows its copy-edit; the new words go there too, so the body you
            // look at holds them (the Mac editor's own rule: write the layer that is shown).
            if let copy = pf.enhancedCopyedit,
               !copy.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                pf.enhancedCopyedit = joined(copy, words)
            }
            pf.transcriptUserEdited = true
            pf.transcribeStatus = .done
            // Re-link names + recompile over the new working body (no LLM).
            MemoCloudUpdate.resanitiseAndCompile(pf, people: people, author: author)
        }
        pf.lastActivityAt = now

        // ── the synced memo ──
        guard let memo, let cloud else { return }
        memo.duration = splice.merged
        if !words.isEmpty {
            memo.transcript = pf.transcript
            memo.transcriptUserEdited = true   // every device trusts the combined transcript
            memo.transcriptStatus = .done
        }
        let memoID = memo.id
        let assets = try cloud.fetch(FetchDescriptor<MemoAsset>(predicate: #Predicate { $0.memoID == memoID }))
        if let blob = try? Data(contentsOf: audioURL) {
            if let audio = assets.first(where: { $0.kind == MemoAsset.Kind.audio }) {
                audio.blob = blob
                audio.byteCount = blob.count
            } else {
                let name = memo.audioFilename.isEmpty ? pf.filename : memo.audioFilename
                cloud.insert(MemoAsset(memoID: memoID, kind: MemoAsset.Kind.audio, filename: name, blob: blob))
            }
        }
        if !words.isEmpty, let wt = assets.first(where: { $0.kind == MemoAsset.Kind.wordTimings }),
           let data = try? JSONEncoder().encode(pf.wordTimings) {
            wt.blob = data
            wt.byteCount = data.count
        }
        memo.markEdited(now)
        try cloud.save()
        // The polished body moved too: write it back now, as a Mac body edit does
        // (`MacCloudEditSync`), so the sweep can't revert the copy-edit to the cloud's older one.
        if !words.isEmpty, !(pf.enhancedCopyedit ?? "").isEmpty {
            try MacCloudWriteBack.upsert(for: pf, into: cloud, deviceID: deviceID, now: now,
                                         bodyOverride: Sanitiser.unlinkToSpoken(pf.bestBodyText, people: people))
        }
    }

    // MARK: - Privates

    /// The row's picture manifest (`image_manifest.json` in its working folder), so the body
    /// commit keeps every `[[img_NNN]]` where it is.
    private static func manifest(of pf: PipelineFile) -> [ImageManifestEntry] {
        guard let folder = pf.workingFolder,
              let data = try? Data(contentsOf: folder.appendingPathComponent("image_manifest.json")),
              let entries = try? JSONDecoder().decode([ImageManifestEntry].self, from: data) else { return [] }
        return entries
    }

    /// The metadata blob with `duration` set to `seconds` (number of seconds, the shape
    /// `MemoCloudIngest.metadataJSON` writes); every other key kept.
    static func withDuration(_ seconds: TimeInterval, in json: Data?) -> Data? {
        var obj = json.flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] } ?? [:]
        obj["duration"] = seconds
        return try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys])
    }
}
