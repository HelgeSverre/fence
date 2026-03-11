<p align="center">
  <img src="screenshot.png" alt="Fence — Split-view Markdown Editor" width="800" />

</p>

<h1 align="center">Fence</h1>

<p align="center">
  A split-view markdown editor built with Elm and Electron.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Elm-0.19.1-1293D8?logo=elm&logoColor=white" alt="Elm" />
  <img src="https://img.shields.io/badge/Electron-28-47848F?logo=electron&logoColor=white" alt="Electron" />
  <img src="https://img.shields.io/badge/Markdown-Editor-000000?logo=markdown&logoColor=white" alt="Markdown" />
  <img src="https://img.shields.io/badge/Vite-5-646CFF?logo=vite&logoColor=white" alt="Vite" />
  <img src="https://img.shields.io/badge/License-MIT-green" alt="License" />
</p>

---

Fence provides a clean, focused environment for writing markdown with a live preview, frontmatter support, and syntax
highlighting.

## Features

- **Split-View Editor** — Real-time markdown preview as you type
- **Frontmatter Support** — Parses and displays YAML frontmatter
- **Syntax Highlighting** — Built-in support for Elm, JavaScript, Python, CSS, JSON, and more
- **File Explorer** — Integrated file tree for managing your markdown files
- **Themes** — Customizable themes for the editor environment
- **Built with Elm** — Type-safe, reliable editing experience

## Getting Started

### Prerequisites

- [Node.js](https://nodejs.org/) (latest LTS recommended)
- [Elm](https://guide.elm-lang.org/install/elm.html)

### Installation

```bash
git clone https://github.com/helgesverre/fence.git
cd fence
npm install
```

### Development

Start the development server with hot-reloading:

```bash
npm run dev
```

With Electron DevTools enabled:

```bash
npm run dev:debug
```

### Building

Build the application for production:

```bash
npm run build
```

## Project Structure

```
src/            Elm source code
├── Main.elm        Main application entry point
├── Editor.elm      Markdown editor component
├── Markdown.elm    Markdown parsing and rendering
└── FileTree.elm    File navigation component
electron/       Electron main process and preload scripts
js/             JavaScript glue code and Ports
static/         CSS styles and static assets
tests/          Elm test suite
```

## Tech Stack

| Layer    | Technology                                    |
| -------- | --------------------------------------------- |
| Frontend | [Elm](https://elm-lang.org/)                  |
| Desktop  | [Electron](https://www.electronjs.org/)       |
| Build    | [Vite](https://vitejs.dev/) + vite-plugin-elm |
| Testing  | elm-test                                      |

## License

MIT
