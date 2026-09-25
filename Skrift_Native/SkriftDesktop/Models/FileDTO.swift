import Foundation

/// Wire shapes for the HTTP file endpoints, kept separate from the SwiftData
/// `@Model`. Only the phone consumes these (the native UI reads SwiftData
/// directly), and it reconciles by `filename`, so this is a faithful subset of the
/// backend `PipelineFile` rather than the whole thing.

struct StepsDTO: Codable, Sendable {
    var transcribe: String
    var sanitise: String
    var enhance: String
    var export: String
}

struct FileDTO: Codable, Sendable {
    var id: String
    var filename: String
    var size: Int
    var uploadedAt: String   // ISO-8601
    var sourceType: String
    var steps: StepsDTO
}

struct UploadResponseDTO: Codable, Sendable {
    var success: Bool
    var files: [FileDTO]
    var message: String
    var errors: [String]?
}
