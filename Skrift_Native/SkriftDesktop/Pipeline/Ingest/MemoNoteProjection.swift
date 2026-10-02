import Foundation
import SwiftData

/// An UNRATED memo, projected into the type the note view already renders.
///
/// **Why this exists.** The RATING is what pipelines a memo (`MemoCloudIngest`
/// gates on `significance > 0`), so an unrated `Memo` has no `PipelineFile` — and
/// `NoteDisplayView`/`NoteProperties`/`NoteBody` are all typed to one. The first two
/// attempts at "open an unrated note" answered that by building a SECOND renderer
/// that imitated the note anatomy; Tuur rejected both ("make an unrated note
/// identical to other notes"), and rightly — a copy drifts the moment either side
/// changes.
///
/// So: no second renderer, and no new view-model either. `PipelineFile` already IS
/// the shape the note view reads, so the memo is projected INTO one that is
/// **never inserted into the pipeline store**. The note view cannot tell the
/// difference — an unrated note IS a normal note — while nothing enters the queue,
/// so "the rating IS the flag" holds by construction rather than by policing.
///
/// **Deliberately faithful, not improved.** The projection maps the memo through
/// `MemoCloudIngest.metadataJSON` — the exact blob a real ingest would have written —
/// so the chips row, the capture blocks and the book-quote styling derive through the
/// same accessors a pipelined note uses. Matching what a normal note ACTUALLY does is the
/// whole point: a projection that quietly did better would read as a difference.
enum MemoNoteProjection {

