# Editor soft wrap

Soft wrap is enabled by default and persisted as the Boolean `softWrap` setting.
Turning it off restores horizontal scrolling. It changes display layout only:
source strings, clipboard text, logical line commands, undo snapshots and saved
files never contain the soft breaks.

## Layout and editing

`EditorLayout` stores one leaf per logical line, with cached break offsets and
logical tab-cell offsets. AVL branches aggregate source-line and screen-row
counts. Splicing changed leaves preserves the rest of the tree; ordinary typing
and deletion supply a bounded affected span. Bulk commands and undo find the
changed prefix/suffix without rewrapping equal lines. The text buffer still has
its existing whole-document join on edits.

Whitespace is preserved. Breaks prefer spaces/tabs and otherwise split a word.
Continuation rows start at the left edge. ASCII prose uses native string/regex
scans per row; tabs and non-ASCII text use a code-point walker. Source columns
remain UTF-16 offsets and never split surrogate pairs. The existing one-cell-per-
code-point model remains: wide glyphs and grapheme clusters are not fully shaped.

`VirtualEditor` renders viewport rows plus ten rows of overscan on each side,
even inside one enormous paragraph. Caret, hidden input, pointer selection,
search highlights, and preview synchronization use the same layout. A source
offset at a wrap boundary has upstream/downstream affinity. Home/End and vertical
motion use screen rows; repeated vertical motion retains the desired cell column.

Visible logical lines have cached, indexed syntax tokens. Each fragment binary-
searches the tokens and uses `Html.Lazy.lazy3` with the cached token array, segment,
and source string. Unchanged fragments skip both tokenization and child VDOM
work. Tabs are expanded only in the display; test metadata retains raw source.

Viewport measurements exclude padding and the scrollbar gutter. Measurements
are deduplicated and coalesced through requestAnimationFrame. Reflow runs only
when the effective column count changes; font height and viewport-origin changes
only update geometry. Reflow preserves the top source position and fractional
row offset, while keeping an already-visible caret visible. A width change still
requires a full document rewrap.

## Verification

```sh
bun run test
bunx vite build
bun run test:e2e
FENCE_E2E_WRAP=off node --test --test-concurrency=1 --test-skip-pattern='soft wrap|editor performance:' e2e/*.test.js
```

The portable `soft-wrap-performance.test.js` covers approximately 700 KB spread
across 10,000 source lines, longer prose paragraphs, and a single syntax-heavy
paragraph. It runs both settings, checks bounded DOM size, scroll layout below
50 ms, and wrapped steady-typing layout below 2 ms. First-edit title/header work
and the preview debounce are outside the steady-typing phase, matching the
existing reference-file keystroke test. Optional `FENCE_PROFILE=1` writes traces
to `/tmp/fence-wrap-<fixture>-<setting>.json`.

A local production-build run on 2026-09-06 measured:

| Wrapped fixture | Rendered rows | Worst scroll layout | Worst steady typing layout | Worst resize frame callback |
| --- | ---: | ---: | ---: | ---: |
| 10,000 lines | 46 | 0.43 ms | 0.08 ms | 7.97 ms |
| Prose paragraphs | 46 | 0.34 ms | 0.07 ms | 9.48 ms |
| One large paragraph | 47 | 0.14 ms | 0.07 ms | 8.83 ms |

The existing 9,976-line reference-file trace painted its first frame in 50 ms
(limit 150 ms), with an 8.7 ms worst scroll layout (limit 50 ms). Its keystroke
trace measured a 0.23 ms worst layout (limit 2 ms). Timings vary with machine load;
the deterministic row/dirty-object bounds are also checked.

**Remaining large-line cost:** the existing syntax tokenizer takes about 250 ms
on the single 700 KB syntax-heavy paragraph. Wrapped input handlers measured up
to 260 ms because the visible-line token cache refreshes during the update;
unwrapped highlighting runs in the lazy view instead. These layout timings are
not end-to-end input latency. Wrapping is about 11 ms for that line in an isolated
measurement; incremental syntax tokenization remains separate work.
