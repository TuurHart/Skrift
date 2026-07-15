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
    /// any. The phone sends camelCase `sharedContent` (C3 contract); snake_case is
    /// tolerated for hand-built fixtures, matching `SharedContent.decode`.
    var sharedContentType: String? {
        guard let data = audioMetadataJSON,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sc = (obj["sharedContent"] ?? obj["shared_content"]) as? [String: Any] else { return nil }
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
    private var sourceDescriptor: (glyph: String, label: String) {
        if bookCapture != nil { return ("book.closed.fill", "Audiobook quote") }
        if mediaSource == "video" { return ("video.fill", "Video") }
        switch sourceType {
        case .note:  return ("note.text", "Apple Note")
        case .audio: return ("mic.fill", "Voice memo")
        case .capture:
            switch sharedContentType {
            case "url":   return ("link", "Link")
            case "image": return ("photo", "Image")
            case "text":  return ("text.quote", "Text")
            case "file":  return ("doc", "File")
            default:      return ("square.and.arrow.down", "Capture")
            }
        }
    }

    /// Duration like "2:14" pulled from the phone metadata blob, if present.
    var durationString: String? {
        guard let data = audioMetadataJSON,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let d = obj["duration"] as? String else { return nil }
        return SkriftFormat.duration(d)
    }

    /// Title shown in the queue row.
    var queueTitle: String { displayTitle }   // enhanced title → first body line → filename (phone parity)

    /// Secondary meta line: "06 Jun · 2:14" / "05 Jun · Link" / "03 Jun · Apple Note".
    var queueMeta: String {
        let date = SkriftFormat.shortDate(uploadedAt)
        if let dur = durationString { return "\(date) · \(dur)" }
        switch sourceType {
        case .note: return "\(date) · Apple Note"
        case .audio: return date
        case .capture:
            switch sharedContentType {
            case "url":   return "\(date) · Link"
            case "image": return "\(date) · Image"
            case "file":  return "\(date) · File"
            case "text":  return "\(date) · Text"
            default:      return date
            }
        }
    }
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
    static func duration(_ hms: String) -> String {
        let parts = hms.split(separator: ":").map { Int($0) ?? 0 }
        let h, m, s: Int
        switch parts.count {
        case 3: (h, m, s) = (parts[0], parts[1], parts[2])
        case 2: (h, m, s) = (0, parts[0], parts[1])
        default: return hms
        }
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