    /// Where an unrated note's media is materialised. **Caches** on purpose: it is
    /// derived data — every byte is reproducible from the synced `MemoAsset` blobs —
    /// so the OS may evict it and the next open simply rebuilds it. Rating the note
    /// makes the real ingest folder, at which point this copy is dropped.
    static func mediaFolder(for id: UUID) -> URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent(Bundle.main.bundleIdentifier ?? "Skrift", isDirectory: true)
            .appendingPathComponent("UnratedMedia", isDirectory: true)
            .appendingPathComponent(id.uuidString, isDirectory: true)
    }

    /// Drop a note's materialised media — call when it pipelines (the real ingest
    /// folder takes over) or is trashed.
    static func discardMedia(for id: UUID) {
        try? FileManager.default.removeItem(at: mediaFolder(for: id))
    }

    /// Build the transient `PipelineFile` for `memo`. Never inserted into a
    /// `ModelContext` — it is a view-model that happens to already have a type.
    /// `id` is the memo UUID (the contract spine), which is also what lets the
    /// existing Mac→phone write-back resolve the memo from it
    /// (`MacCloudWriteBack.memoID(for:)`).
    static func file(for memo: Memo) -> PipelineFile {
        let kind = SourceKind.of(memo)
        let pf = PipelineFile(id: memo.id.uuidString,
                              filename: memo.audioFilename,
                              path: "",          // filled by `materialiseMedia` — the blobs are
                                                 // already synced; only the FILES are missing
                                                 // until then (see that method).
                              size: 0,
                              sourceType: sourceType(for: kind),
                              uploadedAt: memo.recordedAt)
        // The marker the Mac row classifier (`PipelineFile.sourceDescriptor`) reads back.
        if kind == .video { pf.mediaSource = "video" }
        if kind == .typedNote { pf.mediaSource = "typed" }
        if kind == .captureImage, memo.sharedContent == nil { pf.mediaSource = MemoMetadata.Source.image }
        pf.transcript = memo.transcript
        pf.enhancedTitle = memo.title
        pf.tags = memo.tags
        // `significance` is OPTIONAL on PipelineFile and 0-means-unrated on Memo — an
        // unrated note must arrive at the circles as "nothing picked", not as a hard 0.
        pf.significance = memo.significance > 0 ? memo.significance : nil
        pf.locked = memo.locked
        pf.remindAt = memo.remindAt
        pf.imageOCRText = MemoCloudIngest.ocrText(for: memo)
        // The SAME blob a real ingest writes → place/weather/daypart chips, the capture
        // banner + shared-content block, and the audiobook quote card all derive through
        // the identical accessors a pipelined note uses.
        pf.audioMetadataJSON = MemoCloudIngest.metadataJSON(for: memo)
        // Only the transcribe step can be truthfully claimed (the phone did it). The rest
        // are pending because they genuinely haven't run — which is also what keeps the
        // title chooser away (it needs a `titleSuggested` the Mac hasn't produced).
        pf.transcribeStatus = memo.transcriptStatus == .done ? .done : .pending
        return pf
    }

    /// Give the projection its MEDIA, so an unrated note plays, shows its photos and
    /// karaokes like any other note.
    ///
    /// Nothing here is a download: every byte already synced as a `MemoAsset` blob —
    /// what an unrated note lacks is FILES, because materialisation happens at ingest
    /// and the rating is what triggers ingest. So this writes the blobs into the
    /// cache folder and points the projection at them; the player, `NoteBody`'s
    /// `[[img_NNN]]` resolver and the karaoke highlight then work through their
    /// ordinary paths, with no special cases anywhere in the view.
    ///
    /// `fetchAssets` is LAZY (the `MemoPhotoMaterializer` rule): fetching asset rows
    /// pulls every blob into memory, so it's called only when a file is actually
    /// missing. A second open of the same note touches no blobs at all.
    static func materialiseMedia(for memo: Memo, into pf: PipelineFile,
                                 fetchAssets: () -> [MemoAsset]) {
        let fm = FileManager.default
        let folder = mediaFolder(for: memo.id)
        // Memoise: three call sites below, but the rows (and their blobs) are heavy —
        // fetch at most ONCE per open, and only if something is genuinely missing.
        var cached: [MemoAsset]?
        func assets() -> [MemoAsset] {
            if let cached { return cached }
            let rows = fetchAssets()
            cached = rows
            return rows
        }

        // Audio → `<folder>/original.<ext>`, which also makes `workingFolder` resolve
        // to `<folder>` for the photo paths below (captures point AT the folder).
        let ext = (memo.audioFilename as NSString).pathExtension
        let audioURL = folder.appendingPathComponent("original." + (ext.isEmpty ? "m4a" : ext))
        let wantsAudio = !memo.audioFilename.isEmpty || memo.duration > 0
        if wantsAudio, !fm.fileExists(atPath: audioURL.path) {
            if let blob = assets().first(where: { $0.kind == MemoAsset.Kind.audio })?.blob {
                try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
                try? blob.write(to: audioURL)
            }
        }
        if fm.fileExists(atPath: audioURL.path) {
            pf.path = audioURL.path
        } else if pf.sourceType == .capture {
            // No audio to anchor on — a capture's working folder IS its path.
            try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
            pf.path = folder.path
        }

        // Photos: the SAME healer the pipeline uses, now that `workingFolder` exists.
        if pf.workingFolder != nil {
            MemoPhotoMaterializer.materializeMissing(memo: memo, pf: pf, fetchAssets: assets)
        }

        // Karaoke: word timings are a synced blob too, and they're TRANSCRIPTION
        // output — not polish — so an unrated note is entitled to read along.
        //
        // Cached to disk like the audio, and keyed on the FILE's existence rather than
        // its contents: a fresh projection always starts with nil timings, so checking
        // the model would re-fetch the (heavy) asset rows on every single open. An
        // EMPTY file is the "already looked, this note has none" marker. Only audio
        // memos can have timings at all, so nothing else even makes a folder.
        if wantsAudio {
            let timingsURL = folder.appendingPathComponent("word_timings.json")
            if fm.fileExists(atPath: timingsURL.path) {
                let onDisk = (try? Data(contentsOf: timingsURL)) ?? Data()
                pf.wordTimingsJSON = onDisk.isEmpty ? nil : onDisk
            } else {
                let blob = assets().first(where: { $0.kind == MemoAsset.Kind.wordTimings })?.blob
                try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
                try? (blob ?? Data()).write(to: timingsURL)
                pf.wordTimingsJSON = (blob?.isEmpty == false) ? blob : nil
            }
        }
    }

    /// `SourceKind` → the coarse `PipelineFile.sourceType` the note view branches on.
    /// A video and an audiobook quote are both audio; the finer distinction rides
    /// `mediaSource` / the metadata blob, exactly as it does on an ingested row.
    private static func sourceType(for kind: SourceKind) -> SourceType {
        switch kind {
        case .appleNote, .typedNote: return .note   // text-born notes render the note path
        case .captureURL, .captureImage, .captureText, .captureFile, .captureOther: return .capture
        case .voiceMemo, .video, .audiobookQuote: return .audio
        }
    }

    /// Push every field the note view can edit back onto the `Memo`, which is the real
    /// record. Returns true when something actually changed (so the caller only saves
    /// on a real edit).
    ///
    /// Title and transcript go STRAIGHT onto the memo rather than through
    /// `MacCloudEditSync` — that carrier writes a `MemoEnhancement`, i.e. "the Mac
    /// polished this", which would be a lie about a note the Mac has never processed.
    /// Tags and significance are written here TOO, even though `NoteProperties` also
    /// mirrors them via `MacCloudMetaSync`: that mirror is gated on
    /// `cloudKitMacSyncEnabled`, and an edit to an open note must land on the memo
    /// whether or not sync happens to be on. Both paths compare before writing, so the
    /// overlap is a no-op rather than a fight.
    @discardableResult
    static func writeBack(_ pf: PipelineFile, to memo: Memo) -> Bool {
        var contentChanged = false
        let title = pf.enhancedTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        let newTitle = (title?.isEmpty ?? true) ? nil : title
        if memo.title != newTitle { memo.title = newTitle; contentChanged = true }
        // The body binding writes to `transcript` on a projection (there is no
        // `sanitised`/`enhancedCopyedit` to take precedence), so this is the raw
        // transcript — the phone's own field. A hand-edit is exactly what
        // `transcriptUserEdited` means, and it lifts the note over the trust gate
        // the same way an edit on the phone does.
        if let body = pf.transcript, body != memo.transcript {
            memo.transcript = body
            memo.transcriptUserEdited = true
            contentChanged = true
        }
        if memo.tags != pf.tags { memo.tags = pf.tags; contentChanged = true }
        // Rating an unrated note through the ordinary circles is what pipelines it —
        // the flag stays the rating, stated by the user on the note itself. CLEARING
        // it (re-tap the lit circle → nil) has to travel too: a control that only
        // works one way is worse than no control. `Memo.significance` is
        // non-optional, so "not rated" is 0. Tracked APART from content: a rating is
        // a judgment, not an investment.
        var ratingChanged = false
        let rating = pf.significance ?? 0
        if memo.significance != rating { memo.significance = rating; ratingChanged = true }
        // A CONTENT edit is a touch — `markEdited` (editedAt + the keptAt clock bump),
        // the same one-clock rule as every phone edit site ("a user edit is also a
        // TOUCH"). This used to set `editedAt` alone, so typing in an unrated note
        // never restarted its fade clock — visible the moment typed notes were born
        // here (a note you are actively writing must not be quietly dying). A
        // rating-only change deliberately does NOT touch (markEdited's own contract:
        // "NOT from sync-status / significance changes").
        if contentChanged { memo.markEdited() }
        return contentChanged || ratingChanged
    }
}
