# Closing the feature gaps

## Why

Fence renders markdown well and opens a 700KB file fast, but it is still a
viewer with an editor attached. You cannot create a file, you cannot search
one, and the file tree is read-only. This plan covers the twelve gaps found in
the 2026-09-05 audit, ordered so the shared plumbing lands once and the rest
sits on top of it.

Two of the twelve are deliberately not built as asked — see **Not doing**.

## Shared plumbing (phase 0)

Everything below routes through the same four-file path: Elm `command tag
fields` (`Main.elm:1066`) → tag→method map (`js/ports.js`) → channel
(`electron/preload.js`) → `registerIpc` (`electron/main.js`). Adding a command
is four edits every time, so add them in one batch rather than per feature.

**New `fs-ops` operations**, each guarded by `pathWithinWorkspace` exactly as
`readFile`/`writeFile` are — the guard is the whole reason these are safe:

- `createFile(dir, name)` — `writeFile(p, "", { flag: "wx" })`, so an existing
  name fails loudly instead of truncating.
- `createDir(dir, name)` — `mkdir`, no `recursive`.
- `renamePath(from, to)` — both ends validated, `wx`-equivalent via a prior
  `access` check.
- `trashPath(p)` — `shell.trashItem`, not `unlink`. Reversible, so no
  confirmation dialog is needed and no user data is destroyed by a misclick.
- `writeBinary(dir, name, buffer)` — for pasted images.
- `listMarkdownFiles(root)` — one walk reusing the `WALK_MAX_*` budgets and
  `NOISE_DIRS` pruning from `containsMarkdown`. Feeds quick-open and grep.
- `grep(root, query, opts)` — read each file from `listMarkdownFiles`, collect
  `{path, line, text}`, cap at 500 hits.

**"Open at line"**: `sendFileContent` gains an optional `line`, passed through
to the renderer on `fileContent`, and Elm moves the cursor there and runs the
existing `caretFollow` scroll. Quick-open, grep results and rename-follow all
need it.

**Preview HTML extraction**: one `getPreviewHtml` command handled in
`js/ports.js` (not Elm) — it reads `.preview-pane`'s `innerHTML` from the DOM,
which already contains rendered mermaid SVG, and hands it to main. Export PDF,
export HTML and copy-as-rich-text all consume this single string.

**Elm side**: a `Tests/` addition per pure function. `elm-test` for the buffer
and matching logic, `node --test` for the new `fs-ops` calls (extend
`electron/fs-ops.test.js`, which already builds a temp workspace), `e2e` for
the interactive surfaces.

## 1. Creating files (gap 1 + 3)

No untitled buffers. An untitled buffer forces `filePath : Maybe FilePath`
handling through save, recovery drafts, the title bar and the conflict dialog,
for a state that exists for four seconds. **New File creates a real empty file
on disk immediately** and opens it.

The name has to come from somewhere and Electron has no input dialog, so the
file tree grows an inline edit row — which rename needs anyway:

- `FileTree.Model` gains `editing : Maybe { parent : FilePath, mode : Create
  File | Create Dir | Rename FilePath, name : String }`. The row renders an
  `<input>` in place of the label; Enter commits, Escape cancels.
- New `OutCmd`s: `CmdCreateFile`, `CmdCreateDir`, `CmdRename`, `CmdTrash`,
  translated in `outCmdsToPortCmds` like the existing five.
- Target directory: the selected directory, else the parent of the selected
  file, else the root.

The context menu (`electron/main.js:506`, currently one item) becomes: New
File, New Folder, Rename, Delete, Reveal in Finder (`shell.showItemInFolder`),
Copy Path. Items needing a name send `{tag: "treeCommand", ...}` to the
renderer to start the inline edit; Delete and Reveal call through directly.

Menu: File → New File (`CmdOrCtrl+N`) sends the same `treeCommand`.

**The tree does not need updating by hand.** chokidar already emits
`add`/`unlink`/`addDir`/`unlinkDir` and `FileTree.handleFsEvent` already
consumes them (`FileTree.elm:425`). Create, rename and delete all refresh for
free.

Two edge cases: renaming the currently open file needs `Editor.setPath` so the
title and the next save follow it; deleting the currently open file needs
nothing — the buffer keeps its content and the next save recreates the file,
which is the friendliest behavior available for free.

## 2. Find and replace (gap 2)

