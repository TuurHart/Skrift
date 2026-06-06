import Foundation
import SwiftData

/// Local sync state. Mirrors the RN `Memo.syncStatus` ('waiting' | 'synced').
enum SyncStatus: String, Codable, Sendable {
    case waiting
    case synced
}

/// On-device transcription state. Mirrors the RN `TranscriptStatus`.
enum TranscriptStatus: String, Codable, Sendable {
    case pending
    case transcribing
    case done
    case failed
}

/// A captured voice memo. Mirrors the RN `Memo` shape (`Mobile/lib/storage.ts`)
/// plus the mobile↔Mac contract fields the backend trusts.
@Model
final class Memo {
    /// Stable identity. Audio filenames embed it (`memo_{uuid}.m4a`) and the Mac
    /// reconciles uploads by filename — so this UUID is the contract spine. Never
    /// regenerate it for an existing memo.
    @Attribute(.unique) var id: UUID = UUID()

    /// Audio is stored by filename and resolved against the recordings dir at
    /// runtime — an absolute URL would break across reinstalls (the app-container
    /// UUID changes), and the filename already carries the memo UUID. Empty for
    /// capture items with no audio annotation.
    var audioFilename: String = ""

    var duration: TimeInterval = 0
    var recordedAt: Date = Date()
    var tags: [String] = []
    var syncStatus: SyncStatus = SyncStatus.waiting

    /// On-device transcript. Contains `[[img_NNN]]` markers when photos were
    /// taken. Trusted by the Mac iff `transcriptUserEdited || confidence >= 0.7`.
    var transcript: String?
    var transcriptStatus: TranscriptStatus = TranscriptStatus.pending
    var transcriptConfidence: Double?
    var transcriptUserEdited: Bool = false
    /// True when `[[img_NNN]]` markers are already injected — tells the Mac not
    /// to re-inject them.
    var transcriptMarkersInjected: Bool = false

    /// Contextual capture payload. Stored whole (never queried by SwiftData);
    /// its shape feeds the Mac upload `metadata` JSON.
    var metadata: MemoMetadata?
    var sharedContent: SharedContent?
    var annotationText: String?

    init(
        id: UUID = UUID(),
        audioFilename: String = "",
        duration: TimeInterval = 0,
        recordedAt: Date = Date(),
        tags: [String] = [],
        syncStatus: SyncStatus = .waiting,
        transcript: String? = nil,
        transcriptStatus: TranscriptStatus = .pending,
        transcriptConfidence: Double? = nil,
        transcriptUserEdited: Bool = false,
        transcriptMarkersInjected: Bool = false,
        metadata: MemoMetadata? = nil,
        sharedContent: SharedContent? = nil,
        annotationText: String? = nil
    ) {
        self.id = id
        self.audioFilename = audioFilename
        self.duration = duration
        self.recordedAt = recordedAt
        self.tags = tags
        self.syncStatus = syncStatus
        self.transcript = transcript
        self.transcriptStatus = transcriptStatus
        self.transcriptConfidence = transcriptConfidence
        self.transcriptUserEdited = transcriptUserEdited
        self.transcriptMarkersInjected = transcriptMarkersInjected
        self.metadata = metadata
        self.sharedContent = sharedContent
        self.annotationText = annotationText
    }

    /// Resolved on-disk audio location, or nil for memos without audio.
    var audioURL: URL? {
        audioFilename.isEmpty ? nil : AppPaths.recordingsDirectory.appendingPathComponent(audioFilename)
    }
}
