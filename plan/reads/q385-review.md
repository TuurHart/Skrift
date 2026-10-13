# Q390: shared-code and cleanliness review of the attachments build (Q385, Q385b, Q391)

Scope: every commit tagged Q385 / Q385b / Q391 since 4519b3ea (14 commits, 54 files). Periphery
2.21.2, plan/periphery.md flags, on a `git archive` snapshot of the session head 54745d67:
Mac 288 findings, phone 329; only the ones in files those commits touched were triaged.

## Shared (twins folded into Shared/)

- `Shared/Pipeline/NoteAttachment+Memo.swift` (new): `videoDuration(of:)` and
  `makeEntry(owner:number:source:originalName:uti:byteCount:)` replace the identical
  `NoteAttachmentStore.duration(of:)` and `MacNoteAttachments.duration(of:)` and the two
  "video ? duration : nil" call sites; `capturedFilename(of:)` + `allFilenames(of:)` replace
  `NoteAttachmentStore.pdfFilename/allFilenames` and `MacNoteAttachments.allFilenames`;
  `setSize(_:filename:all:on:)` is the one size switch, the two app `setSize` functions are now
  one line over it (the Mac adds its save and redraw notice; both kept because protected tests
  call them). Drift fixed on the way: the Mac's Set All left out the captured PDF, so Set All
  to Large on the Mac left the phone's PDF small. Both apps now switch the same list.
- `NoteAttachment.isPicture / isVideo / isMedia(literal:)`: the hold menu's Copy / Save facts,
  computed two different ways (phone by manifest lookup, Mac by marker parse).
- Phone selection-bar size switch now reads `NoteAttachment.BlockAction.setSize` title and
  symbol instead of retyping "View as Small/Large" and the two SF Symbols.
- `NoteAttachmentArt.photoCard` / `pdfCard` / new `fileCard` go through the painter's cache,
  keyed by file size + change time. Before, every note open and every editor reload decoded a
  photo thumbnail per small photo on the main thread (photos are small by default since
  Q385b), and the phone's SwiftUI body redrew the PDF card image on every pass.

## Deleted

- Phone `captureFileCard`'s old body (purple-tint doc glyph, "Open" button, `capture-open-file`):
  replaced by the shared grey file card (`NoteAttachmentArt.fileCard`,
  `NoteAttachment.capturedFileCard`), whole card opens Quick Look (mock pick 4, D202). Q385 had
  left the old card in place for non-PDF captured documents.
- `NoteAttachmentStore.naturalSize(of:)` (no caller; posters carry the frame size now).
- `NotePoster.forget(_:)` (no caller anywhere, tests included).
- Phone `Coordinator.movePhoto(marker:toDisplayLocation:)` (no caller since the drag goes
  through `moveBlock`).
- `presentPDF` renamed `presentCapturedFile` (it opens any captured file) and moved out of the
  middle of `photoWasEdited`'s doc comment, which Q385b had split.
- `import AVFoundation` from `NoteAttachmentStore.swift` and `MacNoteAttachments.swift`.

## Comments corrected

- `NoteAttachment.blockShaped` said "both apps"; only the phone editor calls it.

## Stays on purpose

- twin-ok: inline video player. Phone `AVPlayerViewController` child, Mac `AVPlayerView`
  subview: different AVKit classes per platform; the rule (large video plays inline, else
  Quick Look) is the same and short.
- twin-ok: `refreshPoster` in `NoteBodyView` and `BodyTextView`. Each walks its own text
  system's attachment runs (UIKit attribute key vs `NoteBlockAttachment`).
- twin-ok: Save to Files (phone `UIDocumentPickerViewController`) vs Save to Downloads (Mac
  `NoteBlockFileActions.saveToDownloads`), and Share (UIActivityViewController vs
  NSSharingServicePicker): each needs the platform presenter.
- twin-ok: the small-photo card call in phone `imageAttachment` and Mac `splice` (3 lines each):
  the baseline offset differs per text system (y -4 vs 0).
- CHECK, test-only (Q61 rule): `NoteAttachment.slot(...)` (NoteAttachmentExportTests),
  `NotePoster.generationCount` (NotePosterTests), `BodyFormat.movePhoto` (three test files),
  `MacNoteAttachments.Added.fileURL` (NoteAttachmentExportTests).
- Dead parameter kept: `NoteAttachment.blockActions(shareable:)` is only ever `false` in app code,
  but protected `NoteBlockRulesTests` asserts the `true` case. Removing it needs Tuur's yes.
- False positives: `BodyTextView.StyleKey` fields (synthesized Equatable). The Mac scan's
  `inserting`, `exportName`, `convertMarkers`, `inlineVideoStarted` and `attachmentViewTitle`
  show as unused on the phone scan only because the Mac calls them.
- Photo / PDF default size untouched (Tuur is deciding).

## Left for a follow-up (not done here)

- The phone page (`MemoPageView`) and the iPad toolbar (`IPadNoteToolbar`) each chain the same
  camera cover + photos picker + file importer onto `NoteAttachIntake`: a phone-internal twin
  that would fold into one ViewModifier.
- The captured PDF's SwiftUI `.contextMenu` in `MemoPageView` builds Copy / Share / size by hand
  and has no Save; it could list `NoteAttachment.holdMenu(... editing: false)`.
- The Mac capture card (`CaptureViews.fileCard`) still has its own "Open" button; Q385 never
  touched the Mac capture block, so pick 4 is phone-only so far.
- `PDFThumbnailLoader.firstPage` runs inside the phone page's body (pre-Q385).
