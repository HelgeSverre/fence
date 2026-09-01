import { ChangeDetectionStrategy, Component } from '@angular/core';
import { RouteMeta } from '@analogjs/router';

export const routeMeta: RouteMeta = {
  title: 'Docs — Fence',
  meta: [
    { name: 'description', content: 'Getting started with Fence: opening a workspace, editing, preview, frontmatter, themes, and keyboard shortcuts.' },
    { property: 'og:title', content: 'Docs — Fence' },
    { property: 'og:description', content: 'Getting started with Fence: opening a workspace, editing, preview, frontmatter, themes, and keyboard shortcuts.' },
  ],
};

@Component({
  selector: 'page-docs',
  standalone: true,
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div class="prose">
      <span class="eyebrow">Docs</span>
      <h1>Getting started with Fence</h1>
      <p class="lead">
        Fence keeps things simple. Most of what you need is one keyboard shortcut away.
      </p>

      <h2>Open a folder</h2>
      <p>
        On launch, choose a folder via <kbd>⌘O</kbd> (or <kbd>Ctrl+O</kbd> on Windows /
        Linux — every <kbd>⌘</kbd> shortcut below is <kbd>Ctrl</kbd> there). Fence will treat it as your workspace, watch it for changes, and remember
        it as a recent workspace.
      </p>

      <h2>Editing</h2>
      <p>
        The left pane is a plain textarea with syntax highlighting overlaid on top. Use
        <kbd>Tab</kbd> and <kbd>Shift+Tab</kbd> for indentation. Save with <kbd>⌘S</kbd>.
      </p>

      <h2>Preview</h2>
      <p>
        The right pane shows your Markdown rendered. Parsing is debounced — you'll see the
        preview update a fraction of a second after you stop typing.
      </p>

      <h2>Frontmatter</h2>
      <p>Start your file with a YAML block to set metadata:</p>
      <pre><code>---
title: My document
date: 2026-05-27
tags: [markdown, writing]
---

# Hello, Fence

Your content goes here.</code></pre>
      <p>Frontmatter is extracted and shown as a metadata block above the document body.</p>

      <h2>Themes</h2>
      <p>
        Open the settings dropdown from the title bar to switch themes. Available options:
      </p>
      <ul>
        <li>Catppuccin Mocha (default)</li>
        <li>Catppuccin Latte</li>
        <li>Fleet Dark</li>
        <li>GitHub Dark</li>
        <li>VS Code Dark+</li>
        <li>Dracula</li>
        <li>One Dark Pro</li>
        <li>Tokyo Night</li>
        <li>Nord</li>
      </ul>

      <h2>Resizable panes</h2>
      <p>
        Drag any divider to resize. The sidebar clamps between 8–40% of window width; the
        editor/preview split clamps between 15–85%. Your layout is saved automatically.
      </p>

      <h2>Keyboard shortcuts</h2>
      <ul>
        <li><kbd>⌘O</kbd> — open folder</li>
        <li><kbd>⌘S</kbd> — save current file</li>
        <li><kbd>⌘,</kbd> — open settings (themes and fonts)</li>
        <li><kbd>Tab</kbd> / <kbd>Shift+Tab</kbd> — indent / outdent in the editor</li>
        <li>Arrow keys + <kbd>Enter</kbd> — navigate the file tree</li>
      </ul>
    </div>
  `,
})
export default class DocsPage {}
