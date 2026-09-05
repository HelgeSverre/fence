# Changelog

Notable changes to Fence. Dates are release dates; versions follow
[semantic versioning](https://semver.org/) and the format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

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

[Unreleased]: https://github.com/HelgeSverre/fence/compare/v0.1.6...HEAD
[0.1.6]: https://github.com/HelgeSverre/fence/compare/v0.1.5...v0.1.6
[0.1.5]: https://github.com/HelgeSverre/fence/compare/v0.1.4...v0.1.5
[0.1.4]: https://github.com/HelgeSverre/fence/compare/v0.1.3...v0.1.4
[0.1.3]: https://github.com/HelgeSverre/fence/compare/v0.1.2...v0.1.3
[0.1.2]: https://github.com/HelgeSverre/fence/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/HelgeSverre/fence/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/HelgeSverre/fence/releases/tag/v0.1.0
