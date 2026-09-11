# Changelog

Notable changes to Fence. Dates are release dates; versions follow
[semantic versioning](https://semver.org/) and the format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

## [0.6.0] — 2026-09-11

### Added

- Settings gains filterable pickers for the theme, the editor font and a new UI
  font (13 bundled sans faces), preview width presets with a custom width, a
  "use editor font in preview" toggle, a pane-headings toggle, and hover
  tooltips on every row and title bar button.
- Opening a file from the palette, a link, history or the CLI reveals it in the
  sidebar.
- The open-folder button lives in the title bar.

### Changed

- The sidebar lists folders that hold Markdown directly at once and confirms
  deeper ones in the background, so large Markdown-free trees such as build
  output never appear and never delay the listing.
- Preview images are served through a `fence-image://` protocol instead of
  base64 over IPC; exports still embed them.
- Mermaid loads only when a document has a diagram, the update check waits
  ten seconds after launch, and the session file is written after a second of
  quiet instead of on every pause.
- The bundled Iosevka font is subset to Latin, arrows and box drawing (984 KB
  to 96 KB).
- Electron fuses disable run-as-node, `NODE_OPTIONS` and inspect flags, and
  enforce asar integrity; the renderer denies every permission request.

### Fixed

- A second `fence <file>` launch no longer crashes the running instance.
- The Homebrew `fence` command returns the terminal after launching the app.
- Title bar buttons and the preview width control share the same size and
  focus ring as the other settings controls.

## [0.5.0] — 2026-09-10

### Added

- Save As, including saving untitled documents and creating a copy without
  changing the original. Use Cmd/Ctrl+Shift+S or File > Save As.
- Local Markdown links open documents inside Fence and support heading fragments.
- Restart restores the last document, caret, and scroll position, clamping them
  when the file has changed on disk.
- CLI help, version output, and errors for invalid options or missing paths.

### Fixed

- Opening a file or workspace checks unsaved work with Save, Discard, and Cancel.
  Navigation waits for pending saves and preserves edits made during a write.
- Closing checks the current editor state even when the last edit's dirty-state
  notification has not arrived yet.
- Choosing Save when closing an untitled document opens Save As; cancelling
  keeps the document open.
- Switching workspaces clears the old editor after resolving unsaved work.
- Renaming a parent folder updates descendant editor paths and recovery drafts.
- Exports wait for the current Markdown, images, and Mermaid diagrams to render.
- Settings scrolls within the available window height so every control remains
  accessible in short windows or at larger UI font sizes.

## [0.4.2] — 2026-09-10

### Added

- Homebrew installs a global `fence` command for opening files and folders.

### Fixed

- The editor scrollbar corner now matches the theme instead of showing a white
  square when both scrollbars are visible.
- Opening settings no longer shifts the toolbar button and dropdown sideways.

## [0.4.1] — 2026-09-10

### Fixed

- Local images in Markdown and HTML now resolve relative to the open document,
  fixing the broken screenshot when viewing Fence's own README. Image loading
  follows file switches and source edits, including encoded filenames.
- Exports embed local images so they remain visible outside Fence.

### Changed

- Refreshed the README screenshot with the native window frame, Sema's embedding
  guide, and an active search for “interpreter”.

## [0.4.0] — 2026-09-10

### Added

- Editor-only, split, and preview-only layouts, with toolbar controls and a
  configurable keyboard shortcut. Switching layouts preserves your work and
  scroll positions.
- Find in the rendered preview, including match navigation and case-sensitive
  search. Replace brings the editor back into view.
- Invalid Mermaid diagrams show a readable error with expandable source;
  other diagrams continue rendering, and correcting the source clears the error.

### Fixed

- Saving a scrolled document no longer blanks the editor or clears the caret,
  selection, and undo history when its own filesystem notification arrives.
- External reloads preserve the viewport and reject stale responses after
  edits or file switches. Opening another file synchronizes the editor's
  virtual rows with the browser's scroll position.
- When external edits remove the caret's line, it moves to the new end of
  the document. Selections and scroll positions clamp safely, including empty
  files and long final lines with wrapping disabled.
- Rapid external edits immediately after saving are no longer lost in the
  filesystem watcher's notification throttle.
- HTML compatibility preprocessing leaves fenced code intact, preserving
  Mermaid ampersand operators and literal HTML examples.
- Mermaid diagrams update correctly after source edits and theme changes.

## [0.3.0] — 2026-09-06

### Added

- **Soft wrap**, enabled by default with a persistent toggle in Settings.
  Long lines fit the editor width without adding newlines to saved files or
  copied text. Caret movement, selection, search highlights, and preview
  synchronization follow the wrapped rows.

### Changed

- Wrapped editing keeps rendering limited to visible rows and reuses cached
  layout and syntax highlighting. Resize measurements are coalesced per frame.
- Stylesheets are organized by theme and component, with shared control,
  focus, and layout rules. Editor syntax styles are scoped to the editor.
- Outline navigation scrolls the editor to the selected heading and keeps
  the preview synchronized. Settings use a more compact layout and track
  keyboard focus when controls receive focus.

### Fixed

- The window and initial HTML use a dark background while the app loads,
  preventing the default white startup flash.
- Markdown comparisons such as `<2ms` at the start of a line no longer cause
  the preview to show the welcome screen. Unrecoverable parse errors display
  the document source instead of an empty preview.

## [0.2.0] — 2026-09-06

The release that makes Fence a place to write, not only to read: files can be
created, documents can be searched, and the preview keeps up with the editor.

### Added

- **Creating, renaming and deleting files.** New File and New Folder (Cmd+N,
  Cmd+Shift+N, and the file tree's context menu) name the entry inline in the
  tree; Rename and Move to Trash are in the same menu, alongside Reveal in
  Finder. Deletion goes to the Trash, never straight to unlink.
- **Find and replace** (Cmd+F, Cmd+Alt+F). Every match is highlighted, Enter
  and Shift+Enter step through them, matching is case-insensitive until "Aa"
  is pressed, and Replace All is a single undo step. The query is seeded from
  the selection.
- **Quick-open** (Cmd+P) ranks every markdown file in the workspace, and
  **workspace search** (Cmd+Shift+F) greps them and opens a hit at its line.
- **Back and forward** through recently opened files (Cmd+[ and Cmd+]).
- **List continuation.** Enter after a bullet, numbered item, task item or
  blockquote repeats the marker (numbering incremented, task boxes cleared);
  Enter on an empty item ends the list.
- **Markdown shortcuts**: Cmd+B, Cmd+I, Cmd+E and Cmd+Shift+X wrap or unwrap
  the selection, Cmd+K makes a link, Cmd+/ comments out lines, and pasting a
  URL over selected words links them.
- **Line operations**: duplicate (Cmd+Shift+D), move (Alt+Up/Down), delete
  (Cmd+Shift+K) and open a line below or above (Cmd+Enter, Cmd+Shift+Enter).
- **Export** to PDF or HTML, and Copy Document as Rich Text, all from the
  rendered preview with its styles and mermaid diagrams.
- **Pasting an image** writes it to `assets/` beside the document and inserts
  the link. **Dropping** a file or folder on the window opens it.
- **The preview follows the editor's scroll position**, anchored on headings
  and moving continuously with it rather than a line at a time.
- A word, line and character count in the editor's pane header.

### Changed

- Clicking anywhere in the editor pane places the caret. It previously only
  responded on the lines themselves, so a short or new file left most of the
  pane inert.

### Fixed

- Scrolling a large document no longer forces a layout of the whole page for
  the preview to follow it.

## [0.1.6] — 2026-09-05

### Fixed

- **Emoji and other characters outside the Basic Multilingual Plane were
  destroyed by ordinary editing.** Moving the caret past one and typing split
  it into two invalid halves, in the document, the preview and the saved file.
  Movement, deletion, clicking and word selection now step over whole
  characters. Upgrading from 0.1.5 is strongly recommended.
- Running `fence <path>` in a shell after closing the window crashed the app
  on macOS with "Object has been destroyed". It now reopens a window.
- The caret blinked even when the editor did not have focus, suggesting that
  typing would land there.
- Clicking after scrolling could snap the view back to the previous position.
- The editor showed an arrow pointer instead of a text cursor.

### Added

- Word motion. Option or Ctrl with the arrow keys moves by word, Shift
  extends the selection, Option or Ctrl with Backspace deletes a word, and
  Cmd+Backspace deletes to the start of the line.
- Dragging a selection past the top or bottom edge scrolls and keeps
  selecting, faster the further out the pointer is held.

### Removed

- The old textarea editor and the setting that chose between engines. The
  virtualized editor introduced in 0.1.5 is now the only one.

## [0.1.5] — 2026-09-03

### Added

- **A new editor that renders only the lines you can see.** A 700 KB document
  opens in about 35 ms instead of roughly 4 seconds, and a keystroke costs a
  quarter of a millisecond however large the file is. Caret, mouse and
  keyboard selection, double and triple click, select-all, undo and redo,
  clipboard, and input-method composition are all supported.

### Changed

- Lines no longer wrap; long lines scroll horizontally.

### Removed

- Native spellchecking, the system undo stack, and screen-reader access to
  the whole document. Undo is now the editor's own.

## [0.1.4] — 2026-09-02

### Changed

- Large documents open much faster: 46 KB in 83 ms rather than 208 ms, and
  368 KB in 408 ms rather than 674 ms. Parsing and rendering now happen
  progressively, so the first screen appears while the rest fills in.
- Folders containing no Markdown anywhere inside them are hidden from the
  file tree, along with directories such as `node_modules`.

## [0.1.3] — 2026-09-02

### Added

- Markdown file associations. Fence appears under "Open With" and handles
  double-clicks from Finder for `.md`, `.markdown`, `.mdown` and `.mkd`.
- A new app icon, and complete application metadata.

### Fixed

- Typing an emoji immediately before `*`, a backtick or `[` froze the editor
  and exhausted memory.
- Deleting the selected file, or its folder, left the tree pointing at an
  entry that no longer existed.
- Files opened from the command line or Finder were not highlighted in the
  file tree.

## [0.1.2] — 2026-09-02

### Added

- Homebrew installation: `brew install --cask helgesverre/tap/fence`.
- Right-click a file or folder in the sidebar to copy its path.

### Fixed

- READMEs containing an unclosed `<img>` inside a `<div>`, a common badge
  layout, rendered an entirely blank preview.
- The syntax highlighting drifted out of alignment with the text when the
  editor and preview panes were resized.
- YAML frontmatter: a key with an empty value swallowed the following key,
  and a nested block followed by a dedented key was misread.
- The workspace folder was not watched for outside changes until it was
  collapsed and expanded again.

### Changed

- The toolchain moved to bun, and every message between the window and the
  main process is now validated.

## [0.1.1] — 2026-03-12

### Added

- Mermaid diagrams render in the preview.
- A native application menu, an About panel, and keyboard navigation in the
  settings dropdown.
- Wider HTML support in the preview.

### Fixed

- Releases are published automatically once every platform has built.

## [0.1.0] — 2026-03-12

First release. A split-view Markdown editor with a file browser, live
preview, YAML frontmatter, syntax highlighting, several themes, and resizable
panes.

[Unreleased]: https://github.com/HelgeSverre/fence/compare/v0.6.0...HEAD
[0.6.0]: https://github.com/HelgeSverre/fence/compare/v0.5.0...v0.6.0
[0.5.0]: https://github.com/HelgeSverre/fence/compare/v0.4.2...v0.5.0
[0.4.2]: https://github.com/HelgeSverre/fence/compare/v0.4.1...v0.4.2
[0.4.1]: https://github.com/HelgeSverre/fence/compare/v0.4.0...v0.4.1
[0.4.0]: https://github.com/HelgeSverre/fence/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/HelgeSverre/fence/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/HelgeSverre/fence/compare/v0.1.6...v0.2.0
[0.1.6]: https://github.com/HelgeSverre/fence/compare/v0.1.5...v0.1.6
[0.1.5]: https://github.com/HelgeSverre/fence/compare/v0.1.4...v0.1.5
[0.1.4]: https://github.com/HelgeSverre/fence/compare/v0.1.3...v0.1.4
[0.1.3]: https://github.com/HelgeSverre/fence/compare/v0.1.2...v0.1.3
[0.1.2]: https://github.com/HelgeSverre/fence/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/HelgeSverre/fence/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/HelgeSverre/fence/releases/tag/v0.1.0
