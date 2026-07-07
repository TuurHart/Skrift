import Foundation

// MARK: - Shared content (capture items)

// Mobile-side home for the `Memo.sharedContentData` schema. The rest of the
// metadata schema (`MemoMetadata` + friends) is SHARED (Shared/Model/
// MemoMetadata.swift); these two stay mobile-only because the desktop keeps its
// own deliberately-lenient `SharedContent` decoder (CompilerBridge.swift —
// string `type`, snake_case demo-seed fallback) and the names would collide.
// Field names are the C3 capture contract (`Skrift_Native/CAPTURE_CONTRACT.md`)
// — identical on both sides; never rename them.

enum ShareContentType: String, Codable, Sendable {
    case url
    case image
    case text
    case file
}

/// A shared URL / image / text / file captured via the Share Extension, with an
/// optional voice or text annotation. Mirrors the RN `SharedContent`.
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
