# Virtualized editor in Elm

## Why

The editor is a `<textarea>` with a highlight overlay. Everything the browser
does for a textarea scales with the whole document: the 712KB reference file
costs ~150ms of internal layout on open (30k layout objects) and every
keystroke re-lays-out the overlay line that changed plus the textarea. That is
now the floor for opening a large file, and it is also why the overlay had to
become progressive. A custom editor that renders only the visible rows makes
open time independent of document size and gives full control over caret,
selection, undo, and highlighting.

## Shape (recommended)

Same architecture as Monaco: a **hidden `<textarea>` receives input** (keys,
IME composition, paste, native shortcuts, accessibility focus), while Elm owns
the document and **draws only the visible rows**.

- **Document model:** `Array String` of lines plus a change log. Line edits
  are O(line); inserting/removing lines is O(n) on the array but n is 10k, not
  700k characters. A rope is not needed at this scale.
- **Input:** the hidden textarea holds only the current composition. Elm
  handles `beforeinput`/`keydown`/`paste`/`compositionend` and applies edits
  to the model. Native undo is replaced by an Elm history (grouped by time and
  edit kind).
- **Rendering:** a scroll container with a spacer of `totalRows * lineHeight`
  and an absolutely positioned window of visible rows (plus overscan). Row
  tokens come from the existing `Editor.lineTokens`. Caret and selection are
  drawn as positioned elements; the textarea sits under the caret (so IME
  popups appear in place).
- **Metrics:** monospace only (every offered font is monospace). Character
  width and line height are measured once per font/size change with a hidden
  probe (`Browser.Dom.getElement`) and sent to Elm. Mouse → position is
  arithmetic.
- **Wrapping:** deterministic. Rows per line are computed in Elm from
  `ceil(length / columns)` with a wrap-at-character policy, or no wrap with
  horizontal scroll. CSS word-wrap cannot be reproduced exactly in Elm, and
  virtualization needs exact row counts to position rows.

## Decisions needed before slice 1

1. **Wrapping:** no-wrap + horizontal scroll (code-editor default; simplest,
   exact) or wrap at character boundary (exact, but words break) — word wrap
   is out unless rows are measured from the DOM, which reintroduces layout
   cost.
2. **Native features lost:** spellcheck, system text services (dictation,
   emoji picker mostly works via IME), and the OS-level undo. Acceptable?
3. **Accessibility:** the hidden textarea can mirror the current line for
   screen readers; full document reading is lost. Acceptable for v1?

## Status

- Slice 1 done (7229424): first frame 43ms on the 712KB file, 46 rows in DOM.
- Slice 2 done: typing, newline, deletion, arrows/home/end/page, Tab and
  Shift+Tab, undo/redo, click-to-place, paste and IME through the hidden
  input; e2e/virtual-editing.test.js.
- Slice 3 done: shift-movement, mouse drag, double/triple click, select-all,
  typing/paste over a selection, Tab/Shift+Tab on selected lines, copy/cut
  via the copy/cut events (menu and keyboard), IME commit via
  compositionend; fuzz test against a plain-string reference model;
  e2e/virtual-selection.test.js.
- Decisions taken: no wrap + horizontal scroll; native spellcheck, native
  undo and full screen-reader access accepted as v1 losses.

## Slices (each independently shippable and gated)

1. **Read-only virtual view.** New `Editor2` module behind a setting flag:
   document model, metrics probe, virtual rows with the existing token
   highlighting, scroll sync to the preview. Gate: open the 712KB reference
   file with the new editor and paint the first screen in <60ms; scroll to
   the end at 60fps (e2e trace, no frame >16ms of layout).
2. **Caret and keyboard editing.** Hidden textarea input, insert/delete/
   newline, arrows/home/end/page, Tab/Shift-Tab (port editor-keys.js), Elm
   undo/redo, dirty state and save unchanged. Gate: the existing editing e2e
   suite passes with the new editor; a keystroke in the 712KB file costs
   <2ms of layout (trace).
3. **Selection and clipboard.** Mouse and shift-arrow selection, word/line
   selection, copy/cut/paste, drag-select autoscroll, IME composition. Gate:
   e2e covering each, plus a fuzz test that random edit sequences keep the
   model equal to a reference string implementation.
4. **Switch-over.** Make it the default, delete the textarea editor and the
   overlay CSS, keep the old one for one release behind a setting. Gate: all
   suites green, both perf gates green, release.

Estimated size: slice 1 ~400 lines of Elm + a small JS metrics probe; slices
2–3 are where the real work is (input edge cases, IME).
