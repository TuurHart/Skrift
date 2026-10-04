import Foundation

/// The ONE builder of a `CompilerInput` (Q155, C196, C81, R37). Both exporters — the phone's
/// `MemoExporter` and the Mac's `PipelineFile.compilerInput` — call `CompilerInput.make`, so the
/// three rules that used to be written twice are written once:
///   • body source: the copy-edit when it has words, else the raw text (`workingBody`);
///   • the name-linked body: the shared `Sanitiser`, routed by `SpeakerTranscript.isConversation`, honouring the
///     note's `NameResolutions` (`linkBody`) — the phone's export ignored its picks (R37);
///   • voice: `cleaned` only when the exported body IS the copy-edit. A title-only enhancement
///     read `cleaned` on the phone and `raw` on the Mac (setexp-88); now `raw` on both.
/// Memo-link stems ride in the same call (`linkStems`), so a note's `[[memo:UUID|…]]` links
/// resolve the same way on both devices.
extension CompilerInput {

    /// The text a note's body is built from (C196 below sanitised): the copy-edit when it has
    /// words, else the raw transcript / annotation. `fromCopyedit` decides `voice:`.
    static func workingBody(raw: String?, copyedit: String?) -> (text: String, fromCopyedit: Bool) {
        if let c = copyedit, !c.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return (c, true)
        }
        return (raw ?? "", false)
    }

    /// The name-linked form of `text` — the shared `Sanitiser`, the same routing the Mac's
    /// `BatchRunner` uses (a recording with ≥2 speaker headers → the conversation linker, D178),
    /// deleted people excluded, the note's unlink / pick decisions applied. `source` is the
    /// note's source type; a typed note or capture never takes the conversation linker.
    static func linkBody(_ text: String, source: NoteSourceType, people: [Person],
                         resolutions: NameResolutions = NameResolutions()) -> String {
        guard !text.isEmpty else { return text }
        let live = people.filter { !$0.isDeleted }
        guard !live.isEmpty else { return text }
        let never = Set(resolutions.unlinkedNames)
        if SpeakerTranscript.isConversation(text, source: source) {
            return Sanitiser.processConversation(text: text, people: live, neverLink: never,
                                                 namePicks: resolutions.namePicks).sanitised
        }
        return Sanitiser.process(text: text, people: live, neverLink: never,
                                 namePicks: resolutions.namePicks).sanitised
    }

    /// Build the Compiler's input. `raw` is the transcript (or a capture's annotation),
    /// `copyedit` the polish, `linked` the name-linked body when the caller already holds it
    /// (the Mac's stored `sanitised`, which the user may have edited) — nil derives it here
    /// from `workingBody` + `linkBody`. `spoken` = the words were said (false → `written`).
    static func make(filename: String,
                     raw: String?,
                     copyedit: String?,
                     linked: String?? = nil,
                     people: [Person] = [],
                     resolutions: NameResolutions = NameResolutions(),
                     title: String?,
                     summary: String?,
                     tags: [String],
                     significance: Double?,
                     sourceType: NoteSourceType,
                     mediaSource: String?,
                     metadata: CompilerMetadata?,
                     sharedContent: SharedContent?,
                     rawRecordedAt: String?,
                     destination: NoteDestination,
                     spoken: Bool,
                     kind: SourceKind? = nil,
                     linkStems: [UUID: String] = [:]) -> CompilerInput {
        let work = workingBody(raw: raw, copyedit: copyedit)
        let sanitised: String? = {
            if let given = linked { return given }
            // Only words that were SPOKEN can be a conversation: a phone typed note passes
            // `sourceType: .audio` with `spoken: false`, which must not route as one.
            let l = linkBody(work.text, source: spoken ? sourceType : .note,
                             people: people, resolutions: resolutions)
            return l.isEmpty ? nil : l
        }()
        var input = CompilerInput(
            filename: filename,
            transcript: raw,
            sanitised: sanitised,
            enhancedCopyedit: work.fromCopyedit ? copyedit : nil,
            enhancedTitle: title,
            enhancedSummary: summary,
            tags: tags,
            significance: significance,
            sourceType: sourceType,
            mediaSource: mediaSource,
            metadata: metadata,
            sharedContent: sharedContent,
            rawRecordedAt: rawRecordedAt,
            destination: destination,
            voice: !spoken ? .written : (work.fromCopyedit ? .cleaned : .raw),
            kind: kind)
        input.setLinkStems(linkStems)
        return input
    }

    /// Memo-link stems: UUID → the linked note's exported stem. Empty → no resolver (links
    /// fall back to `[[<title snapshot>]]`).
    mutating func setLinkStems(_ stems: [UUID: String]) {
        if stems.isEmpty {
            memoLinkResolver = nil
        } else {
            memoLinkResolver = { stems[$0] }   // value capture — Sendable
        }
    }
}
