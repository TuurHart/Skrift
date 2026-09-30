import Foundation
import CryptoKit

/// The stamp Skrift leaves in an exported note's YAML frontmatter, and the rules for
/// reading it back.
///
/// **This is a PUBLIC CONTRACT, not an implementation detail** (decided with Tuur
/// 2026-07-26, roadmap idea i14). A future Obsidian plugin reads and writes these keys,
/// so treat the format as versioned and additive: rename nothing, and add rather than
/// repurpose. It is also what any other tool would need to recognise a Skrift note.
///
/// ```
/// ---
/// title: "Okay. So let me go over it"
/// lastTouched: 2026-07-26T02:31:07Z
/// skriftID: 7C3F2A1B-...
/// skriftHash: 3f2a1b9c8e...
/// ---
/// ```
///
/// Three questions it answers, which between them carry the whole export safety model:
///
/// 1. **Is this note ours?** No `skriftID` ⇒ Skrift did not write this file and must
///    never overwrite it. Before this existed, the Mac wrote `<title>.md` unconditionally
///    and could silently replace a hand-authored note whose title happened to match.
/// 2. **Did the user edit it?** `skriftHash` is the fingerprint of the file as Skrift
///    last wrote it. Recompute it; a mismatch means a human changed the note, so their
///    version is the newer intent. (It covers the frontmatter too, so a tag added in
///    Obsidian counts — Tuur, on the alternative: *"edit tags in the app, not in
///    Obsidian" is not intuitive*.)
/// 3. **Which note is it, wherever it now lives?** The Skrift folder is an INBOX — notes
///    get filed out of it into the rest of the vault. Keying on `skriftID` rather than on
///    a remembered path is what stops a moved note being re-created as a duplicate.
///
/// The hash deliberately covers **everything except its own line** — self-reference is
/// otherwise impossible — so `lastTouched`, the title and the body are all protected.
enum VaultStamp {
    /// Frontmatter key for the memo's UUID. Stable across renames AND moves.
    static let idKey = "skriftID"
    /// Frontmatter key for the content fingerprint.
    static let hashKey = "skriftHash"
    /// Frontmatter key for when Skrift last wrote the file. Pre-existed as an
    /// always-EMPTY `lastTouched:` in every exported note (nothing wrote a value,
    /// nothing read it — Tuur spotted it); it now carries a real timestamp and serves as
    /// the cheap half of change detection: a file modified later than this deserves a
    /// look, with `skriftHash` as the authority.
    static let touchedKey = "lastTouched"

    /// What a file's frontmatter claims about itself.
    struct Marks: Equatable {
        var id: UUID
        var hash: String
    }

    /// Verdict on a file already at the destination — the only three states export
    /// needs to tell apart before it writes.
    enum Standing: Equatable {
        /// No file there. Safe to create.
        case absent
        /// Ours, byte-identical to what we last wrote. Safe to overwrite.
        case untouched(Marks)
        /// Ours, but changed since we wrote it ⇒ the user edited it. Their version wins;
        /// do not overwrite. (The return path will later ADOPT the edit; today it stops.)
        case userEdited(Marks)
        /// A file we have no claim on — no stamp, or an unreadable one. Never touch it.
        case foreign
    }

    // MARK: - Writing

    /// Stamp `markdown` for `id`: set `lastTouched`, then compute the fingerprint over the
    /// finished text and write it in. Call this LAST, after every other transform (image
    /// markers → embeds, attachment rewrites), or the hash won't describe the bytes that
    /// actually land on disk.
    static func apply(to markdown: String, id: UUID, touchedAt: Date = Date()) -> String {
        // Order matters: seed both keys first (so the hash covers a line that exists and
        // will keep existing), then fill the hash from the result.
        var out = upsert(markdown, key: touchedKey, value: iso.string(from: touchedAt))
        out = upsert(out, key: idKey, value: id.uuidString)
        out = upsert(out, key: hashKey, value: "")
        return upsert(out, key: hashKey, value: fingerprint(of: out))
    }

    // MARK: - Reading

    /// The stamp `markdown` carries, or nil when it carries none (⇒ not a Skrift note).
    static func read(_ markdown: String) -> Marks? {
        guard let fm = frontmatter(markdown),
              let idRaw = value(of: idKey, in: fm), let id = UUID(uuidString: idRaw),
              let hash = value(of: hashKey, in: fm), !hash.isEmpty else { return nil }
        return Marks(id: id, hash: hash)
    }

    /// Classify what is already on disk. `existing` is nil when nothing is there.
    static func standing(of existing: String?) -> Standing {
        guard let existing else { return .absent }
        guard let marks = read(existing) else { return .foreign }
        return marks.hash == fingerprint(of: existing) ? .untouched(marks) : .userEdited(marks)
    }

