# Fence – Agent Guide

## Commands

- **Dev:** `bun run dev` (Vite + Electron with hot-reload)
- **Build:** `bun run build` (production build via electron-builder)
- **Test all:** `bun run test`
- **Test single:** `bunx elm-test tests/YamlTest.elm`

## Architecture

Elm 0.19.1 frontend + Electron 28 desktop shell, bundled with Vite.

- `src/` — Elm app: `Main.elm` (entry, TEA app), `Types.elm` (shared types), `Ports.elm` (JS interop), `Editor.elm`, `Preview.elm`, `Markdown.elm`, `FileTree.elm`, `Frontmatter.elm`, `Yaml.elm`, `Icon.elm`
- `electron/` — Main process (`main.js`), preload script, filesystem ops (`fs-ops.js`)
- `js/` — JS glue: Elm init (`elm.js`), port handlers (`ports.js`), editor input and metrics (`virtual-input.js`, `editor-metrics.js`)
- Elm↔JS communication uses ports (`Ports.toElectron`/`Ports.fromElectron`) with JSON-encoded messages

## Code Style

- **Elm:** Standard Elm conventions — `PascalCase` types, `camelCase` functions/values. Use `exposing (..)` only for `Types`. Qualify other imports (`Json.Decode as D`, `Json.Encode as E`). Custom types over type aliases for domain models (see `FileEntry`).
- **JS:** Vanilla ES modules, no framework. Use `const`, template literals, and DOM APIs directly.
- **No database** — filesystem-only via Electron IPC. No external services.
