"""Voice notes with pictures taken DURING the recording — the body/image model's home turf.

A photo has a real moment (`imageManifest.offsetSeconds`) and the phone drops a
`[[img_NNN]]` marker at the word nearest that moment. Shapes: a marker mid-sentence, at
the very start, at the end, two photos in the same second, three spread out, OCR text in
the manifest, a marker whose file is missing, a manifest photo with no marker, a photo in
a Dutch note, photo + names, photo + the ASR wall, markers already on sentence ends (user
edited), a photo inside a task list, and a photo inside a blockquote.

`atWord` = the word index the photo was taken after; the generator turns it into
offsetSeconds from the audio duration so the two always agree.
"""
from notes_typed import WALL_ONE_PARAGRAPH

WORKSHOP = {"latitude": 51.9139, "longitude": 4.4760, "placeName": "Werkplaats, Rotterdam-Zuid"}

NOTES = [
    {
        "slug": "pic-mid-sentence",
        "kind": "voice", "lang": "en",
        "shape": ["voice", "pictures", "marker-mid-sentence"],
        "transcript": "The crack runs from the rim all the way down to the [[img_001]] foot, so it is the body not the glaze. I will fire the next one slower.",
        "photos": [{"atWord": 12}],
        "tags": ["glaze"],
        "significance": 0.6,
        "metadata": {"location": WORKSHOP, "dayPeriod": "afternoon"},
        "expect": {"bug": "v1 splits the sentence into two paragraphs around the marker. Expected: the sentence stays whole and the picture is its own paragraph AFTER 'foot, so it is the body not the glaze.'"},
    },
    {
        "slug": "pic-at-start",
        "kind": "voice", "lang": "en",
        "shape": ["voice", "pictures", "marker-start"],
        "transcript": "[[img_001]] This is what the blue looks like at cone five, straight out of the kiln, before I touched it.",
        "photos": [{"offsetSeconds": 0.4}],
        "tags": ["glaze"],
        "significance": 0.7,
        "expect": {"note": "Photo taken as the recording started: the picture is the first paragraph, the sentence the second."},
    },
    {
        "slug": "pic-at-end",
        "kind": "voice", "lang": "en",
        "shape": ["voice", "pictures", "marker-end"],
        "transcript": "Finished the Gazelle overhaul, new chain, new cables, wheels trued. Here it is. [[img_001]]",
        "photos": [{"atWord": 14}],
        "tags": ["studio"],
        "significance": 0.5,
    },
    {
        "slug": "pic-two-same-second",
        "kind": "voice", "lang": "en",
        "shape": ["voice", "pictures", "adjacent-markers"],
        "transcript": "Front and back of the same bowl, [[img_001]] [[img_002]] the green edge is only on the side that faced the element.",
        "photos": [{"atWord": 7}, {"atWord": 7}],
        "tags": ["glaze"],
        "significance": 0.6,
        "expect": {"note": "Two photos within the same second: two picture paragraphs back to back, in order, both after the clause; never merged, never one dropped."},
    },
    {
        "slug": "pic-three-spread",
        "kind": "voice", "lang": "en",
        "shape": ["voice", "pictures", "multiple"],
        "transcript": "Walking the workshop before the Saturday. Bike side first, [[img_001]] this all has to be covered. Then the wheel, which is fine. [[img_002]] Then the shelf where the glazed pieces go, which is not fine, it is full of Hendrik's tools. [[img_003]] Friday night job.",
        "photos": [{"atWord": 10}, {"atWord": 21}, {"atWord": 40}],
        "tags": ["workshop"],
        "significance": 0.7,
        "metadata": {"location": WORKSHOP, "dayPeriod": "evening"},
        "expect": {"note": "Three pictures; each lands after the sentence being spoken; 'Hendrik' links across the marker."},
    },
    {
        "slug": "pic-ocr-text",
        "kind": "voice", "lang": "en",
        "shape": ["voice", "pictures", "ocr"],
        "transcript": "Snapped the supplier's price board so I stop guessing. [[img_001]] Grey body went up again.",
        "photos": [{"atWord": 9, "bigText": "GREY BODY 20KG 31.50", "text": "GREY BODY 20KG 31.50"}],
        "tags": ["money"],
        "significance": 0.5,
        "expect": {"note": "OCR text rides the manifest: searchable on the phone, imageOCRText on the Mac row, never inserted into the body."},
    },
    {
        "slug": "pic-missing-file",
        "kind": "voice", "lang": "en",
        "shape": ["voice", "pictures", "missing-file"],
        "transcript": "The photo for this one never made it across. [[img_001]] Should show a placeholder, not crash, not drop the marker.",
        "photos": [{"atWord": 8, "missingFile": True}],
        "tags": [],
        "significance": 0.5,
        "expect": {"note": "Manifest entry exists, file does not (asset not synced yet). Marker preserved; renderer shows a placeholder; export skips the image but keeps the text."},
    },
    {
        "slug": "pic-manifest-no-marker",
        "kind": "voice", "lang": "en",
        "shape": ["voice", "pictures", "markers-not-injected"],
        "transcript": "Recorded on an older build that did not inject markers yet. The photo is in the manifest at twelve seconds.",
        "transcriptMarkersInjected": False,
        "photos": [{"offsetSeconds": 12.0}],
        "tags": [],
        "significance": 0.5,
        "expect": {"note": "markersInjected == false with a manifest: the Mac injects the marker itself from offsetSeconds (legacy path); v2 = 'derive the position from the moment' for everyone."},
    },
    {
        "slug": "pic-nl",
        "kind": "voice", "lang": "nl",
        "shape": ["voice", "pictures", "dutch"],
        "transcript": "Dit is de scheur waar Hendrik het over had, [[img_001]] van de rand tot aan de voet. Ik denk de klei, niet de glazuur. Eh, volgende keer langzamer stoken.",
        "photos": [{"atWord": 8}],
        "tags": ["glaze"],
        "significance": 0.6,
        "expect": {"note": "Dutch + picture: the same 'own paragraph after the sentence' rule; copy-edit removes 'Eh' without touching the marker."},
    },
    {
        "slug": "pic-wall",
        "kind": "voice", "lang": "en",
        "shape": ["voice", "pictures", "long", "wall", "no-paragraphs"],
        "transcript": WALL_ONE_PARAGRAPH.replace("Which brings me to scheduling", "[[img_001]] Which brings me to scheduling").replace("And the glaze.", "[[img_002]] And the glaze."),
        "photos": [{"atWord": 520}, {"atWord": 720}],
        "tags": ["studio", "thinking"],
        "significance": 0.9,
        "expect": {"bug": "THE 2026-08-20 shape: a wall WITH pictures. v1's anchor extraction flattened whitespace and the model re-paragraphed; expected: the paragrapher breaks the wall exactly as it would without pictures, and each picture is its own paragraph at the same place."},
    },
    {
        "slug": "pic-user-snapped-markers",
        "kind": "voice", "lang": "en",
        "shape": ["voice", "pictures", "user-edited"],
        "transcript": "Moved the markers myself in the editor so they sit on sentence ends.\n\n[[img_001]]\n\nThis paragraph is after the first picture.\n\n[[img_002]]\n\nAnd this one after the second.",
        "transcriptUserEdited": True,
        "editedAt": "2026-09-13T21:00:00+01:00",
        "photos": [{"atWord": 4}, {"atWord": 12}],
        "tags": [],
        "significance": 0.6,
        "expect": {"note": "Already in the v2 shape. Every stage must be a no-op on structure: editor round-trip returns the identical string; export places both images between the paragraphs."},
    },
    {
        "slug": "pic-in-task-list",
        "kind": "voice", "lang": "en",
        "shape": ["voice", "pictures", "tasks"],
        "transcript": "Parts to order for the cargo bike:\n\n- [ ] chain, 1/8\n- [ ] the rear hub, this one [[img_001]]\n- [ ] brake pads, four\n- [x] new bell",
        "photos": [{"atWord": 12}],
        "tags": ["cargo", "todo"],
        "significance": 0.5,
        "expect": {"needs-verdict": "A picture taken while dictating a list item: does it break the list (own paragraph after the item) or stay inline on the item?"},
    },
    {
        "slug": "pic-in-blockquote",
        "kind": "voice", "lang": "en",
        "shape": ["voice", "pictures", "blockquote"],
        "transcript": "> The pot you want is the pot you can't make yet. [[img_001]]\n\nSaw it written on the wall at the fair and photographed it.",
        "photos": [{"atWord": 11}],
        "tags": ["thinking"],
        "significance": 0.5,
        "expect": {"needs-verdict": "A marker inside a leading blockquote: picture before the quote, after it, or inside it?"},
    },
    {
        "slug": "pic-shared-no-timestamp",
        "kind": "voice", "lang": "en",
        "shape": ["voice", "pictures", "shared-picture", "offset-zero"],
        "transcript": "Talking [[img_001]] about the lamp base I saw at the market, the seller fires electric at cone five so the matte blue is possible without gas.",
        "photos": [{"offsetSeconds": 0}],
        "tags": ["glaze", "inspiration"],
        "destination": "inspiration",
        "significance": 0.7,
        "expect": {"bug": "A picture with NO moment (offset 0, e.g. added after the fact): v1 drops it after the FIRST WORD. Expected: TOP of the note as its own paragraph (recommendation; needs Tuur's verdict top vs bottom)."},
    },
]
