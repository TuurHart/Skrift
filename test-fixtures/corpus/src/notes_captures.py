"""Captures (the share sheet: URL / text / image / file) and video imports.

A capture has no recording of its own; the body is the annotation (typed or spoken) and
the shared thing rides `sharedContent`. Shapes: URL with and without a fetched title, a
YouTube and an Instagram URL, URL + voice ramble, URL + typed annotation, a plain text
share, a long article as text, an image share with no words, image + ramble, image +
typed note, a PDF file share with its extracted text, a plain-text file share, a Dutch
annotation, a link-only capture with no comment, and three video imports.
"""

WORKSHOP = {"latitude": 51.9139, "longitude": 4.4760, "placeName": "Werkplaats, Rotterdam-Zuid"}

ARTICLE = (
    "Why iron makes blue glazes go green\n\n"
    "Most studio potters meet this the same way: a cobalt blue that looks perfect on a white "
    "body turns olive at the edges on a darker one. The culprit is usually not the glaze at all "
    "but iron oxide in the clay body migrating into the glaze layer during the melt.\n\n"
    "At cone 6 the migration is stronger than at cone 5, which is why the same glaze can look "
    "right at the lower temperature and wrong at the higher one. Two fixes exist: switch to a "
    "lower-iron body, or add a slip layer that seals the body under the glaze.\n\n"
    "Neither is free. A new body means re-testing every glaze you own, and a slip adds a step "
    "to every piece. But it is the difference between a blue and a green."
)

