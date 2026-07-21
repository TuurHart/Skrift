# PLAN_EPUB — spike 4: EPubParse

Base SHA: a58c0d0. Ownership: `Shared/Pipeline/EPubParse.swift` (new) +
`SkriftDesktopTests/EPubParseTests.swift` (new) + `SkriftMobileTests/EPubParseTests.swift` (new,
twin). Pure Foundation only, no I/O, no singletons.

## API shape

Top-level (pinned names), all `Equatable` + `Sendable`:
- `EPubBlock { text: String, sourceFile: String }`
- `EPubTOCEntry { title: String, sourceFile: String, fragment: String? }`
- `EPubDRMVerdict { case none, case protected(reason: String) }`
- `EPubBook { blocks: [EPubBlock], toc: [EPubTOCEntry], drm: EPubDRMVerdict }`
- `enum EPubParse { static func parse(entries: [String: Data]) throws -> EPubBook }` — throwing,
  with a nested `EPubParse.ParseError: Error, Equatable { missingContainer, missingRootfile,
  missingSpine, noReadableText }`. `noReadableText` fires only when blocks end up empty AND
  `drm == .none` — a book that's empty BECAUSE it's protected returns normally (empty blocks,
  `.protected` verdict) so callers can tell "unreadable" from "encrypted".

## Internals (one file, all `private`)

- **`MiniNode`**: a tiny in-memory XML tree (qualified `name`, `attributes: [String:String]`,
  `children`, `#text` nodes for character data) built by one `XMLParser` pass
  (`shouldProcessNamespaces = false` — keeps `epub:type` etc. literal, matches the wild's
  inconsistent namespace prefixing). One generic tree builder feeds container/OPF/NCX/nav/spine-body
  parsing — no bespoke SAX delegate per format.
- `findFirst`/`findAll` — depth-first, qualified-name-suffix match (`localName` strips `ns:`
  prefix) — document order preserved, which is what TOC ordering depends on.
- **Container → OPF → spine**: `META-INF/container.xml` → `rootfile/@full-path`. OPF manifest
  parsed into `[id: ManifestItem(href, mediaType, properties)]` off `attributes` dict (order-
  independent — the GOTCHA in the brief). Spine → ordered `idref` list; blocks assembled by
  walking that list, not manifest declaration order.
