# Copy-edit v2 after your "no" (Q449, D209)

What changed: a dropped ordinary word no longer sends your words back unedited. The model's
edit now ships unless it translates, loses a name or a number, invents a name, re-paragraphs a
typed note, or shrinks a long note under 55% (C33). Fillers um/uh/eh still go.

On the 81 corpus notes that get a copy-edit: **74 now ship the model's edit, 7 still fall
back** (was 20 under Q424). Harness against v1: identical 80, expected-different 29,
unexplained 0.

## Still falls back to your words (7)

| Note | Why |
|---|---|
| voice-mix-code-switch | Translation: the model turned the English half into Dutch and lost "six". Still caught. |
| typed-crlf-tabs-nbsp | Translation: the model wrote a Dutch paragraph the note never said. |
| typed-title-derived | Invented names: the model wrote an essay about the Dutch language. |
| edge-tag-case-dupes | Lost number: "typed three times" lost its "three". |
| typed-headings-and-tags | Typed note re-paragraphed: the model merged 10 paragraphs into 5. |
| typed-wall-one-paragraph | Typed note re-paragraphed: the model split your one paragraph. |
| typed-tags-with-spaces | Flagged as a language flip, but really a dropped phrase: losing "Tags with spaces and hashes" halved its English marker words. |

## Now ships the model's edit, with words dropped (13)

| Note | What the edit drops |
|---|---|
| voice-en-pricing-ramble | okay, so, yeah, and the fillers. Ships "Walking back from the shop, I think I've decided on the prices." |
| voice-en-with-mac-polish | so, and, see, fillers |
| voice-en-names-all-tiers | "colour" becomes "color" |
| typed-blockquote-ordinary | "apologising" becomes "apologizing" |
| quote-missing-book-metadata | this |
| typed-wall-7k, voice-en-asr-wall, voice-en-eight-minutes, pic-wall | the opening "Okay so" |
| typed-dutch-boodschappen | your list becomes one prose paragraph; "Ria haar" becomes "Ria's" |
| typed-tasks | **every checkbox: tasks come back as plain list lines, done or not** |
| voice-en-paragraphed-by-pauses | whole phrases: "First thought.", "Second thought, unrelated.", "Third." |
| voice-en-raw-title | a whole sentence: "A voice note whose stored title looks like a raw filename." |

The other 61 notes ship the edit with no word dropped.

## For you to judge

1. typed-tasks loses its checkboxes, and with them which tasks are done. D209 does not list
   that as damage, so it ships.
2. voice-en-raw-title and voice-en-paragraphed-by-pauses drop whole sentences in notes under
   40 words, where the shrink guard does not look.
