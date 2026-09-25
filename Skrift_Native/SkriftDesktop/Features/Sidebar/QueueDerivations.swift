import SwiftUI

/// The honest one-word queue status, derived from the four step columns.
/// Ported from `Sidebar.tsx` `noteStatus`.
enum QueueStatus {
    case queued, transcribing, transcribed, enhancing, ready, exported, error

    var label: String {
        switch self {
        case .queued:       return "Queued"
        case .transcribing: return "Transcribing"
        case .transcribed:  return "Transcribed"
        case .enhancing:    return "Enhancing"
        case .ready:        return "Ready"
        case .exported:     return "Exported"
        case .error:        return "Error"
        }
    }

    /// Pill text color.
    var color: Color {
        switch self {
        case .ready:                  return Theme.green
        case .enhancing:              return Theme.amber
        case .transcribing:           return Theme.blue
        case .transcribed, .queued:   return Theme.textSecondary
        case .exported:               return Theme.textMuted
        case .error:                  return Theme.destructive
        }
    }

    /// Pill background tint (Exported reads as a quiet, untinted label).
    var tint: Color { color.opacity(self == .exported ? 0 : 0.16) }

    /// Whether the pill shows a pulsing activity dot (work in flight).
    var pulses: Bool { self == .enhancing || self == .transcribing }
}

extension PipelineFile {
    var queueStatus: QueueStatus {
        let s = steps
        if s.transcribe == .error || s.enhance == .error || s.export == .error { return .error }
        if s.transcribe == .processing { return .transcribing }
        if s.enhance == .processing { return .enhancing }
        if s.export == .done { return .exported }
        if s.enhance == .done { return .ready }
        if s.transcribe == .done || s.transcribe == .skipped { return .transcribed }
        return .queued
    }

    /// `sharedContent.type` from the phone metadata blob (url/image/text/file), if
    /// any. camelCase `sharedContent` only — the C3 contract, matching
    /// `SharedContent.decode` (the snake_case tolerance was dead leniency with no
    /// producer; goldens: SharedContentParityTests).
    var sharedContentType: String? {
        guard let data = audioMetadataJSON,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sc = obj["sharedContent"] as? [String: Any] else { return nil }
        return sc["type"] as? String
    }

    /// SF Symbol for the row's source glyph — the unified source taxonomy. Pairs
    /// with `sourceTypeLabel` (same `sourceDescriptor`) so the sidebar glyph and the
    /// detail "source" line ALWAYS correspond.
    var sourceSymbol: String { sourceDescriptor.glyph }

    /// Human label for the detail "source" field — the SAME descriptor as the row
    /// glyph, so glyph and label can never disagree (e.g. a video shows the film
    /// glyph + "Video", not the mic + "Voice memo").
    var sourceTypeLabel: String { sourceDescriptor.label }

    /// Single source of truth for (glyph, label). Discriminators, in priority:
    /// audiobook quote (C2 `bookTitle` blob) → video (`mediaSource`) → the base
    /// `sourceType`/`sharedContentType`. A book capture + a video both sync as
    /// `.audio`, so type alone can't tell them apart — the markers do.
    var sourceDescriptor: (glyph: String, label: String) {
        let kind: SourceKind
        if bookCapture != nil { kind = .audiobookQuote }
        else if mediaSource == "video" { kind = .video }
        // A note somebody TYPED, ingested as a `.note` row — the marker is what keeps it
        // from reading as an Apple Note import, that row kind's only other population.
        else if mediaSource == "typed" { kind = .typedNote }
        else {
            switch sourceType {
            case .note:  kind = .appleNote
            case .audio: kind = .voiceMemo
            case .capture:
                switch sharedContentType {
                case "url":   kind = .captureURL
                case "image": kind = .captureImage
                case "text":  kind = .captureText
                case "file":  kind = .captureFile
                default:      kind = .captureOther
                }
            }
        }
        // Glyph + label come from the SHARED taxonomy — one copy, both apps.
        return (kind.glyph, kind.label)
    }

    /// Duration like "2:14" pulled from the phone metadata blob, if present. Goes
    /// through the shared `durationSeconds` reader so the row and the note header can't
    /// disagree about whether a note has a duration — they used to, whenever the blob
    /// held the numeric shape (both said "no", wrongly).
    var durationString: String? {
        let secs = durationSeconds
        guard secs > 0 else { return nil }
        return SkriftFormat.duration(seconds: secs)
    }

    /// Title shown in the queue row.
    var queueTitle: String { displayTitle }   // enhanced title → first body line → filename (phone parity)
}

enum SkriftFormat {
    /// Strip a trailing file extension (but not if the dot is inside a path segment).
    static func cleanFilename(_ name: String) -> String {
        guard let dot = name.lastIndex(of: ".") else { return name }
        let ext = name[name.index(after: dot)...]
        if ext.contains("/") || ext.isEmpty { return name }
        return String(name[..<dot])
    }

    /// "HH:MM:SS" / "MM:SS" → "M:SS" (with "H:MM:SS" when there are hours).
    /// Seconds → "h:mm:ss" past the hour, else "m:ss". Takes SECONDS now rather than an
    /// `"HH:MM:SS"` string: the stored value isn't always a string (see
    /// `PipelineFile.durationSeconds`), so parsing belongs at the read and this only
    /// formats. Hours matter here — an audiobook capture runs to double digits.
    static func duration(seconds: Double) -> String {
        let total = Int(max(0, seconds.isFinite ? seconds : 0).rounded())
        let (h, m, s) = (total / 3600, (total % 3600) / 60, total % 60)
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }

    private static let shortDF: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "dd MMM"
        f.locale = Locale(identifier: "en_GB")
        return f
    }()

    static func shortDate(_ d: Date) -> String {
        if Calendar.current.isDateInToday(d) { return "today" }
        return shortDF.string(from: d)
    }
}
