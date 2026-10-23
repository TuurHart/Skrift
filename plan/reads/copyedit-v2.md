# Copy-edit v2 after your four D215 calls (Q478)

## The four notes now

| Your call | Note | Ships now |
|---|---|---|
| 1. Checkboxes never reach the model | typed-tasks | All six boxes, ticked ones still ticked: `- [ ] Marco bellen…`, `- [x] Order the grey clay body`… Only "Mariam" gets linked. |
| 2. A short note losing a sentence falls back | voice-en-paragraphed-by-pauses | Your words: "First thought.", "Second thought, unrelated." and "Third." are back. |
| | voice-en-raw-title | Your words: "A voice note whose stored title looks like a raw filename." is back. |
| 3. Your spelling stays | voice-en-names-all-tiers | "rose gold is not a colour" (was "color"). The rest of the edit ships. |
| | typed-blockquote-ordinary | "stop apologising" (was "apologizing"). |
| 4. A typed list stays a list | typed-dutch-boodschappen | Your five list lines as typed, "tante Ria haar verjaardag" included (was one prose paragraph with "Ria's"). |

Fillers and "okay so" still go: voice-en-pricing-ramble ships "Walking back from the shop, I think I've decided on the prices."

## How

1. Checkbox lines, and every list line (`- `, `* `, `1. `) of a typed note, are held aside like pictures and put back in place. The model only sees the rest.
2. A note under 40 words falls back to your words when more than half the words of any sentence are gone. A sentence of only fillers ("Yeah.", "Okay.") may go.
3. The copy-edit prompt gets one added line, stored in `PolishPrompts.keepSpelling`: keep the writer's own spelling and dialect. The gate also falls back when a word comes back respelled (colour→color, apologising→apologizing, centre→center, grey→gray). On the corpus the prompt line alone was enough: no note fell back on spelling.
4. The changed prompt meant new model outputs for every copy-edit: 77 recorded with the live model. The other differences from v1 are commas and dashes (typed-wall-7k: "rent," → "rent").

## Falls back to your words (13 of 81)

| Note | Why |
|---|---|
| voice-en-paragraphed-by-pauses, voice-en-raw-title | Lost a whole sentence (call 2). |
| typed-numbered-list | Lost a sentence: the model mangled the one line it saw, "Overhaul checklist, in order". The list was held and is unchanged. |
| typed-dutch-boodschappen, applenote-dutch | The model merged your two prose paragraphs, so the typed note ships as typed. The lists were held anyway. |
| typed-wall-one-paragraph | The model split your one typed paragraph. |
| voice-mix-code-switch | Translation: the English half turned Dutch and lost "six". Still caught. |
| typed-crlf-tabs-nbsp | The gate read the model's output as a language flip. |
| typed-title-derived, edge-tag-case-dupes | Invented names. |
| voice-en-duplicate-a, voice-en-duplicate-b | Lost the numbers "two" and "forty" (new with this prompt). |
| quote-with-names | Lost "two" (new with this prompt). |

## For you to judge

1. applenote-headings-checklist: the model drops the bold from `**Pros:**` / `**Cons:**` and the `#` from the first heading. No rule catches lost formatting. v1 drops the heading too.

Harness against v1: identical 62, expected-different 47, unexplained 0.
