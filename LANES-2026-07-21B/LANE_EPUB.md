# LANE_EPUB — spike 4: EPubParse, the pure ePub → book-text extractor

Read `LANE_PLAYBOOK.md` then `LANES-2026-07-21B/BASE.md` first (base check, ownership,
pinned names, pure-Foundation rule). Then this brief. Then write your PLAN, commit, execute.

## The question
Turn an ALREADY-UNZIPPED ePub (`[String: Data]` — archive path → bytes; the conductor's
ZIPFoundation wrapper supplies it later) into `EPubBook { blocks: [EPubBlock], toc:
[EPubTOCEntry], drm: EPubDRMVerdict }` — the book text the aligner consumes and the TOC the
chapter feature consumes. Real-world-lenient, deterministic, pure Foundation.

## Contract (from the locked design, backlog 📖 item 5 + probe findings)

1. **Container → OPF → spine.** Parse `META-INF/container.xml` for the rootfile path; parse
   the OPF manifest + spine; blocks come out in SPINE ORDER. GOTCHA (hit live on the real
   Steal ePub): manifest `<item>` attribute order is NOT guaranteed — never regex on
   `id=…href=…` adjacency; parse attributes properly (XMLParser gives you a dict).
2. **TOC, both generations:** EPUB2 `toc.ncx` (`navMap/navPoint` → title + content src) and
   EPUB3 nav document (`epub:type="toc"` nav → li/a). Prefer the EPUB3 nav when both exist.
   `EPubTOCEntry { title: String, sourceFile: String, fragment: String? }`.
3. **Body text extraction, LENIENT:** strict `XMLParser` first; if a spine file fails to
   parse (real files: `&nbsp;`-style named entities + malformed markup hard-fail XMLParser),
   fall back to: named-entity substitution table (nbsp amp lt gt quot apos mdash ndash
   hellip rsquo lsquo rdquo ldquo shy + numeric `&#N;`/`&#xH;`) + tag-strip + whitespace
   collapse. Either path yields BLOCKS at paragraph granularity (block-level elements:
   p, h1–h6, li, blockquote; a div with no block children = one block). `EPubBlock.text`
   keeps the ORIGINAL display text (punctuation, case); the aligner normalizes internally.
4. **Exclusions:** script/style entirely; `<img>` contributes NOTHING (alt text is NEVER
   book text — BASE.md); footnotes excluded via `epub:type="noteref"`/`"footnote"` +
   class/id heuristics (contains "footnote"/"fn-"/"note-"); empty/whitespace blocks dropped.
5. **DRM verdict** (`EPubDRMVerdict`): no `META-INF/encryption.xml` → `.none`. Present →
   parse algorithm URIs; if EVERY algorithm is one of the two font-obfuscation URIs
   (`http://www.idpf.org/2008/embedding`, `http://ns.adobe.com/pdf/enc#RC`) → still `.none`
   (fonts only, book text fine). `META-INF/rights.xml` present OR any other algorithm →
   `.protected(reason: String)` with an honest human-readable reason. NEVER attempt bypass.
6. API shape: `EPubParse.parse(entries: [String: Data]) -> EPubBook` (+ small pure helpers
   as needed). Throwing or Result — your call, state it in your PLAN; a book with zero
   readable spine text should surface as an error/empty distinguishable from DRM.

## Tests (twin files, identical bodies — desktop test bundle compiles Shared directly;
## mobile via @testable import)
In-source fixtures (build the `[String: Data]` dicts from string literals — you're testing
the parser, not a zip): a minimal 3-chapter EPUB2 (container+OPF+NCX+3 XHTML) · an EPUB3
variant with nav doc (nav preferred over NCX) · attribute-order-swapped OPF manifest ·
a malformed chapter (`&nbsp;` + unclosed tag) that MUST fall back leniently and still yield
text · footnote/noteref exclusion · an image-only "chapter" (blocks empty, no crash, alt
ignored) · DRM: absent / font-obfuscation-only / ADEPT-style (rights.xml) · spine order ≠
manifest order. Assert block TEXT content, order, sourceFile stamping, TOC titles+targets.

## Wrap
Playbook wrap block. Your uncertain-decisions table matters here — real-world ePub weirdness
is exactly where silent guesses poison things; when the spec above doesn't cover a case,
pick conservatively and TABLE it.
