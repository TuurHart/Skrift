import Foundation

/// Q180: the Mac side of the shared note-menu rules (`Shared/UI/NoteMenu.swift`). The rated
/// list row's right-click and the open note's ⋯ both ask THIS for what a `PipelineFile` can do,
/// so the two Mac surfaces and the phone read one rule set. Pure (no AppKit, no lock gate: the
/// caller passes `locked`) so `NoteMenuParityTests` can drive it.
enum MacNoteMenu {
    /// A speaker-attributed (conversation) transcript. Only an audio memo can be one.
    static func isConversation(_ file: PipelineFile) -> Bool {
        file.sourceType == .audio && SpeakerTranscript.isAttributed(file.transcript)
    }

    /// A polish really ran on this note (D176, Q295): a summary, a copy-edit, tags, or a title
    /// the model generated (`titleSuggested`; a chosen title only lands in `enhancedTitle`).
    /// A note whose only "polish" is a title Tuur chose himself has not been polished, so it
    /// offers Polish, not Redo.
    static func hasRealPolish(_ file: PipelineFile) -> Bool {
        func has(_ s: String?) -> Bool { !(s ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return has(file.enhancedSummary) || has(file.enhancedCopyedit) || has(file.titleSuggested)
            || file.tags.contains { has($0) }
    }

    /// Redo's availability: the shared engine/lock/any-part rule (`NoteRedoItem.isOffered`,
    /// engine is in-process here so always available) AND a real polish ran (Q295).
    static func redoOffered(_ file: PipelineFile, locked: Bool) -> Bool {
        hasRealPolish(file)
            && NoteRedoItem.isOffered(title: file.enhancedTitle, copyEdit: file.enhancedCopyedit,
                                      summary: file.enhancedSummary, engineAvailable: true, locked: locked)
    }

    /// Re-transcribe re-runs ASR and would destroy a conversation's speaker turns (the turns in
    /// the text are the only copy of the diarization), so it is off for them.
    static func canRetranscribe(_ file: PipelineFile) -> Bool {
        file.steps.transcribe == .done && file.sourceType != .note && !isConversation(file)
    }

    static func state(for file: PipelineFile, locked: Bool, canUndoTidyUp: Bool) -> NoteMenuState {
        NoteMenuState(locked: locked,
                      isConversation: isConversation(file),
                      canRetranscribe: canRetranscribe(file),
                      redoOffered: redoOffered(file, locked: locked),
                      canUndoTidyUp: canUndoTidyUp,
                      hasWorkingFolder: !file.path.isEmpty || !(file.exported ?? "").isEmpty,
                      hasExportedFile: file.steps.export == .done && !(file.exported ?? "").isEmpty)
    }
}
