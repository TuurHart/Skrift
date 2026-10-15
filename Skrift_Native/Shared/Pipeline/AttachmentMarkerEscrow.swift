import Foundation

/// v1 copy-edit's escrow for `[[vid_NNN]]` / `[[file_NNN]]` attachment markers (Q469, C29, C30):
/// the model never sees them, and each comes back after the same-index text paragraph of the
/// edited body. Copy-edit v2 holds them with its pictures (`CopyEditV2.Held`). Both polishers
/// run this: the Mac `CopyEditPipeline` and the phone `PolishEscrow`.
///
/// A text paragraph is a blank-line block with words left once every marker (picture or
/// attachment) is gone; a marker inline in text paragraph i returns after paragraph i, a
/// marker-only block before any text returns at the top.
enum AttachmentMarkerEscrow {
    /// Every picture or attachment marker: what makes a block "not text".
    static let anyMarkerRegex = try! NSRegularExpression(pattern: #"\[\[(?:img|vid|file)_\d+\]\]"#)

    struct Marker: Equatable, Sendable {
        let marker: String
        /// Text paragraphs before it.
        let after: Int
    }

    struct Held: Equatable, Sendable {
        /// The body without attachment markers (unchanged when it had none).
        let prose: String
        let markers: [Marker]
    }

    static func hold(_ text: String) -> Held {
        let regex = NoteAttachment.regex
        guard regex.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)) != nil else {
            return Held(prose: text, markers: [])
        }
        var markers: [Marker] = []
        var textParas = 0
        for block in text.components(separatedBy: "\n\n") {
            let b = block as NSString
            let found = regex.matches(in: block, range: NSRange(location: 0, length: b.length)).map { b.substring(with: $0.range) }
            if isText(block) { textParas += 1 }
            markers += found.map { Marker(marker: $0, after: textParas) }
        }
        let stripped = regex.stringByReplacingMatches(
            in: text, range: NSRange(location: 0, length: (text as NSString).length), withTemplate: " ")
        return Held(prose: CopyEditV2.Held.tidy(stripped), markers: markers)
    }

    /// Each held marker as its own paragraph after the same-index text paragraph of `edited`,
    /// clamped to the end. Picture-only blocks in `edited` stay where they are.
    static func place(_ markers: [Marker], in edited: String) -> String {
        guard !markers.isEmpty else { return edited }
        let blocks = CopyEditV2.paragraphs(edited)
        let textCount = blocks.filter(isText).count
        var out = markers.filter { $0.after == 0 }.map(\.marker)
        var k = 0
        for block in blocks {
            out.append(block)
            guard isText(block) else { continue }
            k += 1
            out += markers.filter { $0.after > 0 && Swift.min($0.after, textCount) == k }.map(\.marker)
        }
        if textCount == 0 { out += markers.filter { $0.after > 0 }.map(\.marker) }
        return out.joined(separator: "\n\n")
    }

    private static func isText(_ block: String) -> Bool {
        let r = NSRange(location: 0, length: (block as NSString).length)
        return !anyMarkerRegex.stringByReplacingMatches(in: block, range: r, withTemplate: "")
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
