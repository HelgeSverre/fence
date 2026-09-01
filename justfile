# Fence — split-view markdown editor (Elm + Electron, built with Vite/bun).

[private]
default:
    @just --list

# Install dependencies.
setup:
    bun install

# Start Vite dev server + Electron with hot reload.
[group('run')]
dev:
    bun run dev

# Same, with Electron DevTools open.
[group('run')]
dev-debug:
    bun run dev:debug

# Run the Elm test suite.
[group('check')]
test:
    bun run test

# Build renderer + package with electron-builder.
[group('build')]
build:
    bun run build

# Package for macOS.
[group('build')]
build-mac:
    bun run build:mac

# Package for Windows.
[group('build')]
build-win:
    bun run build:win

# Package for Linux.
[group('build')]
build-linux:
    bun run build:linux

# Remove build artifacts.
[group('build')]
clean:
    rm -rf dist dist-electron release elm-stuff

# Build .app (signed if certs present), install to /Applications + `fence` CLI shim.
[group('build')]
[macos]
install:
    #!/usr/bin/env bash
    set -euo pipefail
    bunx vite build
    CSC_IDENTITY_AUTO_DISCOVERY=false bunx electron-builder --mac dir
    app=$(ls -d release/mac*/Fence.app | head -1)
    rm -rf /Applications/Fence.app
    ditto "$app" /Applications/Fence.app
    mkdir -p "$HOME/.local/bin"
    printf '#!/bin/sh\nnohup /Applications/Fence.app/Contents/MacOS/Fence "$@" >/dev/null 2>&1 &\n' > "$HOME/.local/bin/fence"
    chmod +x "$HOME/.local/bin/fence"
    echo "Installed /Applications/Fence.app and $HOME/.local/bin/fence"

# Remove installed .app and CLI shim.
[group('build')]
[macos]
uninstall:
    rm -rf /Applications/Fence.app
    rm -f ~/.local/bin/fence
    @echo "Removed /Applications/Fence.app and ~/.local/bin/fence"
