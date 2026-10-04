import Foundation

/// The phone's `diarization` `MemoAsset` blob, decoded for its segments only. The blob is the
/// phone's `DiarizationData` JSON (`segments` + `slotNames` + `turnSlots`); the Mac keeps
/// `pf.diarizationSegments` and nothing else of it (voice enrollment slices by segments; the
/// names live in the transcript headers).
struct PhoneDiarizationBlob: Decodable {
    let segments: [DiarizedSegment]
}
