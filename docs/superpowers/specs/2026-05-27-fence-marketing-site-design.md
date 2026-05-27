# Fence Marketing Site — Design Spec

**Date:** 2026-05-27
**Status:** Approved (design phase)
**Owner:** helge.sverre@gmail.com

## Goal

Build a static marketing site for Fence (the Elm + Electron Markdown editor) using
AnalogJS, scaffolded at `website/` inside this repo. The site introduces the editor,
shows what it does, and points visitors to a download.

## Non-goals

- No blog, CMS, analytics, newsletter, or i18n.
- No auto-detection of visitor OS for download links — links go to GitHub releases.
- No e2e tests for marketing copy.
- No server runtime: site is fully static (SSG only).

## Stack

- **Framework:** AnalogJS (latest) on Angular standalone components.
- **Bundler:** Vite (via `@analogjs/platform`).
- **Content:** `@analogjs/content` for markdown routes and rendering.
- **Output:** Static HTML in `website/dist/analog/public/`, deployable anywhere.
- **Dev server:** `cd website && npm run start` on port 5173.

The website project is isolated from the root Elm+Electron build — its own
`package.json`, `node_modules/`, and `vite.config.ts`. The root app is unaffected.

## Folder layout

```
website/
  package.json
  vite.config.ts            # analog plugin, static: true, prerender routes listed
  tsconfig.json
  tsconfig.app.json
  index.html
  public/
    favicon.svg
    screenshots/            # copied from repo root + new captures as added
  src/
    main.ts                 # bootstrapApplication
    app/
      app.component.ts      # root layout: <site-header>, <router-outlet>, <site-footer>
      app.config.ts         # provideFileRouter, provideContent, withMarkdownRenderer
      pages/
        index.page.ts       # "/"
        features.page.ts    # "/features"
        download.page.ts    # "/download"
        docs.page.ts        # "/docs"
        about.md            # "/about"      (markdown route)
        changelog.md        # "/changelog"  (markdown route)
      components/
        site-header.component.ts
        site-footer.component.ts
        hero.component.ts
        feature-card.component.ts
        feature-section.component.ts
        download-card.component.ts
        code-block.component.ts
      shared/
        theme.service.ts    # data-theme switching, persisted to localStorage
    styles.css              # imports tokens.css + base.css + components.css
    styles/
      tokens.css            # oklch palette (mocha + latte), copied from app's main.css
      base.css              # resets, typography, layout primitives
      components.css        # component-scoped styles imported by components
```

## Routing

File-based via `@analogjs/router`. Each entry below is a single route:

| Path         | Source file                | Purpose                                                        |
| ------------ | -------------------------- | -------------------------------------------------------------- |
| `/`          | `pages/index.page.ts`      | Hero + features grid + screenshot + primary CTA                |
| `/features`  | `pages/features.page.ts`   | Long-form feature sections with alternating text+image rows    |
| `/download`  | `pages/download.page.ts`   | Three `download-card` components (macOS, Windows, Linux)       |
| `/docs`      | `pages/docs.page.ts`       | Getting started, keyboard shortcuts, themes, frontmatter usage |
| `/about`     | `pages/about.md`           | Philosophy / why this editor exists                            |
| `/changelog` | `pages/changelog.md`       | Versions and notable changes                                   |

All routes are listed under `prerender.routes` in `vite.config.ts`. `static: true`
disables the server build.

## Components

All standalone Angular components. Inputs are typed; no NgModules.

- **`site-header`** — logo wordmark, nav (Home, Features, Download, Docs, About,
  Changelog), GitHub link, theme toggle button.
- **`site-footer`** — copyright, GitHub link, license, links to relevant Fence
  internals (issue tracker, releases).
- **`hero`** — `@Input() headline`, `@Input() subhead`, `@Input() ctaHref`,
  `@Input() ctaLabel`, content-projected `<img>` slot for the screenshot.
- **`feature-card`** — `@Input() icon` (SVG component name or string), `title`,
  `description`. Used in a 3-column grid on `/`.
- **`feature-section`** — `@Input() title`, `imageSrc`, `imagePosition: 'left'|'right'`,
  content-projected body. Used on `/features`.
- **`download-card`** — `@Input() os: 'mac'|'win'|'linux'`, `@Input() href`,
  `@Input() filename`. Renders OS icon + label + button.
- **`code-block`** — `@Input() language`, content-projected `<pre><code>`. Matches
  the syntax colors from `static/styles/syntax.css`.

## Styling

- Palette: copy the oklch CSS custom properties from
  `static/styles/main.css` into `website/src/styles/tokens.css`. Includes
  `catppuccin-mocha` (default) and `catppuccin-latte` (light). Other themes
  (`fleet-dark`, `github-dark`, `vscode-dark`) are not ported — the site stays
  visually consistent.
- Theme switch: `theme.service.ts` toggles `<html data-theme="...">` and writes
  the choice to `localStorage` under key `fence-site-theme`. Default on first
  visit: `catppuccin-mocha`.
- Fonts: copy `static/fonts/` (JetBrains Mono, IBM Plex Sans) into
  `website/public/fonts/`; `@font-face` declarations in `base.css`.
- Layout: max content width ~960px on prose pages, ~1200px on the landing page.
- No CSS framework — hand-written CSS using the palette tokens.

## Content sources

- **Feature copy:** drafted from `README.md` and `CLAUDE.md`. The landing-page
  feature grid covers: split-view editor + preview, file explorer, YAML
  frontmatter, syntax highlighting, multiple themes, resizable panes.
- **Screenshots:** `screenshot.png` from repo root is the hero image. Additional
  per-feature captures can be added later under `public/screenshots/`.
- **Download links:** point to `https://github.com/<repo>/releases/latest` for
  now. Per-OS deep links can be wired later.
- **Changelog:** initial stub with v0.1.0 and v0.1.1. Future maintenance is manual
  edits to `changelog.md` (no automated GitHub release sync in this spec).

## Build & dev commands

```bash
# inside website/
npm install
npm run start          # dev, http://localhost:5173
npm run build          # static build to dist/analog/public
```

Root `package.json` is untouched. Optional convenience script can be added later
(out of scope here).

## Deployment

Out of scope for this spec. The build output is static; pick a host later.

## Open questions

None at design time. If unknowns surface during implementation (Analog version
quirks, font licensing for redistribution), surface them at that point.
