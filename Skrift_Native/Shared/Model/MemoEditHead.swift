import Foundation
import SwiftData

/// One device's LATEST words for one note (C98 / C242 / D139): the note's title, body and
/// tags as that device last edited them, plus the edit vector they were written at.
///
/// **Why a separate synced row per (memo, device):** the `Memo` row itself is merged by
/// CloudKit per field, newest-wins, so when two devices edit the same note while apart, one
/// device's words are overwritten on arrival and gone. A head row is keyed by the DEVICE, so
/// the two devices never write the same row: both versions survive the meeting, and
/// `EditConflicts.detect` can see that neither descends from the other.
///
/// **CloudKit shape rules (mirrors `Memo`/`MemoAsset`):** every attribute has a default, no
/// `@Attribute(.unique)`, no relationship (loose `memoID` key). A NEW record type is an
/// additive schema change: older builds never fetch it and keep plain newest-wins. Needs the
/// prod CloudKit schema deploy at promotion, like every additive field.
@Model
final class MemoEditHead {
    var memoID: UUID = UUID()
    /// `DeviceID.current()` of the device that wrote these words.
    var deviceID: String = ""
    /// "iPhone" / "iPad" / "Mac" — Skrift stores no device NAMES, so the prompt says
    /// "this iPhone" / "the Mac" (Q4 finding).
    var deviceKind: String = ""
    /// JSON `[deviceID: Int]` — the edit vector these words were written at.
    var vectorData: Data? = nil
    /// Content hash of the words this device edited FROM (nil = unknown: the first edit
    /// after the upgrade). Equal to `contentHash` = the device changed no words.
    var baseHash: String? = nil
    var title: String? = nil
    var body: String? = nil
    var tags: [String] = []
    var editedAt: Date = Date()
    /// The POLISHED body (`MemoEnhancement.copyedit`) this device held at this edit — the
    /// text he actually edits on a Mac-polished note (Q38). nil = the note had no polish, or
    /// the head came from a build before Q38. ADDITIVE, nil default.
    var polishedBody: String? = nil

    init(memoID: UUID, deviceID: String, deviceKind: String, vector: EditVector,
         baseHash: String?, title: String?, body: String?, tags: [String], editedAt: Date,
         polishedBody: String? = nil) {
        self.memoID = memoID
        self.deviceID = deviceID
        self.deviceKind = deviceKind
        self.vectorData = EditVectors.encode(vector)
        self.baseHash = baseHash
        self.title = title
        self.body = body
        self.tags = tags
        self.editedAt = editedAt
        self.polishedBody = polishedBody
    }

    var vector: EditVector {
        get { EditVectors.decode(vectorData) }
        set { vectorData = EditVectors.encode(newValue) }
    }

    var contentHash: String {
        EditConflicts.hash(title: title, body: body, tags: tags, polished: polishedBody)
    }
}
