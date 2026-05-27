---
title: About Fence
meta:
  - name: description
    content: The philosophy behind Fence — a focused Markdown editor.
---

# Why Fence exists

Most Markdown editors try to be a knowledge graph, a publishing platform, or a
notes-and-tasks app. Fence isn't any of those. It's a desktop app for writing
Markdown files in a folder and seeing what they look like rendered.

## The shape of it

- One window. Tree on the left, editor in the middle, preview on the right.
- Files live on your disk, in folders you control. No database, no sync server.
- No accounts, no telemetry, no analytics, no surprise subscription.
- The whole thing is MIT licensed and the source is on GitHub.

## How it's built

Fence is written in **Elm** and runs in **Electron**. Elm gives the renderer the
single Model/Update/View story that makes the UI predictable. Electron handles
file I/O, window state, and OS integration. Vite handles the dev build.

The split between renderer and main process is strict: the renderer can't touch
the file system directly. Everything goes through ports — typed messages from
Elm to JS, then through a context-bridged preload, then to Node in the main
process. It's a few more files, but it means no surprises.

## Who it's for

People who already write a lot of Markdown — for docs, blog posts, notes, README
files — and want a small native app that gets out of the way. If that sounds
like you, [download a build](/download) or [browse the source](https://github.com/HelgeSverre/fence).