The largest item. New `src/Find.elm`, pure:

```elm
type alias Model =
    { query : String
    , replacement : String
    , caseSensitive : Bool
    , wholeWord : Bool
    , replaceOpen : Bool
    , matches : Array ( Cursor, Cursor )
    , active : Int
    }

matchesIn : Options -> String -> Array String -> Array ( Cursor, Cursor )
```

- Matching is `String.indexes` per line (lowercased on both sides when
  case-insensitive). One pass over 20k lines is a few milliseconds; no regex,
  no incremental index. Regex search is deferred until asked for.
- Recomputed synchronously when the query changes, and on document change in
  the existing `DebouncedParse` step — a keystroke should not re-scan 700KB.
- **Rendering** reuses the machinery that already draws selections:
  `VirtualEditor.Config` gains `highlights : List (Cursor, Cursor)`, drawn by
  the same `selectionRects` function into a new `.veditor-highlight-layer`
  (`static/styles/editor.css`), clipped to the visible range like everything
  else in that view. The active match gets a second class.
- Navigation sets `editor.cursor`/`anchor` to the match and lets `caretFollow`
  scroll. Enter / ⇧Enter, `⌘G` / `⇧⌘G`.
- Replace goes through `Editor.edit` (`deleteRange` then `insert`). Replace All
  applies matches **bottom-up in a single `edit`**, so earlier positions stay
  valid and the whole operation is one undo entry.
- The bar sits over the top-right of the editor pane. Its `<input>` takes focus
  away from `veditor-input`; closing must call `focusSilently "veditor-input"`
  (`Main.elm:277`) or the editor goes dead.
- `⌘F`, `⌘⌥F` (replace), Escape — in `Main.KeyDown`, beside the existing `⌘S`.

Seed the query from the selection when the bar opens; that is the behavior
everyone expects and it is three lines.

## 3. List continuation (gap 4)

`Editor.keyPressed`'s `Enter` branch (`Editor.elm:328`) currently inserts a
bare `"\n"`. Add one pure function:

```elm
continuationFor : String -> Maybe String   -- prefix to repeat on the next line
```

Handles `-`/`*`/`+`, ordered `1.`/`1)` with the number incremented, task items
(`- [x]` continues as `- [ ]`), and blockquote `>`. An item whose content is
empty clears the line instead of continuing it, which is how every other editor
ends a list. Indentation is preserved verbatim.

`elm-test` covers it — it is exactly the kind of prefix logic that rots.

## 4. Markdown shortcuts (gap 5)

One helper, `wrapSelection : String -> String -> Model -> Model`, that toggles:
selection wrapped in markers if not already wrapped, unwrapped if it is, and
with no selection inserts both markers and puts the caret between them.

- `⌘B` `**`, `⌘I` `*`, `⌘E` `` ` ``, `⌘⇧X` `~~`.
- `⌘K` inserts `[selection](  )` with the caret in the URL slot.
- `⌘/` toggles `<!-- -->` on the selected lines via `editLines`.
- **Paste a URL over a selection** → `[selection](url)`. `InsertText` already
  receives paste; this is one `String.startsWith "http"` check and is the
  single nicest small thing in this document.

Auto-pairing of `*`/`_`/`` ` `` is **not** included: in markdown those are
typed as literal characters constantly, and doing it properly needs a
"type-over the closer" state machine. Add it only if it is missed.

## 5. Line operations (gap 7)

Pure `TextBuffer` additions, each with an `elm-test`, each wired through
`edit`/`editLines` so undo works without further thought:

- `⌘⇧D` duplicate line or selection
- `⌥↑` / `⌥↓` move line or selected lines
- `⌘⇧K` delete line
- `⌘↵` open line below, `⌘⇧↵` above

Multi-cursor is **not** here. `Editor.Model.cursor : Cursor` and
`anchor : Maybe Cursor` are singular, and every function in `TextBuffer`,
`Editor` and `VirtualEditor` assumes it. Multi-cursor is a rewrite of the
editor core, not a feature — it needs its own plan.

## 6. Word count (gap 8)

Computed in the debounced parse step, never per keystroke — `String.words` over
700KB is ~50ms and would be felt. Store `{ words, chars, lines, readingMinutes
}` on the model and render it in the outline pane's footer, which already
exists and has room. No new pane, no status bar.

## 7. Quick-open and workspace search (gaps 9, 11)

