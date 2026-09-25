# Phone typing, 2026-09-25, Dev build 172, FAST state (baseline)

Trace: `.queue/perf/phone-typing.trace`, Time Profiler, 30s, `--all-processes`, iPhone 13 / iOS 27.0, Skrift Dev (pid 10742). Recorded while typing felt fast (post-install lag is separate, unmeasured). Only one SkriftMobile process was in the trace, no prod/dev duplicate to filter.

## Totals

| | samples | % |
|---|---|---|
| SkriftMobile total | 8651 | 100% |
| Main thread | 8042 | 93.0% |
| Other app threads (6) | 609 | 7.0% |

## Top 15 symbols by self time (leaf frame, all SkriftMobile threads)

No single frame dominates — spread thin across ARC/objc runtime and UIKit text-input support, consistent with "feels fast."

| self | binary | symbol |
|---|---|---|
| 73 | libswiftCore | swift::RefCounts::doDecrementSlow (ARC release) |
| 69 | libobjcMsgSend2 | objc_msgSend |
| 60 | libicucore | icu::RuleBasedTokenizer::init() |
| 59 | CoreGraphics | A8_mark_constmask (glyph blit) |
| 43 | liblangid | langid_consume_string (autocorrect lang-ID) |
| 39 | libobjc.A | objc_autoreleaseReturnValue |
| 39 | libsystem_malloc | _xzm_xzone_malloc_tiny |
| 38 | libobjc.A | AutoreleasePoolPage::add |
| 37 | CoreGraphics | CGSColorMaskCopyARGB8888 |
| 36 | libobjc.A | objc_retainAutoreleaseReturnValue |
| 34 | libobjc.A | object_getMethodImplementation |
| 32 | (unsymbolized) | 0x1a257ba71 |
| 32 | libswiftCore | LockingConcurrentMap::getOrInsert (generic metadata cache) |
| 29 | CoreFoundation | __CFStringAppendFormatCore |
| 29 | libobjc.A | objc_msgSend (deduplicated) |

## Top app-code frames, inclusive samples on main thread

(root frames `SkriftApp.$main()` / dylib entry excluded, ~99% trivially)

| incl. | % main | frame |
|---|---|---|
| 258 | 3.2% | MemosListView.body.getter |
| 258 | 3.2% | MemosListView.notesRoot.getter |
| 225 | 2.8% | MemosListView.listContent.getter |
| 174 | 2.2% | MemoPageView.body.getter |
| 169 | 2.1% | MemoPageView.editorPage.getter |
| 162 | 2.0% | MemosListView.derived.getter |
| 161 | 2.0% | MemosListView.enhancedTitleByMemoID.getter |
| 160 | 2.0% | NotesRepository.allTags() |
| 160 | 2.0% | MemoPageView.noteHeaderCore(isCurrent:) |
| 138 | 1.7% | MemoLifecycle.backlinkedIDs(in:) |

## Per-keystroke work in app code

- `NoteBodyTextView.layoutSubviews()` — 37 samples (0.46% main), TextKit relayout.
- `NoteBodyView.Coordinator.sanitizeTypingAttributes(_:)` + closures — 33 samples (0.41% main), runs every typed character.
- `NotesRepository.save()` — 15 samples (0.19% main).
- No SwiftData/markdown-styling/name-linking frame reached the top 40 app-code frames. The biggest app-code cost is `MemosListView` body/list-content re-evaluating (allTags, allMemos, backlinkedIDs, filterChips) — the memo LIST behind the editor re-rendering on every edit, not the text input itself.
