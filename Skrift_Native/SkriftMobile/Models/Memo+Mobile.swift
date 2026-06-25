import Foundation

/// iOS-only coupling for the shared `Memo` @Model (`Shared/Model/Memo.swift`).
///
/// The core `Memo` is compiled by BOTH apps (the Mac is a CloudKit client of the phone's
/// note store — `MAC_CLOUDKIT_PLAN.md`), so it carries no iOS types. This extension adds
/// back the phone-side pieces the desktop must NOT see:
/// - the typed `metadata` / `sharedContent` accessors over the raw JSON blobs (the
///   `MemoMetadata` / `SharedContent` structs stay mobile-only — they'd otherwise collide
///   with the desktop's `CompilerBridge.SharedContent`),
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

    /// Typed contextual metadata, decoded from / encoded to the raw `metadataData` blob.
    var metadata: MemoMetadata? {
        get { Self.decodeJSON(metadataData) }
        set { metadataData = Self.encodeJSON(newValue) }
    }

    /// Typed shared-capture payload, decoded from / encoded to the raw `sharedContentData` blob.
    var sharedContent: SharedContent? {
        get { Self.decodeJSON(sharedContentData) }
        set { sharedContentData = Self.encodeJSON(newValue) }
    }

    /// Typed per-note name-linking resolution choices, over the `nameResolutionsData` blob.
    var nameResolutions: NameResolutions {
        get { Self.decodeJSON(nameResolutionsData) ?? NameResolutions() }
        set { nameResolutionsData = newValue.isEmpty ? nil : Self.encodeJSON(newValue) }
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

/// Per-note name-linking resolution choices — the typed form of `Memo.nameResolutionsData`.
/// Drives the phone's tap-to-resolve surface (`mocks/phone-name-linking.html`) and the
/// on-device Obsidian export, fed straight into the shared `Sanitiser`. Phone-side only —
/// the mobile↔Mac contract (phone sends RAW, Mac links names) is untouched.
struct NameResolutions: Codable, Equatable {
    /// Canonical keys kept plain across the WHOLE note regardless of alias — the
    /// `Sanitiser.neverLink` input. (Reserved; today's gestures use per-alias `namePicks`.)
    var unlinkedNames: [String] = []
    /// alias(lowercased) → chosen canonical `[[Name]]` (a force-pick / link), or `""`
    /// to SILENCE the alias (the reversible "keep as plain text" / unlink). The
    /// `Sanitiser.namePicks` input.
    var namePicks: [String: String] = [:]

    var isEmpty: Bool { unlinkedNames.isEmpty && namePicks.isEmpty }
}

extension Memo {
    /// Tiered name spans over the RAW transcript against THIS note's resolutions — the
    /// data behind the in-place name-linking surface. People injected for testability.
    func nameSpans(people: [Person]) -> [NameSpan] {
        Sanitiser.nameSpans(inRaw: transcript ?? "", people: people,
                            neverLink: Set(nameResolutions.unlinkedNames),
                            namePicks: nameResolutions.namePicks)
    }

    /// Normalised resolution key for an alias (the spoken word as displayed).
    private static func aliasKey(_ alias: String) -> String {
        alias.trimmingCharacters(in: .whitespaces).lowercased()
    }

    /// Force-LINK an alias to a specific person for this note (resolve an ambiguous /
    /// suggested name, or "change person" on a linked one). Clears any prior keep-plain.
    func linkName(alias: String, to canonical: String) {
        let key = Self.aliasKey(alias)
        guard !key.isEmpty else { return }
        var r = nameResolutions
        r.namePicks[key] = NamesMerge.normaliseCanonical(canonical)
        r.unlinkedNames.removeAll { NamesMerge.keyName($0).lowercased() == NamesMerge.keyName(canonical).lowercased() }
        nameResolutions = r
        markEdited()
    }

    /// KEEP an alias plain for this note (the reversible "keep as plain text" / unlink):
    /// silence it so it neither links nor suggests, but stays a re-tappable plain token.
    func keepNamePlain(alias: String) {
        let key = Self.aliasKey(alias)
        guard !key.isEmpty else { return }
        var r = nameResolutions
        r.namePicks[key] = ""
        nameResolutions = r
        markEdited()
    }

    /// REVERT an alias to its default tier (undo a link / keep-plain) — removes the
    /// per-note override so an auto-link person re-links, an ambiguous one goes dotted again.
    func clearNameResolution(alias: String) {
        let key = Self.aliasKey(alias)
        var r = nameResolutions
        guard r.namePicks[key] != nil else { return }
        r.namePicks.removeValue(forKey: key)
        nameResolutions = r
        markEdited()
    }
}