NOTES = [
    {
        "slug": "cap-url-with-title",
        "kind": "capture", "lang": "en",
        "shape": ["capture", "url", "annotation-typed"],
        "transcript": "Ines sent this. The bit about iron migrating at cone 6 explains the green edge.",
        "annotationText": "Ines sent this. The bit about iron migrating at cone 6 explains the green edge.",
        "sharedContent": {"type": "url", "url": "https://en.wikipedia.org/wiki/Ceramic_glaze",
                          "urlTitle": "Ceramic glaze - Wikipedia",
                          "urlDescription": "A ceramic glaze is an impervious layer or coating applied to bisqueware..."},
        "tags": ["glaze"],
        "significance": 0.6,
        "expect": {"note": "URL capture with a fetched title: export renders a link card/line with the title, the annotation as the body."},
    },
    {
        "slug": "cap-url-no-title",
        "kind": "capture", "lang": "en",
        "shape": ["capture", "url", "no-title"],
        "transcript": "Bookmarking this before I lose it.",
        "annotationText": "Bookmarking this before I lose it.",
        "sharedContent": {"type": "url", "url": "https://app.example-glaze-calc.com/#/recipe/8813"},
        "tags": [],
        "significance": 0.4,
        "expect": {"bug": "JS-rendered page: no title fetched. v1 shows the bare URL as the title. Expected: a readable fallback (the host), never the whole URL as a title."},
    },
    {
        "slug": "cap-url-youtube",
        "kind": "capture", "lang": "en",
        "shape": ["capture", "url", "youtube"],
        "transcript": "Throwing wide bowls, the trick at 4:10 with the rib.",
        "annotationText": "Throwing wide bowls, the trick at 4:10 with the rib.",
        "sharedContent": {"type": "url", "url": "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
                          "urlTitle": "Throwing a wide bowl — studio demo", "urlThumbnailUrl": "https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg"},
        "tags": ["throwing"],
        "significance": 0.5,
        "expect": {"needs-verdict": "YouTube = a link card with the title (today), or fetch the audio and transcribe it into the note?"},
    },
    {
        "slug": "cap-url-instagram",
        "kind": "capture", "lang": "en",
        "shape": ["capture", "url", "instagram"],
        "transcript": "",
        "annotationText": "",
        "sharedContent": {"type": "url", "url": "https://www.instagram.com/p/C0rpusExample/"},
        "tags": ["inspiration"],
        "destination": "inspiration",
        "significance": 0.5,
        "expect": {"needs-verdict": "Instagram share with no comment: is the caption the body? Today it is a bare link with no title (login-walled fetch)."},
    },
    {
        "slug": "cap-url-voice-ramble",
        "kind": "capture", "lang": "en",
        "shape": ["capture", "url", "annotation-voice"],
        "transcript": "So Bruno, um, Bruno sent me this frame builder in Porto, lugged steel, and I, I think this is the one for the touring bike. Look at the, the seat cluster.",
        "annotationText": "So Bruno, um, Bruno sent me this frame builder in Porto, lugged steel, and I, I think this is the one for the touring bike. Look at the, the seat cluster.",
        "sharedContent": {"type": "url", "url": "https://example-frames.pt/lugged", "urlTitle": "Lugged steel frames — handmade in Porto"},
        "tags": ["bikes"],
        "significance": 0.7,
        "expect": {"note": "A spoken annotation on a URL: copy-edit applies to the ramble, the link stays a link."},
    },
    {
        "slug": "cap-text-plain",
        "kind": "capture", "lang": "en",
        "shape": ["capture", "text"],
        "transcript": "From a message: “Kiln wash: 50/50 kaolin and alumina hydrate, thin, two coats, let each dry.”",
        "annotationText": "From a message: “Kiln wash: 50/50 kaolin and alumina hydrate, thin, two coats, let each dry.”",
        "sharedContent": {"type": "text", "text": "Kiln wash: 50/50 kaolin and alumina hydrate, thin, two coats, let each dry."},
        "tags": ["studio"],
        "significance": 0.5,
        "expect": {"needs-verdict": "A text share: is the shared text the body, the annotation the body, or both (quote + comment)?"},
    },
    {
        "slug": "cap-text-article",
        "kind": "capture", "lang": "en",
        "shape": ["capture", "text", "long"],
        "transcript": "",
        "annotationText": "",
        "sharedContent": {"type": "text", "text": ARTICLE},
        "tags": ["glaze"],
        "significance": 0.6,
        "expect": {"note": "A long text share with no annotation: the body should be the text, paragraphs intact."},
    },
    {
        "slug": "cap-image-no-words",
        "kind": "capture", "lang": "en",
        "shape": ["capture", "image", "no-annotation"],
        "transcript": "",
        "annotationText": "",
        "sharedContent": {"type": "image", "fileName": "IMG_4471.jpg", "mimeType": "image/jpeg"},
        "photos": [{"offsetSeconds": 0, "portrait": True}],
        "tags": [],
        "significance": 0.5,
        "expect": {"bug": "A bare shared photo: processed with NO content stalled forever before 2026-08-26. Expected: processed, no polish, exports as an image note."},
    },
    {
        "slug": "cap-image-voice-ramble",
        "kind": "capture", "lang": "en",
        "shape": ["capture", "image", "annotation-voice", "shared-picture"],
        "transcript": "This is the, the lamp base from the market, the matte blue, um, electric kiln cone five he said.",
        "annotationText": "This is the, the lamp base from the market, the matte blue, um, electric kiln cone five he said.",
        "sharedContent": {"type": "image", "fileName": "IMG_4472.jpg", "mimeType": "image/jpeg"},
        "photos": [{"offsetSeconds": 0}],
        "tags": ["glaze", "inspiration"],
        "destination": "inspiration",
        "significance": 0.8,
        "expect": {"bug": "THE WhatsApp/shared-picture bug: offset 0 puts the marker after the first word. Expected: picture at the TOP, the ramble below it as one paragraph."},
    },
    {
        "slug": "cap-image-typed-note",
        "kind": "capture", "lang": "nl",
        "shape": ["capture", "image", "annotation-typed", "dutch"],
        "transcript": "Whiteboard van het overleg met Lotte: de indeling van de zaterdag.",
        "annotationText": "Whiteboard van het overleg met Lotte: de indeling van de zaterdag.",
        "sharedContent": {"type": "image", "fileName": "whiteboard.jpg", "mimeType": "image/jpeg"},
        "photos": [{"offsetSeconds": 0, "bigText": "10:00 KLEI / 11:00 VORM", "text": "10:00 KLEI / 11:00 VORM"}],
        "tags": ["workshop"],
        "significance": 0.6,
    },
    {
        "slug": "cap-file-pdf",
        "kind": "capture", "lang": "en",
        "shape": ["capture", "file", "pdf"],
        "transcript": "Marco's quote for the kiln line. Nine metres, dedicated 16 A, €640 plus the box.",
        "annotationText": "Marco's quote for the kiln line. Nine metres, dedicated 16 A, €640 plus the box.",
        "sharedContent": {"type": "file", "mimeType": "application/pdf"},
        "sharedFile": {"file": "document.pdf", "filename": "capture_quote_kiln.pdf", "displayName": "Offerte kiln lijn.pdf",
                       "title": "Offerte — kiln voedingslijn", "body": "Dedicated 16 A groep, 9 m, incl. kabelgoot\nArbeid 4 uur\nTotaal € 640,00 excl. verdeelkast"},
        "tags": ["studio", "money"],
        "significance": 0.7,
        "expect": {"note": "The document stays on the phone (MemoAsset kind document); its extracted text is the body (A6); the Mac gets the file under files/ and can open it."},
    },
    {
        "slug": "cap-file-txt",
        "kind": "capture", "lang": "en",
        "shape": ["capture", "file", "text-file"],
        "transcript": "",
        "annotationText": "",
        "sharedContent": {"type": "file", "mimeType": "text/plain"},
        "sharedFile": {"file": "recipe.txt", "filename": "capture_recipe.txt", "displayName": "blue-3.txt",
                       "body": "Blue #3\nNepheline syenite 45\nSilica 25\nWhiting 15\nKaolin 10\nCobalt carbonate 1.5\nRutile 3"},
        "tags": ["glaze"],
        "significance": 0.5,
        "expect": {"needs-verdict": "A .txt file share with no annotation: body = the file's text, or an attachment card only?"},
    },
    {
        "slug": "cap-url-dutch-annotation",
        "kind": "capture", "lang": "nl",
        "shape": ["capture", "url", "dutch"],
        "transcript": "Dit is die veerpont bij Enkhuizen, tijden staan onderaan. Voor het IJsselmeer-weekend met Lotte.",
        "annotationText": "Dit is die veerpont bij Enkhuizen, tijden staan onderaan. Voor het IJsselmeer-weekend met Lotte.",
        "sharedContent": {"type": "url", "url": "https://www.example-veerpont.nl/enkhuizen-stavoren", "urlTitle": "Veerpont Enkhuizen – Stavoren | dienstregeling"},
        "tags": ["fietsen", "weekend"],
        "significance": 0.4,
    },
    {
        "slug": "cap-url-link-only",
        "kind": "capture", "lang": "en",
        "shape": ["capture", "url", "no-annotation"],
        "transcript": "",
        "annotationText": "",
        "sharedContent": {"type": "url", "url": "https://digitalfire.com/glossary/iron+oxide", "urlTitle": "Iron Oxide - Digitalfire"},
        "tags": [],
        "significance": 0.3,
        "expect": {"note": "A link with no comment: processed-with-no-content contract; the export is the link line + title, nothing else."},
    },
    # ---- video imports (audio strip + one frame) ------------------------------------
    {
        "slug": "video-portrait",
        "kind": "video", "lang": "en",
        "shape": ["video", "pictures", "portrait"],
        "transcript": "[[img_001]]\n\nAdvice to future me, recorded on the balcony: do not say yes to a workshop before checking the calendar.",
        "recordedAt": "2026-08-02T19:30:00+01:00",
        "createdAt": "2026-09-16T10:00:00+01:00",
        "photos": [{"offsetSeconds": 0, "portrait": True}],
        "tags": ["thinking"],
        "significance": 0.5,
        "expect": {"note": "Video import: recordedAt = the filming date (Aug 2), createdAt = the import (Sep 16). The frame is the first paragraph; portrait aspect must not stretch."},
    },
    {
        "slug": "video-landscape",
        "kind": "video", "lang": "nl",
        "shape": ["video", "pictures", "landscape", "dutch"],
        "transcript": "[[img_001]]\n\nKorte video van het draaien van de brede schaal, voor Ines, zodat ze ziet wat er misgaat bij de rand.",
        "photos": [{"offsetSeconds": 0}],
        "tags": ["throwing"],
        "significance": 0.4,
    },
    {
        "slug": "video-no-speech",
        "kind": "video", "lang": "en",
        "shape": ["video", "pictures", "empty-transcript"],
        "transcript": "[[img_001]]",
        "photos": [{"offsetSeconds": 0}],
        "tags": [],
        "significance": 0.5,
        "expect": {"note": "A video with no speech: the note is the frame alone. Processed, no content; export = the image."},
    },
]
