<p align="center">
  <img src="screenshot.png" alt="Fence — Split-view Markdown Editor" width="800" />

</p>

<h1 align="center">Fence</h1>

<p align="center">
  A split-view markdown editor built with Elm and Electron.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Elm-0.19.1-1293D8?logo=elm&logoColor=white" alt="Elm" />
  <img src="https://img.shields.io/badge/Electron-41-47848F?logo=electron&logoColor=white" alt="Electron" />
  <img src="https://img.shields.io/badge/Markdown-Editor-000000?logo=markdown&logoColor=white" alt="Markdown" />
  <img src="https://img.shields.io/badge/Vite-5-646CFF?logo=vite&logoColor=white" alt="Vite" />
  <img src="https://img.shields.io/badge/License-MIT-green" alt="License" />
</p>

---

Fence provides a clean, focused environment for writing markdown with a live preview, frontmatter support, syntax highlighting, and mermaid diagram rendering.

## Features

- **Flexible Layout** — Editor, preview, or split view with synchronized scrolling
- **Find & Replace** — Cmd+F, with match highlighting and a single-undo Replace All
- **Quick-Open & Search** — Cmd+P by file name, Cmd+Shift+F across the workspace
- **Markdown Editing** — List continuation, bold/italic/link shortcuts, line operations
- **File Management** — Create, rename and trash files and folders from the tree
- **Export** — PDF, HTML, or rich text on the clipboard
- **Frontmatter Support** — Parses and displays YAML frontmatter
- **Syntax Highlighting** — Built-in support for Elm, JavaScript, Python, CSS, JSON, and more
- **Mermaid Diagrams** — Render mermaid diagrams directly in the preview
- **Images** — Paste one in and it is saved beside the document and linked
- **Themes** — Customizable themes for the editor environment
- **Auto-Update** — Built-in auto-updater via GitHub releases
- **Cross-Platform** — Builds for macOS, Windows, and Linux

## Install

```bash
brew install --cask helgesverre/tap/fence
```

Or grab a DMG from the [releases page](https://github.com/HelgeSverre/fence/releases).
See [CHANGELOG.md](CHANGELOG.md) for what changed in each version.

## Getting Started

### Prerequisites

- [Bun](https://bun.sh/)

### Setup from source

```bash
git clone https://github.com/helgesverre/fence.git
cd fence
bun install
```

### Development

Start the development server with hot-reloading:

```bash
bun run dev
```

With Electron DevTools enabled:

```bash
bun run dev:debug
```

### Building

Build for your platform:

```bash
# Generic build
bun run build

# Platform-specific
bun run build:mac
bun run build:win
bun run build:linux
```

## Project Structure

```
src/
├── Main.elm            Application entry point
├── Editor.elm          Editing: cursor, selection, undo, shortcuts
├── VirtualEditor.elm   The editor's view: only visible rows
├── TextBuffer.elm      Pure edits over the document's lines
├── Find.elm            Find and replace
├── Palette.elm         Quick-open and workspace search
├── Markdown.elm        Markdown parsing and rendering
├── Preview.elm         Preview pane rendering
├── FileTree.elm        File navigation component
├── Frontmatter.elm     YAML frontmatter parsing
├── Yaml.elm            YAML parser
├── Ports.elm           Elm port definitions
├── Types.elm           Shared types
└── Icon.elm            SVG icon components
electron/
├── main.js             Electron main process
├── preload.js          Preload script (context bridge)
└── fs-ops.js           File system operations
js/
├── main.js             App initialization
├── elm.js              Elm app bootstrap
├── ports.js            Port subscriptions
├── virtual-input.js    Editor hidden-input glue (paste, copy/cut, focus, IME)
├── editor-metrics.js   Measures monospace metrics for the editor
└── mermaid-init.js     Mermaid diagram rendering
static/
├── fonts/              Bundled fonts
└── styles/             CSS stylesheets
tests/                  elm-test suites, one per module
e2e/                    Playwright tests driving the packaged app
```

## Keyboard shortcuts

On Windows and Linux, use Ctrl where this says Cmd.

| Shortcut                | Action                                  |
| ----------------------- | --------------------------------------- |
| Cmd+S                   | Save                                    |
| Cmd+N / Cmd+Shift+N     | New file / new folder                   |
| Cmd+P                   | Go to file                              |
| Cmd+Shift+F             | Search the workspace                    |
| Cmd+F / Cmd+Alt+F       | Find / find and replace                 |
| Cmd+G / Cmd+Shift+G     | Next / previous match                   |
| Cmd+[ / Cmd+]           | Back / forward through opened files     |
| Cmd+B / Cmd+I / Cmd+E   | Bold / italic / code                    |
| Cmd+Shift+X / Cmd+K     | Strikethrough / link                    |
| Cmd+/                   | Comment out the selected lines          |
| Cmd+Shift+D             | Duplicate the line or selection         |
| Alt+Up / Alt+Down       | Move the line or selection              |
| Cmd+Shift+K             | Delete the line                         |
| Cmd+Enter / +Shift      | Open a line below / above               |
| Cmd+1 / Cmd+3           | Toggle the sidebar / outline            |
| Cmd+2                   | Cycle Editor / Split / Preview          |

Use the three layout buttons beside Settings to select a mode directly. Fence remembers the mode and split width. Rebind the layout shortcut under Settings → Shortcuts. In preview-only mode, Find searches rendered text; Find and Replace opens Split to edit the source.

## Tech Stack

| Layer    | Technology                                    |
| -------- | --------------------------------------------- |
| Frontend | [Elm](https://elm-lang.org/)                  |
| Desktop  | [Electron](https://www.electronjs.org/)       |
| Build    | [Vite](https://vitejs.dev/) + vite-plugin-elm |
| Diagrams | [Mermaid](https://mermaid.js.org/)            |
| Testing  | elm-test                                      |

## License

MIT
