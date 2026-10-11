import Foundation
import SwiftData

/// Q333: puts ONE triaged Apple Note into Skrift. A rated note arrives RATED (the ball is the
/// consent, Q71), dated by its own creation date or "Date unknown" (Q141 / C76 / D18, never the
/// import day), carrying its Notes tags (folded into the library's spellings) and a typed-note
/// body. The row is built complete BEFORE it is inserted, and its synced `Memo` is authored here,
/// so the reconcile sweep can never author it first at a different rating or date (the race
/// `ArrivalPath` documents).
enum AppleNotesImporter {

    /// What the report needs to know about a note that did not map whole.
    struct Result {
        var file: PipelineFile
        var droppedMedia: NotesBodyDecoder.Media
    }

    @MainActor
    static func importNote(_ note: AppleNoteSummary,
                           decoded: NotesBodyDecoder.Decoded,
                           rating: Int,
                           libraryTags: [String],
                           outputDir: URL = AppPaths.audioOutputDirectory,
                           context: ModelContext,
                           cloudContext: ModelContext?) throws -> Result {
        // A retry (the first attempt saved the row but the answer never reached the triage file, or the
        // cloud half threw) reuses the row it already made: found by the Notes identifier.
        let noteID = note.id
        var existing = FetchDescriptor<PipelineFile>(predicate: #Predicate { $0.appleNoteID == noteID })
        existing.fetchLimit = 1
        if let pf = try context.fetch(existing).first {
            try authorMemo(for: pf, cloudContext: cloudContext)
            return Result(file: pf, droppedMedia: dropped(from: decoded.media))
        }
        let id = UUID().uuidString
        let filename = shortTitle(IngestService.sanitizeTitle(decoded.title)) + ".md"
        let folder = outputDir.appendingPathComponent("\(id)_\(filename)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let dest = folder.appendingPathComponent("original.md")
        try Data(decoded.markdown.utf8).write(to: dest)

        let pf = PipelineFile(id: id, filename: filename, path: dest.path, size: decoded.markdown.utf8.count,
                              sourceType: .note, uploadedAt: note.created ?? MemoDate.unknown)
        pf.transcript = BodyV2.committed(BodyV2.Input(text: decoded.markdown, source: .typed))
        pf.transcribeStatus = .done
        pf.enhancedTitle = decoded.title
        pf.isLocalImport = true
        pf.appleNoteID = note.id
        pf.significance = ThreeBallScale.value(forStep: rating)
        pf.tags = AppleNotesTags.map(decoded.tags, library: libraryTags)
        context.insert(pf)
        do { try context.save() } catch {
            context.delete(pf)
            try? FileManager.default.removeItem(at: folder)   // no orphan folder for the retry to trip over
            throw error
        }

        try authorMemo(for: pf, cloudContext: cloudContext)
        return Result(file: pf, droppedMedia: dropped(from: decoded.media))
    }

    /// The import folder name carries at most this many characters of the title (the full title
    /// lives on `enhancedTitle`), so a very long first line cannot overrun the filesystem's name limit.
    static let maxFolderTitle = 80

    static func shortTitle(_ sanitised: String) -> String {
        guard sanitised.count > maxFolderTitle else { return sanitised }
        let cut = String(sanitised.prefix(maxFolderTitle)).trimmingCharacters(in: CharacterSet(charactersIn: "- ."))
        return cut.isEmpty ? "note" : cut
    }

    @MainActor
    private static func authorMemo(for pf: PipelineFile, cloudContext: ModelContext?) throws {
        guard let cloudContext else { return }
        if let memo = try MacMemoAuthor.author(for: pf, audioURL: nil, into: cloudContext) {
            memo.tags = pf.tags
        }
        try cloudContext.save()
    }

    /// Pictures, drawings, scans, tables, files and audio are NOT copied out of Notes yet: the report
    /// says so per note (`droppedMedia`) instead of dropping them quietly.
    static func dropped(from media: NotesBodyDecoder.Media) -> NotesBodyDecoder.Media {
        var dropped = media
        dropped.checklistItems = 0; dropped.checklistDone = 0; dropped.links = 0
        return dropped
    }

    /// Changes the rating of a note already in Skrift (a second tap on another ball).
    @MainActor
    static func rerate(_ file: PipelineFile, rating: Int) {
        file.significance = ThreeBallScale.value(forStep: rating)
    }
}