- **Path resolution**: `resolvePath(base:href:)` — percent-decode, split on `/`, resolve `.`/`..`,
  strip a leading `/` (root-absolute). `directory(of:)` for the base of any file (opfDir, and each
  NCX/nav file's own dir for its `content/@src` and `<a href>` targets).
- **Body extraction, strict path**: block-level tags = `p h1-h6 li blockquote`; a `div` with no
  block-level descendant anywhere in its subtree is treated as ONE leaf block (its flattened text);
  everything else is a transparent container recursed into. `script`/`style`/`img` and anything
  footnote-flagged (`epub:type` containing `noteref`/`footnote`, or `class`/`id` containing
  `footnote`/`fn-`/`note-`, case-insensitive) is skipped entirely — not read into any block's text,
  and never descended into. `flattenText` concatenates `#text` descendants in document order,
  honoring the same skip rules so a footnote marker inside a paragraph vanishes cleanly.
- **Body extraction, lenient fallback**: triggered whenever `XMLParser` fails on a spine file
  (real `&nbsp;`-class named entities are undefined in bare XML and hard-fail the strict parser —
  this IS the detection signal, no separate well-formedness check needed). Regex pipeline on the
  decoded string: strip `script`/`style` blocks whole; best-effort strip footnote-flagged elements
  (single-tag-name, non-nested — a documented lenient-mode compromise); mark block boundaries at
  block tag start AND end (handles an unclosed tag: the next open tag still cuts a boundary); strip
  all remaining tags; THEN substitute entities (must run after tag-strip so a decoded `&lt;` isn't
  re-stripped as a tag) — named table (nbsp→space, amp/lt/gt/quot/apos, mdash/ndash/hellip/rsquo/
  lsquo/rdquo/ldquo, shy→nothing) + numeric `&#N;`/`&#xH;` via `Unicode.Scalar`; split on the
  boundary marker, collapse whitespace, drop empties.
- **TOC**: EPUB3 nav preferred — manifest item with `properties` containing token `nav`; find the
  `<nav>` whose `epub:type` token list contains `toc`; every `<a href>` inside, in document order,
  title = flattened+collapsed anchor text. Falls back to NCX (`spine/@toc` → manifest id, else
  first `application/x-dtbncx+xml` item) only if no nav item exists OR the nav yields zero entries;
  `navMap` walked depth-first, own `navLabel/text` + `content/@src` read before recursing into
  nested `navPoint`s (document order). Both split `href`/`src` on `#` into `(sourceFile, fragment)`.
- **DRM verdict**: no `META-INF/encryption.xml` → `.none` (checked first, before rights.xml — a
  bare `rights.xml` with no `encryption.xml` is untested territory in the wild and the brief's
  rule 1 gates on encryption.xml, so it reads `.none`; tabled below). Otherwise: `rights.xml`
  present → `.protected("ADEPT rights.xml present")`; else every `EncryptionMethod/@Algorithm` in
  the allowlist (`idpf.org/2008/embedding`, `ns.adobe.com/pdf/enc#RC`) → `.none`; else
  `.protected(reason:)` naming the offending/unrecognized algorithm (or "no recognized algorithm"
  if the file has no `EncryptionMethod` at all).

## Tests (twin bodies, in-source fixtures only)

One flexible `makeEPub(...)` builder (container/opf/ncx/nav/chapters/encryption/rights → `[String:
Data]`) per file, then: (1) 3-chapter EPUB2 baseline — block text/order/sourceFile + TOC
titles/targets; (2) EPUB3 nav present alongside a DIFFERENT-titled NCX — asserts nav wins by
checking the NAV titles show up, not the NCX ones; (3) manifest `<item>` attributes reordered
(href/media-type before id) — identical result to (1); (4) malformed chapter (`&nbsp;` + an
unclosed `<p>`) — asserts lenient fallback still yields non-empty blocks containing the expected
substrings (loose match — lenient-mode exact block boundaries are an implementation detail, not a
contract); (5) footnote/noteref exclusion — paragraph with an inline `epub:type="noteref"` marker
plus a sibling `epub:type="footnote"` aside; asserts the marker text and the aside body are both
gone from output; (6) 2-chapter book where chapter 2 is image-only (two `<img alt=...>`, no text)
— asserts chapter 2 contributes zero blocks, no throw, and book-level blocks come from chapter 1
only; (7) DRM — three cases (absent / font-obfuscation-only allowlisted algorithm / rights.xml
present) asserting `.none`/`.none`/`.protected` via `if case`; (8) spine idref order deliberately
different from manifest declaration order — asserts block order follows spine, not manifest.

## Uncertain decisions (tabled, not guessed silently)

1. **`linear="no"` itemrefs**: not filtered — every spine `itemref` contributes, matching the
   brief's literal contract (SPINE ORDER, no mention of linear). A cover/ad page marked
   `linear="no"` would then leak into blocks. Flip: skip itemref when `attributes["linear"] ==
   "no"`.
2. **Stray text outside any block tag** (body/section text not wrapped in `p`/`div`/etc.) is
   silently dropped — `collectBlocks` only descends into elements, `#text` children of a
   non-leaf container never become a block. Matches the brief's literal block-tag list; flip:
   treat a run of stray text as its own block, same leaf treatment as a childless div.
3. **`rights.xml` with no `encryption.xml`**: reads as `.none` (rule 1 is literally gated on
   `encryption.xml` presence, and real ADEPT files always ship both). Flip: check `rights.xml`
   presence independently of `encryption.xml`.
4. **Footnote/nav namespace prefix is assumed literal `epub:`** (`epub:type`) — the near-universal
   convention, but a document that aliases the OPS namespace to a different prefix wouldn't be
   recognized (namespace processing is off on purpose, per the base-marker's "malformed hrefs"
   lenience goal). Flip: turn on `shouldProcessNamespaces` and match by URI instead of prefix.
5. **Lenient-mode footnote stripping is single-tag-name and non-nested** (a regex `<TAG
   ...>...</TAG>` match) — good enough for the fallback path (already-malformed markup), but a
   footnote wrapper containing a same-named nested tag would truncate early. Flip: only if a real
   malformed-footnote fixture surfaces this.
