import Foundation
import SwiftData

/// The pure state changes behind the Mac's "Split speakers" switch (Q87, signed mock
/// `mocks/Q86-split-speakers.html`). No engines and no UI, so the MLX-free test bundle pins them;
/// `ProcessingCoordinator` runs the slow parts (ASR, diarization, polish) around these.
enum SplitSpeakers {

    // MARK: state

    /// The switch is ON exactly when the note's words ARE turns. Not `diarizeRequested`: that is
    /// only the request, and it is withdrawn again when a run finds one voice.
    static func isSplit(_ pf: PipelineFile) -> Bool {
        pf.sourceType == .audio && SpeakerTranscript.isAttributed(pf.transcript)
    }

    /// C102 opt-in, per note. BatchRunner diarizes only a note that carries this.
    static func request(_ pf: PipelineFile) { pf.diarizeRequested = true }
    static func withdraw(_ pf: PipelineFile) { pf.diarizeRequested = false }

    // MARK: outcome

    enum Outcome: Equatable { case split, oneVoice, cancelled, failed }

    /// Settle a finished split run: a note that ended as turns is `.split`; a run that found one
    /// voice or was cancelled withdraws the request so the switch falls back to off.
    static func settle(_ pf: PipelineFile, error: Error?) -> Outcome {
        let outcome: Outcome
        if let e = error as? BatchRunnerError {
            switch e {
            case .oneVoice: outcome = .oneVoice
            case .cancelled: outcome = .cancelled
            case .missingAudioFile: outcome = .failed
            }
        } else if error != nil {
            outcome = .failed
        } else {
            outcome = isSplit(pf) ? .split : .oneVoice
        }
        if outcome != .split { withdraw(pf) }
        return outcome
    }

    // MARK: flatten (switching off)

    /// Undo a split WITHOUT transcribing again: drop the turn headers into plain prose, clear the
    /// diarization, and reopen the polish so the caller can write title + summary for one voice.
    /// What stays, on purpose: the words (with the user's fixes), `unlinkedNames` / `namePicks`,
    /// and every person in Names (this never touches `NamesStore`). Returns false when the note
    /// is not split, so a caller can no-op safely.
    @discardableResult
    static func flatten(_ pf: PipelineFile) -> Bool {
        guard SpeakerTranscript.isAttributed(pf.transcript),
              let flat = SpeakerTranscript.flattened(pf.transcript) else { return false }
        pf.transcript = flat
        pf.diarizationSegments = []
        pf.sanitised = nil
        pf.ambiguousNames = nil
        pf.enhancedCopyedit = nil
        pf.enhancedSummary = nil
        pf.compiledText = nil
        pf.sanitiseStatus = .pending
        pf.enhanceStatus = .pending
        pf.diarizeRequested = false
        return true
    }

    /// A real name this note's turns carry (the flatten confirm says "Maria stays in Names"),
    /// or nil when every speaker is still "Speaker N".
    static func namedPerson(in pf: PipelineFile, people: [Person]) -> String? {
        let resolver = SpeakerTurnStyle.HeaderResolver(people: people)
        for name in SpeakerTranscript.speakers(in: pf.bestBodyText) where !SpeakerTranscript.isUnnamed(name) {
            let label = SpeakerTurnStyle.label(for: name)
            if let p = resolver.person(for: label) { return NamesMerge.keyName(p.canonical) }
            return label
        }
        return nil
    }

    // MARK: naming from the gutter

    /// The turn headers of the note as it is SHOWN, in order — the gutter's own index space.
    static func turnLabels(in pf: PipelineFile) -> [String] {
        (SpeakerTranscript.parse(pf.bestBodyText) ?? []).map { SpeakerTurnStyle.label(for: $0.name) }
    }

    /// How many of the SHOWN turns belong to the speaker wearing `displayed` (their whole voice,
    /// short or full name alike). "A person names all 3 of Speaker 2's turns."
    static func turnCount(of displayed: String, in pf: PipelineFile, people: [Person]) -> Int {
        SpeakerNaming.turnCount(of: displayed, in: pf.bestBodyText, people: people)
    }

    /// The other speakers in the note, for the popover's "move this line" list: distinct
    /// identities, first-appearance order, excluding the one wearing `displayed`.
    static func otherSpeakers(than displayed: String, in pf: PipelineFile, people: [Person]) -> [String] {
        SpeakerNaming.otherSpeakers(than: displayed, in: pf.bestBodyText, people: people)
    }

    /// A person names ALL of that speaker's turns. Rewrites the raw transcript (and the
    /// copy-edit, which for a conversation is the same words) so a later re-link keeps the name;
    /// the caller then re-derives `sanitised`, which writes the full name on the speaker's first
    /// turn and the short one after. Returns false when there is nothing to rename.
    @discardableResult
    static func nameSpeaker(_ pf: PipelineFile, displayed: String, as newName: String, people: [Person]) -> Bool {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, isSplit(pf) else { return false }
        guard let renamed = SpeakerNaming.rename(pf.transcript, displayed: displayed, to: name, people: people) else { return false }
        pf.transcript = renamed
        if let ce = pf.enhancedCopyedit, SpeakerTranscript.isAttributed(ce) {
            pf.enhancedCopyedit = SpeakerNaming.rename(ce, displayed: displayed, to: name, people: people) ?? ce
        }
        return true
    }

    /// "Move just this line to another speaker": ONLY turn `index` (as shown) changes hands, and
    /// neighbours of the same speaker fold together. Works on the SHOWN body, so the index the
    /// gutter reports is the index used; the result is written back as plain words to the
    /// transcript and copy-edit (a conversation keeps both verbatim) for the caller to re-link.
    @discardableResult
    static func moveLine(_ pf: PipelineFile, turnIndex: Int, to other: String, people: [Person]) -> Bool {
        let body = pf.bestBodyText
        guard isSplit(pf),
              let moved = SpeakerTranscript.reassign(body, turnAt: turnIndex, to: SpeakerTurnStyle.label(for: other))
        else { return false }
        let plain = Sanitiser.unlinkToSpoken(moved, people: people)
        pf.transcript = plain
        if pf.enhancedCopyedit != nil { pf.enhancedCopyedit = plain }
        return true
    }

    // MARK: sync

    /// The split (or flatten) is a deliberate structural change of the note's words, so the
    /// synced `Memo` must carry it — otherwise `MemoCloudUpdate` path 3 sees the memo's old
    /// text differ from the row and puts the flat transcript back on the next sweep, and the
    /// phone never sees the turns. No `editedAt` bump: echo-quiet, like `MacMemoAuthor`.
    @discardableResult
    static func reflectTranscript(of pf: PipelineFile, into ctx: ModelContext) -> Bool {
        guard let text = pf.transcript, !text.isEmpty, let id = UUID(uuidString: pf.id),
              let memo = try? ctx.fetch(FetchDescriptor<Memo>(predicate: #Predicate { $0.id == id })).first,
              memo.transcript != text else { return false }
        memo.transcript = text
        memo.transcriptStatus = .done
        memo.transcriptUserEdited = true   // a structural, deliberate change: trusted, never re-ASR'd
        try? ctx.save()
        return true
    }
}
