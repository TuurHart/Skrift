import Foundation

extension Sanitiser {
    // MARK: - Tiered name spans over the RAW transcript (phone in-place linking)

    /// Tiered name occurrences over the RAW transcript — the phone's in-place
    /// name-linking touch surface (`mocks/phone-name-linking.html`). Makes the SAME
    /// linking decisions as `process` (identical `Overrides`, identical earliest-
    /// eligible-safe first mention, identical `suggestedOccurrences`) but RECORDS spans
    /// at their RAW offsets instead of mutating the text — so the phone styles the
    /// spoken word in place and the transcript stays RAW (the contract spine). One
    /// LINKED span per linked person (first mention only); later mentions + pronouns are
    /// plain. Monologue only — diarized conversations render through `SpeakerTurnsView`,
    /// which does its own alias-display linking. Deterministic, LLM-free.
    ///
    /// A linked span's `candidates` carry EVERY live person who shares the matched alias,
    /// so the UI can offer "Change person…" only when 2+ exist (a force-picked ambiguous
    /// "Jack"), and just Unlink/Open for a uniquely-owned name ("Hendri").
    static func nameSpans(inRaw raw: String, people: [Person],
                          neverLink: Set<String> = [], namePicks: [String: String] = [:]) -> [NameSpan] {
        guard !raw.isEmpty else { return [] }
        let ov = Overrides(people: people, neverLink: neverLink, namePicks: namePicks)
        let prot = nonProseRanges(in: raw)
        var spans: [NameSpan] = []
        var linkedKeys = Set<String>()

        func candidate(_ p: Person) -> NameCandidate {
            NameCandidate(id: p.canonical, canonical: p.canonical, short: shortName(for: p))
        }
        // Every live person who declares `alias` (case-insensitive) — drives the
        // ambiguity of a LINKED span (≥2 ⇒ offer "Change person…").
        func sharers(of alias: String) -> [Person] {
            let a = alias.trimmingCharacters(in: .whitespaces).lowercased()
            guard !a.isEmpty else { return [] }
            return ov.live.filter { p in
                p.aliases.contains { $0.trimmingCharacters(in: .whitespaces).lowercased() == a }
            }
        }
        // The match range minus any trailing possessive (`Jack's` → `Jack`), so the
        // linked token is the bare name and the `'s` stays plain — matching `process`,
        // which writes the possessive OUTSIDE the brackets.
        func nameOnly(_ m: NSTextCheckingResult) -> NSRange {
            let poss = m.range(withName: "poss")
            guard poss.location != NSNotFound, poss.length > 0 else { return m.range }
            return NSRange(location: m.range.location, length: m.range.length - poss.length)
        }
        // Drop a trailing possessive from a recorded occurrence's range (the
        // `suggestedOccurrences` length INCLUDES the `'s`), so the span text is the bare
        // spoken word and the resolution key is clean.
        func stripPoss(offset: Int, length: Int) -> NSRange {
            let s = nsSub(raw, offset, offset + length) as NSString
            for suffix in ["'s", "\u{2019}s"] where s.hasSuffix(suffix) {
                return NSRange(location: offset, length: length - (suffix as NSString).length)
            }
            return NSRange(location: offset, length: length)
        }

        // First-mention LINKED span per linkable / force-picked person (sorted by
        // canonical) — the SAME person `process` would link first, recorded at its RAW
        // offset (no bracket written).
        for p in ov.linkPeople {
            let canonKey = NamesMerge.keyName(p.canonical).trimmingCharacters(in: .whitespaces)
            let unambiguous = ov.ownedAliases(of: p).filter { !ov.ambiguousAliases.contains($0.lowercased()) }
            let linkAliases = unambiguous.filter { !NameStoplist.isFpProne($0) || ov.forced[$0.lowercased()] != nil }

            // A raw transcript may already carry this person's canonical link (a diarized
            // fragment passing through) — that earliest link is the first mention.
            if let first = linkOccurrences(of: canonKey, in: raw).first {
                let shown = first.core.contains("|") ? (first.core.split(separator: "|").last.map(String.init) ?? canonKey) : canonKey
                spans.append(NameSpan(offset: first.range.location, length: first.range.length,
                                      alias: shown, tier: .linked, canonical: p.canonical,
                                      candidates: { let s = sharers(of: shown); return s.isEmpty ? [candidate(p)] : s.map(candidate) }()))
                linkedKeys.insert(canonKey.lowercased())
                continue
            }
            guard !linkAliases.isEmpty else { continue }
            var earliest: NSTextCheckingResult?
            for rx in linkAliases.compactMap({ wordRegex($0) }) {
                for m in rx.matches(in: raw, range: fullRange(raw)) where eligible(raw, m.range.location, prot) {
                    if earliest == nil || m.range.location < earliest!.range.location { earliest = m }
                    break
                }
            }
            guard let m = earliest else { continue }
            let r = nameOnly(m)
            let shownAlias = nsSub(raw, r.location, r.location + r.length)
            let cands = sharers(of: shownAlias)
            spans.append(NameSpan(offset: r.location, length: r.length, alias: shownAlias,
                                  tier: .linked, canonical: p.canonical,
                                  candidates: cands.isEmpty ? [candidate(p)] : cands.map(candidate)))
            linkedKeys.insert(canonKey.lowercased())
        }

        // SUGGESTED + AMBIGUOUS tiers — reuse the EXACT `process` machinery over RAW.
        // `AmbiguousOccurrence.alias` is the lowercased roster KEY; the displayed token
        // is the SURFACE form (`Jack`, not `jack`), so read it back from the raw text
        // (possessive stripped).
        for occ in suggestedOccurrences(in: raw, overrides: ov, linkedKeys: linkedKeys) {
            let r = stripPoss(offset: occ.offset, length: occ.length)
            spans.append(NameSpan(offset: r.location, length: r.length,
                                  alias: nsSub(raw, r.location, r.location + r.length),
                                  tier: occ.candidates.count >= 2 ? .ambiguous : .suggested,
                                  canonical: occ.candidates.count == 1 ? occ.candidates[0].canonical : nil,
                                  candidates: occ.candidates))
        }

        // PLAIN (leftplain) tier — a SILENCED alias (`namePicks[alias] == ""`, the
        // reversible "keep as plain text" / unlink gesture) that still belongs to ≥1 live
        // person stays a faint dotted, re-tappable token so it can be re-linked inline.
        // The silence already suppressed any link/suggestion above, so these never overlap.
        for (rawAlias, canon) in namePicks where canon.trimmingCharacters(in: .whitespaces).isEmpty {
            let alias = rawAlias.trimmingCharacters(in: .whitespaces)
            let cands = sharers(of: alias)
            guard !cands.isEmpty, let rx = wordRegex(alias) else { continue }
            for m in rx.matches(in: raw, range: fullRange(raw)) where eligible(raw, m.range.location, prot) {
                let r = stripPoss(offset: m.range.location, length: m.range.length)
                spans.append(NameSpan(offset: r.location, length: r.length,
                                      alias: nsSub(raw, r.location, r.location + r.length),
                                      tier: .plain, canonical: nil, candidates: cands.map(candidate)))
            }
        }

        return spans.sorted { $0.offset < $1.offset }
    }

}