    /// The fingerprint of `text`: SHA-256 over every line EXCEPT the `skriftHash` line.
    /// Excluding only that one line is what makes the stamp self-consistent while still
    /// protecting the title, the timestamp, the tags and the body.
    static func fingerprint(of text: String) -> String {
        let kept = text.components(separatedBy: "\n")
            .filter { !isKeyLine($0, key: hashKey) }
            .joined(separator: "\n")
        return SHA256.hash(data: Data(kept.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// Same CONTENT, ignoring the stamp's volatile lines (`skriftHash` + `lastTouched`)?
    /// This is the skip-unchanged test: a re-export whose only difference is a fresh
    /// timestamp must NOT rewrite the file — every needless rewrite is an mtime bump
    /// iCloud then syncs, and needless churn is exactly what breeds its conflict copies.
    static func contentEquivalent(_ a: String, _ b: String) -> Bool {
        func stripped(_ s: String) -> String {
            s.components(separatedBy: "\n")
                .filter { !isKeyLine($0, key: hashKey) && !isKeyLine($0, key: touchedKey) }
                .joined(separator: "\n")
        }
        return stripped(a) == stripped(b)
    }

    /// Does this look like a PRE-STAMP Skrift export? The tell is the `lastTouched` key —
    /// Skrift has emitted it (empty) in every exported note since the Compiler existed,
    /// and nothing else writes that key — while carrying no `skriftID`. These are the
    /// user's REAL already-exported notes (they may have edited them, and with no hash
    /// there is no way to know), so the writer refuses them rather than guessing.
    /// Find the note `id` ANYWHERE under `root`, by its stamp. This is what the stamp is for
    /// — "which note, wherever it lives" — and it answers the one question the export ledger
    /// cannot: a file missing from where Skrift wrote it was either MOVED (filed out of the
    /// inbox, which is the whole point of an inbox) or DELETED. Those want opposite answers,
    /// and until 2026-08-28 both got the moved one, so a note whose file had been deleted
    /// could never be exported again — it just kept saying "left where you put it".
    ///
    /// Reads only the head of each `.md`, stops at the first hit, and only ever runs when the
    /// ledger's path has gone missing, which is rare.
    static func locate(id: UUID, under root: URL, fileManager fm: FileManager = .default) -> URL? {
        guard let en = fm.enumerator(at: root, includingPropertiesForKeys: nil,
                                     options: [.skipsHiddenFiles]) else { return nil }
        let needle = id.uuidString.lowercased()
        for case let url as URL in en where url.pathExtension.lowercased() == "md" {
            guard let handle = try? FileHandle(forReadingFrom: url) else { continue }
            defer { try? handle.close() }
            let head = (try? handle.read(upToCount: 2048)) ?? Data()
            guard let text = String(data: head, encoding: .utf8),
                  let fm2 = frontmatter(text),
                  let raw = value(of: idKey, in: fm2) else { continue }
            if raw.trimmingCharacters(in: .whitespaces).lowercased() == needle { return url }
        }
        return nil
    }

    static func looksLegacySkrift(_ text: String) -> Bool {
        guard read(text) == nil, let fm = frontmatter(text) else { return false }
        return value(of: touchedKey, in: fm) != nil
    }

    // MARK: - YAML plumbing (deliberately line-based)

    // A real YAML parser is the wrong tool here: these are three flat scalars in a block
    // Skrift itself emits, and a parser would round-trip (and so reformat) the rest of the
    // user's frontmatter. Line surgery touches only the lines it owns.

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// Is `line` the `key:` entry at the top level of the block? Indented lines are
    /// nested values (`daylight:`'s children) and never match.
    private static func isKeyLine(_ line: String, key: String) -> Bool {
        guard let colon = line.firstIndex(of: ":") else { return false }
        return String(line[line.startIndex..<colon]) == key
    }

    /// The leading `--- … ---` block, or nil when the text has no frontmatter.
    static func frontmatter(_ text: String) -> String? {
        guard text.hasPrefix("---") else { return nil }
        let lines = text.components(separatedBy: "\n")
        guard let end = lines.dropFirst().firstIndex(of: "---") else { return nil }
        return lines[1..<end].joined(separator: "\n")
    }

    /// A top-level scalar's value, trimmed of quotes and space. nil when the key is
    /// absent; "" when it's present but empty (the state `lastTouched` shipped in).
    static func value(of key: String, in frontmatter: String) -> String? {
        for line in frontmatter.components(separatedBy: "\n") where isKeyLine(line, key: key) {
            let raw = line.drop(while: { $0 != ":" }).dropFirst()
            return raw.trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        }
        return nil
    }

    /// Set `key` inside the frontmatter — replacing the line in place when it exists (so
    /// key ORDER stays stable, which keeps a re-export's diff to the values that changed),
    /// else appending just before the closing `---`. A text with no frontmatter is
    /// returned unchanged: this stamps Skrift's own compiler output, and inventing a YAML
    /// block for something else would be an edit to a file we don't own.
    static func upsert(_ text: String, key: String, value: String) -> String {
        guard text.hasPrefix("---") else { return text }
        var lines = text.components(separatedBy: "\n")
        guard let end = lines.dropFirst().firstIndex(of: "---") else { return text }
        let entry = "\(key): \(value)"
        if let i = (1..<end).first(where: { isKeyLine(lines[$0], key: key) }) {
            lines[i] = entry
        } else {
            lines.insert(entry, at: end)
        }
        return lines.joined(separator: "\n")
    }
}