Both are the same modal with a different result source, so build the shell once
(`src/Palette.elm`): an overlay, an input, a result list, arrow keys, Enter,
Escape, and the same focus-return discipline as the find bar.

- **`⌘P` quick-open**: `listMarkdownFiles` is sent once on folder open and
  refreshed on `add`/`unlink`. Scoring is subsequence matching with a bonus for
  matches at path-segment starts — about 30 lines, no fuzzy-search dependency.
- **`⌘⇧F` workspace search**: `fs-ops.grep`, debounced ~200ms, results grouped
  by file, Enter opens at the line via the phase-0 "open at line" path.

`grep` reads files with plain Node over a markdown-only file list. Mark it:
`// ponytail: plain read-and-scan, swap in ripgrep if a large workspace drags`.

## 8. Tabs → history instead (gap 9)

Tabs mean the model holds N documents: a document cache, per-tab scroll and
cursor and undo, a tab strip, close/dirty semantics per tab, and recovery
drafts multiplied by N. That is a large change to `Main.Model`.

What tabs are mostly used for here is *going back to the file I just had open*.
So: a recent-files stack with `⌘[` / `⌘]`, about 20 lines and no model surgery.
If the stack turns out not to be enough, tabs get their own plan and this is
not wasted.

## 9. Export and print (gap 10)

All three consume the phase-0 preview HTML string:

- **PDF**: main opens an offscreen `BrowserWindow` with the HTML plus
  `preview.css` and the current theme's variables, then `printToPDF`. Printing
  the live window is wrong — it would include the editor, tree and outline.
- **HTML**: same string in a standalone template with the CSS inlined, saved
  through `dialog.showSaveDialog`.
- **Copy as rich text**: `clipboard.write({ text, html })`, three lines.

Menu: File → Export → PDF… / HTML…, and Edit → Copy as Rich Text.

## 10. Images and drag-drop (gap 12)

- **Paste an image**: `js/virtual-input.js:28` reads only `text/plain`. Add a
  branch for `clipboardData.files` with an `image/*` type → send the bytes to
  `fs-ops.writeBinary` → written as `assets/<timestamp>.png` beside the current
  document → the reply carries the relative path → Elm inserts
  `![](assets/….png)` at the cursor.
- **Drop a file or folder on the window**: `dragover`/`drop` in `js/ports.js`.
  Electron 44 has no `File.path`, so the path comes from
  `webUtils.getPathForFile`, which must be exposed in `preload.js`. A dropped
  folder opens as the workspace; a dropped `.md` file opens directly if it is
  inside the current workspace, otherwise its parent becomes the workspace.
  `preventDefault` on both events, or Chromium navigates away from the app.

## 11. Scroll sync (gap 6)

Left for last because it is the one with no clean cheap answer. Line-ratio
mapping is ~15 lines and visibly wrong the moment a code block or image makes
one source line tall in the preview.

Heading-anchored sync is the honest cheap version and the pieces are nearly
there: the outline already carries anchor ids and `scrollToHeadingCmd`
(`Main.elm:1095`) already scrolls to them. What is missing is a source line
number on `Markdown.OutlineEntry` (currently `{ level, text, id }`) —
`splitChunks` splits at top-level headings, so the start line of each chunk is
known where the split happens, offset by the frontmatter length.

Then: on editor scroll, find the last heading at or above the top visible line
and scroll the preview to that anchor, interpolating within the gap to the next
heading. Editor → preview only; preview → editor needs a DOM-to-source map and
is not worth it. Throttle to one animation frame and suppress it while a
selection drag is auto-scrolling (`Main.elm:555`).

## Not doing

- **Multi-cursor** (part of gap 7) — an editor-core rewrite, needs its own plan.
- **Tabs** (part of gap 9) — replaced by file history above until history is
  shown to be insufficient.
- **Auto-pairing** (part of gap 5) — fights literal `*` and `_` typing.
- **Regex find** — added only if plain search proves limiting.

## Order

Each phase ships and is usable on its own.

0. Plumbing: `fs-ops` operations, IPC batch, open-at-line, preview HTML.
1. New file, rename, delete, reveal; list continuation. *Biggest jump in
   day-to-day usability per line of code.*
2. Find/replace; line ops; markdown shortcuts.
3. Quick-open, workspace search, file history, word count.
4. Export/PDF/rich text; image paste; drag-drop.
5. Scroll sync.
