import Foundation

/// The note's "Include audio in export" switch (ST8, setexp-92) between the Mac's
/// `PipelineFile` and the synced `Memo`, so the Mac exporter and the phone publisher honour ONE
/// value (Q186). Synced the way the destination is: phone → Mac on first contact and every live
/// update, Mac → phone as an EVENT when the switch is flipped (`MacCloudMetaSync.setIncludeAudio`),
/// never on the passive pass — a stale row must not clobber a newer phone choice.
///
/// Kept apart from `MirroredNoteFields` for the reason `NameResolutionsMirror` is: that list's
/// tests pin its exact members. The callers are the same three seams: `MemoCloudIngest`,
/// `MemoCloudUpdate`, `MacCloudMetaSync`. No recompile: the audio rides the export's asset
/// lane, not the note's markdown.
enum ExportAudioMirror {

    /// phone → Mac. Returns true when it changed the row.
    @discardableResult
    static func pull(_ memo: Memo, into pf: PipelineFile) -> Bool {
        guard pf.includeAudioInExport != memo.includeAudioInExport else { return false }
        pf.includeAudioInExport = memo.includeAudioInExport
        return true
    }

    /// Mac → phone. Value-compared, so an agreeing memo is not churned.
    @discardableResult
    static func push(_ pf: PipelineFile, to memo: Memo) -> Bool {
        guard memo.includeAudioInExport != pf.includeAudioInExport else { return false }
        memo.includeAudioInExport = pf.includeAudioInExport
        return true
    }
}
