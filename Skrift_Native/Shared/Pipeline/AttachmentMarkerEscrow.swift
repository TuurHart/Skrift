import Foundation

/// `[[img_NNN]]` / `[[vid_NNN]]` / `[[file_NNN]]` markers (Q469, C29, C30): copy-edit v2 holds
/// every one of them with its pictures (`CopyEditV2.Held`), so the model never sees a marker and
/// each returns after the same-index text paragraph.
enum AttachmentMarkerEscrow {
    /// Every picture or attachment marker: what makes a block "not text".
    static let anyMarkerRegex = try! NSRegularExpression(pattern: #"\[\[(?:img|vid|file)_\d+\]\]"#)
}
