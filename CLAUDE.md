# Fence - CLAUDE.md

## Project Overview

Fence is a desktop Markdown editor built with **Elm + Electron**. It features a split-view layout with a file explorer, real-time preview, YAML frontmatter support, syntax highlighting, multiple themes, and resizable panes.

## Tech Stack

- **Frontend**: Elm 0.19.2 (TEA architecture)
- **Desktop**: Electron 44
- **Build**: Vite 8 + vite-plugin-elm
- **Markdown**: dillonkearns/elm-markdown
- **File Watching**: chokidar
- **Packaging**: electron-builder

## Project Structure

```
src/              # Elm source code
  Main.elm        # App entry, Model, update, view, drag/resize logic
  Types.elm       # Core type definitions
  Editor.elm      # Editor component with syntax highlighting overlay
  FileTree.elm    # File browser with OutCmd side-effect pattern
  Markdown.elm    # Markdown parsing and custom renderer
  Preview.elm     # Preview pane
  Frontmatter.elm # YAML frontmatter extraction
  Yaml.elm        # Custom YAML parser (elm/parser combinators)
  Icon.elm        # SVG icon components
  Ports.elm       # Elm <-> Electron IPC bridge definitions
electron/
  main.js         # Electron app init, window management, state persistence
  preload.js      # Secure contextBridge IPC
  fs-ops.js       # File system operations, chokidar watcher
js/
  main.js         # Elm app initialization and flags
  ports.js        # Port wiring and theme management
  virtual-input.js # hidden-input glue: paste, copy/cut, focus, IME
  editor-metrics.js # measures monospace metrics for the editor
  elm.js          # Generated Elm bundle (do not edit)
static/
  styles/
    main.css      # Root CSS variables, 5 themes (oklch color space)
    editor.css    # Editor textarea + highlight overlay
    preview.css   # Preview pane markdown styles
    file-tree.css # Sidebar file browser
    syntax.css    # Code block syntax highlighting
  fonts/          # Bundled web fonts (JetBrains Mono, IBM Plex, etc.)
build/icons/      # App icons (icns, ico, png)
lib/              # Custom syntax highlighting library
```

## Development Commands

```bash
bun run dev        # Start Vite dev server + Electron concurrently
bun run build      # Production build and Electron package
bun run dev:debug  # Open Electron DevTools
```

Vite dev server runs on **port 5173**.

## Architecture Notes

### Elm Architecture (TEA)

The app uses standard TEA. `Main.elm` composes `FileTree`, `Editor`, `Markdown`, `Preview` modules.

### OutCmd Pattern

`FileTree.elm` uses an `OutCmd` type instead of `Cmd` for side effects, letting `Main.elm` translate them to port calls:

```elm
type OutCmd = CmdOpenFolder | CmdReadDir | CmdReadFile | CmdWatchDir | CmdUnwatchDir
```

### Resizable Panes

Drag state tracks mouse delta relative to window width. Sidebar clamped to 8-40%, editor/preview split to 15-85%. Values persisted to Electron `state.json`.

### IPC (Ports)

All file I/O and window operations go through `Ports.elm` → `preload.js` contextBridge → `electron/main.js`. No direct Node access from renderer.

### Editor

A virtualized editor written in Elm (`src/VirtualEditor.elm` view, `src/TextBuffer.elm` edits, cursor/selection/undo in `src/Editor.elm`): only visible rows exist in the DOM, a hidden textarea under the caret takes keys, IME and paste (`js/virtual-input.js`), and `js/editor-metrics.js` measures the monospace metrics. No wrapping; long lines scroll horizontally. `e2e/virtual-editor.test.js` is the open-time gate on a 700KB reference file.

### Progressive Markdown Parsing

Editor changes use a generation counter (50-400ms debounce by size) to discard stale parses. Documents are split at top-level headings (`Markdown.splitChunks`) and parsed chunk by chunk with a per-chunk cache; `Markdown.begin`/`step` render within a character budget and Main continues in `Frame` messages (one step every other animation frame) so a large file paints its first screen in ~150ms. 

### Themes

CSS `data-theme` attribute switching. 5 themes: `catppuccin-mocha` (default), `catppuccin-latte`, `github-dark`, `vscode-dark`, `fleet-dark`. Colors use oklch for perceptual consistency.

### State Persistence

Electron persists `sidebarFraction`, `editorFraction`, and recent workspaces to `app.getPath('userData')/state.json`.

### File Watching

chokidar watches the open directory and pushes change events to Elm via ports. Auto-reloads files with no unsaved changes.

## Key Files to Know

- `src/Main.elm` — central model, all Msg variants, update function, view layout
- `src/Ports.elm` — all port declarations (Elm ↔ Electron)
- `electron/main.js` — IPC handlers, window lifecycle, state persistence
- `electron/fs-ops.js` — file read/write/watch, directory listing
- `js/ports.js` — port subscriptions wired up on the JS side
- `static/styles/main.css` — theme variables (start here for styling changes)

## Elm Dependencies (elm.json)

- `elm/browser`, `elm/core`, `elm/html`, `elm/json`, `elm/svg`
- `elm/parser` (YAML parser)
- `elm/regex`, `elm/time`
- `dillonkearns/elm-markdown` 7.0.1
- `dillonkearns/elm-graphql` (via indirect)
- `rtfeldman/elm-hex`

## Notes

- `js/elm.js` is the generated Elm bundle — never edit manually, regenerated by `bun run build`
- The editor renders only visible rows; see `src/VirtualEditor.elm`
- Frontmatter is extracted before passing content to the Markdown renderer
- Keyboard navigation in file tree: arrow keys + Enter
