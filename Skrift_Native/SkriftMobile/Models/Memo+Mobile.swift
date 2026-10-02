import Foundation

/// iOS-only coupling for the shared `Memo` @Model (`Shared/Model/Memo.swift`).
///
/// The core `Memo` is compiled by BOTH apps (the Mac is a CloudKit client of the phone's
/// note store — `MAC_CLOUDKIT_PLAN.md`), so it carries no iOS types. This extension adds
/// back the phone-side pieces the desktop must NOT see:
/// - the typed `sharedContent` accessor over the raw JSON blob (`SharedContent` is the
///   shared C3 wire struct — Shared/Model — but only the phone WRITES the blob, so the
///   accessor lives here; `metadata`/`MemoMetadata` are on the shared `Memo`),
/// - the on-disk path helpers (`audioURL` / `sharedFileURL`) that resolve against the iOS
///   app-container `AppPaths.recordingsDirectory`,
/// - `Memo.make(…)`, a typed convenience factory matching the old initializer's signature.
///
/// **Why a `make` factory and not a convenience `init`:** a convenience init taking
/// all-defaulted typed `metadata:` / `sharedContent:` params is *ambiguous* with the shared
/// blob-based designated init for any call that omits them (Swift overload resolution can't
/// pick between two inits both applicable to the same argument set). A static factory sidesteps
/// init overload resolution entirely — `Memo(…)` always resolves to the one designated init,
/// `Memo.make(… metadata:…)` handles typed construction.
extension Memo {
    /// Resolved on-disk audio location, or nil for memos without audio.
    var audioURL: URL? {
        audioFilename.isEmpty ? nil : AppPaths.recordingsDirectory.appendingPathComponent(audioFilename)
    }

    /// Resolved on-disk location of a shared `.file` capture's document (e.g. a PDF),
    /// or nil. `sharedContent.filePath` holds the RELATIVE filename (reinstall-safe),
    /// resolved against the recordings dir — same rule as `audioURL`.
    var sharedFileURL: URL? {
        guard let path = sharedContent?.filePath, !path.isEmpty else { return nil }
        return AppPaths.recordingsDirectory.appendingPathComponent(path)
    }

    /// Typed convenience factory — matches the pre-split `Memo(…)` initializer signature
    /// (with typed `metadata:` / `sharedContent:`). Use this anywhere the phone constructs
    /// a memo carrying contextual metadata or shared content; plain `Memo(…)` still works
    /// for memos without either.
    static func make(
        id: UUID = UUID(),
        audioFilename: String = "",
        duration: TimeInterval = 0,
        recordedAt: Date = Date(),
        tags: [String] = [],
        syncStatus: SyncStatus = .waiting,
        title: String? = nil,
        transcript: String? = nil,
        transcriptStatus: TranscriptStatus = .pending,
        transcriptConfidence: Double? = nil,
        transcriptUserEdited: Bool = false,
        transcriptMarkersInjected: Bool = false,
        significance: Double = 0,
        deletedAt: Date? = nil,
        createdAt: Date? = Date(),
        editedAt: Date? = nil,
        metadata: MemoMetadata? = nil,
        sharedContent: SharedContent? = nil,
        annotationText: String? = nil,
        recordingDeviceID: String? = DeviceID.current()
    ) -> Memo {
        Memo(
            id: id,
            audioFilename: audioFilename,
            duration: duration,
            recordedAt: recordedAt,
            tags: tags,
            syncStatus: syncStatus,
            title: title,
            transcript: transcript,
            transcriptStatus: transcriptStatus,
            transcriptConfidence: transcriptConfidence,
            transcriptUserEdited: transcriptUserEdited,
            transcriptMarkersInjected: transcriptMarkersInjected,
            significance: significance,
            deletedAt: deletedAt,
            createdAt: createdAt,
            editedAt: editedAt,
            metadataData: Memo.encodeJSON(metadata),
            sharedContentData: Memo.encodeJSON(sharedContent),
            annotationText: annotationText,
            recordingDeviceID: recordingDeviceID
        )
    }
}

// MARK: - Name-linking resolution (the phone's in-place name-linking surface)
// `NameResolutions`, `Memo.nameResolutions` and the link / keep-plain / clear mutators are
// shared (Shared/Naming/NameResolutions.swift); the Mac mirrors the same blob (C81, D20).

extension Memo {
    /// Tiered name spans over the RAW transcript against THIS note's resolutions — the
    /// data behind the in-place name-linking surface. People injected for testability.
    func nameSpans(people: [Person]) -> [NameSpan] {
        Sanitiser.nameSpans(inRaw: transcript ?? "", people: people,
                            neverLink: Set(nameResolutions.unlinkedNames),
                            namePicks: nameResolutions.namePicks)
    }
}
