import Foundation

// MARK: - Shared content (capture items)

// THE C3 capture wire struct (`Skrift_Native/CAPTURE_CONTRACT.md`) — ONE copy for
// both apps (SharedKit wave 2; previously twinned mobile Models/SharedContent.swift
// vs desktop CompilerBridge.swift). The phone writes it (`Memo.sharedContentData`,
// naked blob); `MemoCloudIngest` passes that blob verbatim into the Mac's metadata
// envelope under `"sharedContent"`; the Mac decodes with `decode(from:)` below.
// Field names ARE the contract — never rename them. Adding a capture type means
// extending `ShareContentType` here (both apps pick it up in the same commit).
// Goldens: SharedContentParityTests in both suites.

enum ShareContentType: String, Codable, Sendable {
    case url
    case image
    case text
    case file
}

/// A shared URL / image / text / file captured via the Share Extension, with an
/// optional voice or text annotation.
struct SharedContent: Codable, Equatable, Sendable {
    var type: ShareContentType
    var url: String?
    var urlTitle: String?
    var urlDescription: String?
    var urlThumbnailUrl: String?
    var text: String?
    var filePath: String?
    var fileName: String?
    var mimeType: String?
}

extension SharedContent {
    /// The `sharedContent` object inside a phone metadata JSON blob — the Mac's
    /// read path (`PipelineFile.audioMetadataJSON`). camelCase only; an unknown
    /// `type` yields nil (better no info than a junk-typed record).
    static func decode(from metadataJSON: Data?) -> SharedContent? {
        guard let data = metadataJSON else { return nil }
        return (try? JSONDecoder().decode(_Wrapper.self, from: data))?.sharedContent
    }

    private struct _Wrapper: Codable { var sharedContent: SharedContent? }
}
