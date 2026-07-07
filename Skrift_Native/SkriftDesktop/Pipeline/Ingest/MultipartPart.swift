import Foundation

/// One part of a `multipart/form-data`-shaped upload. Retained after the Bonjour/HTTP
/// server was retired because the CloudKit read bridge (`MemoCloudIngest`) still
/// synthesizes these parts and hands them to `UploadService.ingest` — the shared
/// materialization path both transports used. (The HTTP `MultipartParser` that produced
/// these from a socket body was deleted with the server.)
struct MultipartPart: Sendable {
    var name: String
    var filename: String?
    var contentType: String?
    var data: Data
}
