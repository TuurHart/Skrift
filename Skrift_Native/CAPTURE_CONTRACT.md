# C3 — Capture-item upload contract (mobile ↔ desktop)

The third cross-app contract addendum (after C1 quote-block shape, C2 book
metadata). **This document is the ONLY seam between the two capture lanes** —
the lanes never see each other's code. Anything on the wire is pinned here,
byte-exactly; everything else is lane-internal. Additive and optional
throughout: a server without the capture branch ignores these fields; a phone
that never captures sends none of them.

The signed-off design is `SkriftDesktop/mocks/capture-items.html` (states 1–3 +
the footnote). The mock IS the spec for both UIs.

## What a capture is

A **capture item** = something shared into Skrift from another app (URL, text
snippet, or image) + an optional typed **annotation** + a significance rating.
NO audio, NO transcription, NO diarization. The annotation is the note body.
Phone-side it is a `Memo` with `audioFilename == ""`; Mac-side a `PipelineFile`
with `sourceType == .capture`.

## Wire shape

Same endpoint, same multipart format: `POST /api/files/upload`
(`multipart/form-data`, CRLF, the exact format `MultipartBuilder` writes and
`MultipartParser` reads today).

A CAPTURE upload differs from a memo upload in exactly these ways:

1. **NO `files` part.** (A memo upload has ≥1 audio `files` part; a capture has
   zero. This absence + `metadata.sharedContent` present IS the discriminator.)
2. **NO `transcript` part.**
3. `metadata` part (`application/json`, part name `metadata`) — the standard
   `UploadMetadata` JSON with:
   - `sharedContent` — REQUIRED for a capture. Object, keys exactly:
     ```json
     {
       "type": "url" | "text" | "image" | "file",
       "url": "https://…",            // url captures
       "urlTitle": "page title",      // url captures, from the share payload (no network fetch)
       "urlDescription": "…",         // optional
       "urlThumbnailUrl": "…",        // optional, unused v1
       "text": "the shared snippet",  // text captures
       "fileName": "IMG_4321.jpeg",   // image captures: the image part's filename
       "mimeType": "image/jpeg"       // image captures
     }
     ```
     All keys optional except `type`. (This is mobile's existing `SharedContent`
     Codable — field names are already on both the model and `UploadMetadata`.)
   - `annotationText` — OPTIONAL string. The user's typed thought. May be absent
     or empty (a bare capture is legal).
   - `source`: `"mobile"`, `recordedAt`: ISO8601 share time, `duration`: `0`.
   - `significance` — present and > 0 (flag-to-send gating applies to captures
     exactly like memos: 0 = never uploaded).
   - `tags` — `[]` v1 (the sheet has no tags row by design; Mac suggests).
   - `title` — ABSENT v1 (the Mac derives/suggests; `urlTitle` rides
     sharedContent).
   - Context fields (`location`/`weather`/`capturedAt`/…) — ABSENT v1 (the
     share extension stays light; additive later).
   - Transcript-trust flags (`transcriptUserEdited`/`transcriptConfidence`) —
     irrelevant for captures; the phone sends `transcriptUserEdited: false` and
     no confidence. The desktop capture branch MUST NOT consult them.
4. `images` part — for an IMAGE capture only: exactly ONE part named `images`
   (the existing photo part), `Content-Type: image/jpeg` (or `image/png`),
   `filename` = `sharedContent.fileName`. `metadata.imageManifest` =
   `[{"filename": "<same name>", "offsetSeconds": 0}]`.

### Literal example (url capture) — both lanes test against THIS fixture

`metadata` part JSON (whitespace-insensitive; keys/values exact):

```json
{
  "sharedContent": {
    "type": "url",
    "url": "https://swiftwithmajid.com/2026/05/rich-text-editing",
    "urlTitle": "Rich text editing in SwiftUI — strategies that work"
  },
  "annotationText": "Try this for the desktop body editor — the NSTextView part maps onto what Nick suggested.",
  "tags": [],
  "source": "mobile",
  "recordedAt": "2026-06-11T14:02:00Z",
  "duration": 0,
  "transcriptUserEdited": false,
  "transcriptMarkersInjected": false,
  "significance": 0.6
}
```

Multipart body = ONLY the `metadata` part (no `files`, no `transcript`,
no `images`), standard boundary framing.

For the IMAGE variant: + one `images` part (filename `whiteboard.jpg`, any
bytes) and metadata gains `"imageManifest":[{"filename":"whiteboard.jpg",
"offsetSeconds":0}]`, sharedContent `{"type":"image","fileName":
"whiteboard.jpg","mimeType":"image/jpeg"}`.

## Desktop semantics (lane D owns the implementation)

- `UploadService.ingest`: when an upload has ZERO audio `files` parts AND
  `metadata.sharedContent` exists → create ONE `PipelineFile`:
  `sourceType: .capture`, `transcript = annotationText ?? ""`,
  `transcribeStatus = .done` (skipped — never run ASR), metadata JSON stored
  verbatim as today (`audioMetadataJSON`), significance pre-filled.
- Pipeline (BatchRunner): NO transcribe, NO diarization. **Enhancement-lite**:
  title + tags + summary run on the annotation; **NO body copy-edit** (the
  annotation is written text, not speech). Name-linking (sanitise) DOES run on
  the annotation. Empty annotation → skip LLM steps gracefully, title falls
  back to `urlTitle` / text snippet head / image filename.
- Compile/export: the **shared content pinned above the body**:
  - url → a link block: title + the URL intact (mock state 3 `sharedblock`),
    URL also in frontmatter (`url:` key); body = sanitised annotation.
  - text → the snippet as a Markdown blockquote above the annotation.
  - image → the image copied to the vault (existing image-copy path) +
    `![[filename]]` embed above the annotation.
  - frontmatter `source:` reflects a capture (e.g. `capture-url` /
    `capture-text` / `capture-image`).
- Review UI (mock state 3): sidebar glyph per type (link/text/image), row meta
  "Link · phone"; toolbar swaps the audio transport for the source strip
  (domain + Open ↗); capture banner ("skipped transcription & diarization …");
  properties grid gains the `url` row.

## Mobile semantics (lane M owns the implementation)

- New share-extension target (`SkriftShare`) + App Group
  (`group.com.skrift.mobile` Release / `group.com.skrift.mobile.dev` Debug).
  The extension writes an inbox entry (JSON + optional image file) into the
  App Group container; the MAIN APP drains the inbox on launch/foreground →
  creates the `Memo` (`audioFilename: ""`, `sharedContent`, `annotationText`,
  `significance`, `transcriptStatus: .done`, `syncStatus: .waiting`).
- Sheet UI per mock state 1: preview block per type, annotation field,
  significance circles + sync line, Save. No tags, no title, NO mic v1.
- `UploadPayload` capture variant: builds the multipart WITHOUT the audio
  part per the wire shape above. `SyncCoordinator` uploads captures through
  the same significance>0 gate as memos.
- List/detail per mock state 2 (glyph row + pinned link card + annotation
  body; no player bar — `memo.audioURL == nil`).

## Invariants

- A memo upload (with audio) is BYTE-IDENTICAL to today — captures are a new
  branch, not a change to the existing one.
- The phone NEVER sends `sanitised`; name-linking stays Mac-side (unchanged).
- Flag-to-send: significance 0 stays on the phone (unchanged, applies to
  captures).
