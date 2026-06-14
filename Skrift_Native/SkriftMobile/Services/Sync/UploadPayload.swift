import Foundation

/// Builds a `multipart/form-data` body byte-compatible with the native Mac
/// server's `POST /api/files/upload` (`SkriftDesktop/Pipeline/Ingest/UploadService`)
/// and the FastAPI backend. Parts: `files` (audio), `metadata` (JSON), `transcript`
/// (only when present), `images` (one per photo). **Never sends `sanitised`** —
/// name-linking is Mac-side.
///
/// **Two paths, both in the same enum:**
///   • `build(memo:audioData:photos:)` — standard memo with audio (byte-identical to before).
///   • `buildCapture(memo:photos:)` — capture item (NO `files`, NO `transcript`, one optional
///     `images` part for image captures). The discriminator on the Mac side is: zero `files`
///     parts + `metadata.sharedContent` present.
///
/// C3 wire-contract invariant: a normal audio memo's multipart is BYTE-IDENTICAL to
/// the pre-capture shape — captures are a new branch, not a modification.
enum UploadPayload {

    // MARK: - Standard memo (audio present) — shape unchanged

    /// `wordTimingsJSON` / `diarizationJSON` are the phone's per-memo sidecars
    /// (`wt_<id>.json` = `[WordTiming]`, `diar_<id>.json` = `DiarizationData`), passed
    /// through verbatim as OPTIONAL additive parts. Absent on a memo without them and on
    /// older builds → the multipart stays byte-compatible (the Mac ignores missing parts).
    /// They let the Mac drive karaoke/read-along + enroll a speaker's voice from a
    /// phone-diarized conversation without re-transcribing.
    static func build(memo: Memo, audioData: Data, photos: [(filename: String, data: Data)],
                      wordTimingsJSON: Data? = nil, diarizationJSON: Data? = nil) -> (body: Data, contentType: String) {
        var builder = MultipartBuilder()

        let audioName = memo.audioFilename.isEmpty ? "memo_\(memo.id.uuidString).m4a" : memo.audioFilename
        builder.addFile(name: "files", filename: audioName, contentType: "audio/mp4", data: audioData)

        let metadataJSON = (try? JSONEncoder().encode(UploadMetadata(memo: memo))) ?? Data("{}".utf8)
        builder.addField(name: "metadata", value: metadataJSON, contentType: "application/json")

        // Mac trusts it iff userEdited || confidence >= 0.7; we send it whenever we
        // have a completed transcript and let the Mac decide.
        if memo.transcriptStatus == .done, let transcript = memo.transcript, !transcript.isEmpty {
            builder.addField(name: "transcript", value: Data(transcript.utf8))
        }

        // Optional additive sidecar parts (see the doc above). Never `sanitised`.
        if let wt = wordTimingsJSON, !wt.isEmpty {
            builder.addField(name: "wordTimings", value: wt, contentType: "application/json")
        }
        if let dz = diarizationJSON, !dz.isEmpty {
            builder.addField(name: "diar", value: dz, contentType: "application/json")
        }

        for photo in photos {
            builder.addFile(name: "images", filename: photo.filename, contentType: "image/jpeg", data: photo.data)
        }

        return (builder.finalize(), builder.contentType)
    }

    // MARK: - Capture item (no audio) — C3 contract

    /// Build a capture upload per the C3 contract (CAPTURE_CONTRACT.md):
    ///   - NO `files` part (absence + sharedContent = the discriminator).
    ///   - NO `transcript` part.
    ///   - `metadata` part with sharedContent + annotationText + duration=0.
    ///   - ONE `images` part when `memo.sharedContent.type == .image` (the image
    ///     file is passed as `photos`, same tuple shape as the audio path).
    ///
    /// `photos` should be empty for non-image captures and contain exactly one
    /// entry `(filename: sharedContent.fileName!, data: <jpeg>)` for image captures.
    static func buildCapture(memo: Memo, photos: [(filename: String, data: Data)] = []) -> (body: Data, contentType: String) {
        var builder = MultipartBuilder()
        // NO files part — intentional; its absence is the discriminator.

        let metadataJSON = (try? JSONEncoder().encode(UploadMetadata(memo: memo))) ?? Data("{}".utf8)
        builder.addField(name: "metadata", value: metadataJSON, contentType: "application/json")
        // NO transcript part — annotation rides in metadata.annotationText.

        // Image captures: one `images` part per the C3 spec.
        for photo in photos {
            let mime = photo.filename.hasSuffix(".png") ? "image/png" : "image/jpeg"
            builder.addFile(name: "images", filename: photo.filename, contentType: mime, data: photo.data)
        }

        return (builder.finalize(), builder.contentType)
    }
}

