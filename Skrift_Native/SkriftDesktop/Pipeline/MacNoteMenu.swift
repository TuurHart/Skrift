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

    /// Redo's availability through the ONE shared rule. The Mac's engine is in-process, so
    /// `engineAvailable` is true here (the phone's depends on the device and model).
    static func redoOffered(_ file: PipelineFile, locked: Bool) -> Bool {
        NoteRedoItem.isOffered(title: file.enhancedTitle, copyEdit: file.enhancedCopyedit,
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
