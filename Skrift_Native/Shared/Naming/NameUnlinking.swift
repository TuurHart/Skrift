import Foundation

extension Sanitiser {
    // MARK: - Unlinking (review-time "unlink a [[Name]]" — mocks/name-unlink.html)

    /// A wiki link in the body: the full `[[…]]` range (brackets included) + the
    /// core text inside the brackets.
    struct BodyLink: Equatable {
        var range: NSRange
        var core: String
    }

    static let bodyLinkRegex = try? NSRegularExpression(pattern: #"\[\[([^\]]+)\]\]"#)

    /// Every `[[Name]]` wiki link in `text`, in reading order. `[[img_NNN]]` image
    /// markers are markers, not links — skipped. Drives the clickable linked-mention
    /// detection in the review body.
    static func linkOccurrences(in text: String) -> [BodyLink] {
        guard let rx = bodyLinkRegex else { return [] }
        let ns = text as NSString
        return rx.matches(in: text, range: fullRange(text)).compactMap { m in
            let core = ns.substring(with: m.range(at: 1))
            guard core.range(of: #"^img_\d+$"#, options: .regularExpression) == nil else { return nil }
            return BodyLink(range: m.range, core: core)
        }
    }

    /// One person's `[[canonical]]` links in `text` (core match is case-insensitive,
    /// brackets/whitespace tolerated on `canonical`), in reading order. The i-th
    /// entry here is what `unlinkOccurrence(index: i)` / `relinkOccurrence(index: i)`
    /// replaces — order-based, so storage-offset drift can't misapply.
    static func linkOccurrences(of canonical: String, in text: String) -> [BodyLink] {
        let key = NamesMerge.keyName(canonical).trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { return [] }
        return linkOccurrences(in: text).filter {
            linkTarget($0.core).caseInsensitiveCompare(key) == .orderedSame
        }
    }

    /// The canonical TARGET of a link's inner text — the part before an Obsidian
    /// alias-display pipe (`Tiuri Hartog|Tuur` → `Tiuri Hartog`), trimmed. So a
    /// `[[Canonical|spoken]]` alias-display link still resolves to its person for
    /// unlink/relink/highlight (the spoken word is display-only).
    static func linkTarget(_ core: String) -> String {
        (core.split(separator: "|", maxSplits: 1).first.map(String.init) ?? core)
            .trimmingCharacters(in: .whitespaces)
    }

    /// True when `text` already carries a `[[canonKey]]` OR `[[canonKey|display]]` link
    /// (case-insensitive) — the pipe-tolerant replacement for a literal `[[Canonical]]`
    /// substring search, so the alias-display form is recognised as an existing mention.
    static func hasCanonicalLink(_ canonKey: String, in text: String) -> Bool {
        let key = NamesMerge.keyName(canonKey).trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty,
              let rx = try? NSRegularExpression(
                pattern: "\\[\\[\(NSRegularExpression.escapedPattern(for: key))(\\|[^\\]]*)?\\]\\]",
                options: [.caseInsensitive]) else { return false }
        return rx.firstMatch(in: text, range: fullRange(text)) != nil
    }

    /// "Unlink this mention": the `index`-th `[[canonical]]` link (reading order)
    /// becomes the plain `alias` as spoken. Order-based, so the UI's storage offsets
    /// (image attachments collapse `[[img_NNN]]` markers to one character) can't
    /// misapply. A possessive sits OUTSIDE the brackets (`[[Nick Jansen]]'s`) and is
    /// left in place → `Nick's`. An out-of-range index returns the text unchanged.
    static func unlinkOccurrence(text: String, canonical: String, index: Int, alias: String) -> String {
        let links = linkOccurrences(of: canonical, in: text)
        guard index >= 0, index < links.count else { return text }
        return nsReplace(text, links[index].range, with: linkDisplay(links[index].core) ?? alias)
    }

    /// The display half of an alias-display link's core (`Tiuri Hartog|Tuur` → `Tuur`),
    /// i.e. the actual SPOKEN word — what an unlink should restore. nil for a bare
    /// `[[Canonical]]` link (no pipe), where the caller's `alias` fallback applies.
    static func linkDisplay(_ core: String) -> String? {
        let parts = core.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        let display = parts[1].trimmingCharacters(in: .whitespaces)
        return display.isEmpty ? nil : display
    }

    /// "Change to → <other person>": the `index`-th `[[canonical]]` link becomes
    /// `[[newCanonical]]` — the one-tap fix when the deterministic alias match
    /// picked the WRONG person (a spoken "Jack" auto-linked to Timmons but meant
    /// Hutton). Order-based like `unlinkOccurrence`; out-of-range = unchanged.
    static func relinkOccurrence(text: String, canonical: String, index: Int, newCanonical: String) -> String {
        let links = linkOccurrences(of: canonical, in: text)
        guard index >= 0, index < links.count else { return text }
        // Preserve an alias-display spoken word across the re-link (`[[Wrong|Tuur]]` →
        // `[[Right|Tuur]]`); a bare link stays bare.
        let repl = linkDisplay(links[index].core).map { "[[\(newCanonical)|\($0)]]" } ?? "[[\(newCanonical)]]"
        return nsReplace(text, links[index].range, with: repl)
    }

    /// "Unlink all mentions in this note": EVERY `[[canonical]]` link becomes the
    /// plain `alias`. Plain mentions are already plain and other links (other
    /// people, image markers, place links) are untouched. The caller persists the
    /// choice (`PipelineFile.unlinkedNames`) and feeds it back via
    /// `process(neverLink:)` so re-processing doesn't re-link.
    static func unlinkAll(text: String, canonical: String, alias: String) -> String {
        var out = text
        for link in linkOccurrences(of: canonical, in: text).reversed() {
            out = nsReplace(out, link.range, with: linkDisplay(link.core) ?? alias)
        }
        return out
    }

    /// Un-link EVERY known person's `[[wiki link]]` back to their SPOKEN form (the alias-display
    /// word for a `[[Canonical|spoken]]` link, else the person's short name) — the inverse of
    /// `process`, so `unlinkToSpoken` → `process` round-trips. Used by the Mac→phone live-edit
    /// write-back: the phone stores a RAW copy-edit (bracket-free editor) and re-links itself,
    /// so a manual Mac body edit must be sent un-linked to the spoken word — NOT the bare
    /// canonical, which would re-link as `[[Nick Jansen]] Jansen` (the linker re-matches the
    /// "Nick" alias inside "Nick Jansen"). Image markers (`[[img_NNN]]`) and links to people not
    /// in `people` are left untouched.
    static func unlinkToSpoken(_ text: String, people: [Person]) -> String {
        var out = text
        for p in people {
            out = unlinkAll(text: out, canonical: p.canonical, alias: spokenAlias(for: p))
        }
        return out
    }

    /// The plain text a mention reads as once unlinked — the SAME short-name rule
    /// `process` uses when demoting later mentions (short override → first word of
    /// the canonical), falling back to the bare canonical.
    static func spokenAlias(for p: Person) -> String {
        let short = shortName(for: p)
        if !short.isEmpty { return short }
        return NamesMerge.keyName(p.canonical).trimmingCharacters(in: .whitespaces)
    }

}