/// Flat metadata blob the Mac reads, mirroring the RN `sync.ts` object exactly:
/// the `MemoMetadata` fields + memo-level `tags`/`recordedAt`/`duration` +
/// `source:"mobile"` + the transcript-trust flags.
///
/// Codable (not just Encodable) so that tests can decode the multipart body and
/// assert exact contract field values against the C3 pinned fixture.
struct UploadMetadata: Codable {
    var capturedAt: String?
    var location: LocationInfo?
    var weather: WeatherInfo?
    var pressure: PressureInfo?
    var dayPeriod: DayPeriod?
    var daylight: DaylightInfo?
    var steps: Int?
    var photoFilename: String?
    var imageManifest: [ImageManifestEntry]?
    /// Audiobook quote-capture book metadata (CONTRACT ADDITION C2, additive /
    /// optional — absent on non-capture memos). The Mac's `PhoneMetadata`
    /// mirror reads these to compose the export attribution.
    var bookTitle: String?
    var bookAuthor: String?
    var bookChapter: String?
    var tags: [String]
    var source: String
    /// Optional phone-set title. The Mac may use it in its title chooser instead
    /// of the LLM title. CONTRACT ADDITION — the native Mac server's
    /// UploadService must read this (see the desktop-native flag).
    var title: String?
    var recordedAt: String
    var duration: Double
    var sharedContent: SharedContent?
    var annotationText: String?
    var transcriptConfidence: Double?
    var transcriptUserEdited: Bool
    var transcriptMarkersInjected: Bool
    /// Manual importance rating (0–1). CONTRACT ADDITION (additive/optional) — only
    /// emitted when > 0 (and only > 0 memos are uploaded at all; see SyncCoordinator).
    /// The desktop UploadService reads it → pre-fills its review significance slider.
    var significance: Double?

    init(memo: Memo) {
        let meta = memo.metadata
        capturedAt = meta?.capturedAt
        location = meta?.location
        weather = meta?.weather
        pressure = meta?.pressure
        dayPeriod = meta?.dayPeriod
        daylight = meta?.daylight
        steps = meta?.steps
        photoFilename = meta?.photoFilename
        imageManifest = meta?.imageManifest
        bookTitle = meta?.bookTitle
        bookAuthor = meta?.bookAuthor
        bookChapter = meta?.bookChapter
        tags = memo.tags
        source = "mobile"
        let trimmedTitle = memo.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        title = (trimmedTitle?.isEmpty == false) ? trimmedTitle : nil
        recordedAt = ISO8601.string(from: memo.recordedAt)
        duration = memo.duration
        sharedContent = memo.sharedContent
        annotationText = memo.annotationText
        transcriptConfidence = memo.transcriptConfidence
        transcriptUserEdited = memo.transcriptUserEdited
        transcriptMarkersInjected = memo.transcriptMarkersInjected
        significance = memo.significance > 0 ? memo.significance : nil
    }
}

/// Minimal `multipart/form-data` writer using the exact wire format the native
/// `MultipartParser` expects (CRLF-delimited, boundary, disposition, blank line).
struct MultipartBuilder {
    let boundary: String
    private var body = Data()

    init(boundary: String = "----skrift-\(UUID().uuidString)") {
        self.boundary = boundary
    }

    var contentType: String { "multipart/form-data; boundary=\(boundary)" }

    mutating func addField(name: String, value: Data, contentType: String? = nil) {
        appendString("--\(boundary)\r\n")
        appendString("Content-Disposition: form-data; name=\"\(name)\"\r\n")
        if let contentType { appendString("Content-Type: \(contentType)\r\n") }
        appendString("\r\n")
        body.append(value)
        appendString("\r\n")
    }

    mutating func addFile(name: String, filename: String, contentType: String, data: Data) {
        appendString("--\(boundary)\r\n")
        appendString("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n")
        appendString("Content-Type: \(contentType)\r\n\r\n")
        body.append(data)
        appendString("\r\n")
    }

    mutating func finalize() -> Data {
        appendString("--\(boundary)--\r\n")
        return body
    }

    private mutating func appendString(_ string: String) {
        body.append(Data(string.utf8))
    }
}
