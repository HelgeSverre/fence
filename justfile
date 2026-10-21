# Fence — split-view markdown editor (Elm + Electron, built with Vite/bun).
# Plain `bun run <script>` wrappers are kept for discoverability only; see package.json.

[private]
default:
    @just --list

# Install dependencies and vendor the sans fonts; a fast no-op when nothing changed.
setup:
    bun install
    bun run vendor-fonts

# Start Vite dev server + Electron with hot reload.
[group('run')]
dev: setup
    bun run dev

# Same, with Electron DevTools open.
[group('run')]
dev-debug: setup
    bun run dev:debug

# Build and launch a local macOS app bundle; optional args go to Fence (e.g. just run samples/mermaid.md).
[group('run')]
[macos]
[positional-arguments]
run *args: setup
    #!/usr/bin/env bash
    set -euo pipefail
    case "$(uname -m)" in
      arm64) arch=arm64; app_dir=release/run/mac-arm64 ;;
      x86_64) arch=x64; app_dir=release/run/mac ;;
      *) echo "Unsupported macOS architecture" >&2; exit 1 ;;
    esac
    bunx vite build
    CSC_IDENTITY_AUTO_DISCOVERY=false bunx electron-builder --mac dir "--$arch" --publish never \
      -c.directories.output=release/run -c.mac.identity=- -c.mac.forceCodeSigning=false \
      -c.mac.hardenedRuntime=false -c.mac.notarize=false
    # Keep a persistent test profile with its own single-instance lock.
    # FENCE_USER_DATA can override it to test against a specific profile.
    export FENCE_USER_DATA="${FENCE_USER_DATA:-$HOME/Library/Application Support/fence-run}"
    exec "$app_dir/Fence.app/Contents/MacOS/Fence" "$@"

# Run the Elm and Node unit tests.
[group('check')]
test: setup
    bun run test

# Build the renderer, then run the Playwright/Electron end-to-end suite.
[group('check')]
test-e2e: setup
    bunx vite build
    bun run test:e2e

# Build renderer + package with electron-builder.
[group('build')]
build: setup
    bun run build

# Package for macOS / Windows / Linux.
[group('build')]
build-mac: setup
    bun run build:mac

[group('build')]
build-win: setup
    bun run build:win

[group('build')]
build-linux: setup
    bun run build:linux

# Remove build artifacts.
[group('build')]
clean:
    rm -rf dist dist-electron release elm-stuff

# Build .app (signed if certs present), install to /Applications + `fence` CLI shim.
[group('build')]
[macos]
install: setup
    #!/usr/bin/env bash
    set -euo pipefail
    bunx vite build
    CSC_IDENTITY_AUTO_DISCOVERY=false bunx electron-builder --mac dir
    app=$(ls -d release/mac*/Fence.app | head -1)
    rm -rf /Applications/Fence.app
    ditto "$app" /Applications/Fence.app
    mkdir -p "$HOME/.local/bin"
    cat > "$HOME/.local/bin/fence" <<'SH'
    #!/bin/sh
    exe="/Applications/Fence.app/Contents/MacOS/Fence"
    for a in "$@"; do case "$a" in -h|--help|-v|--version) exec "$exe" "$@";; esac; done
    nohup "$exe" "$@" >/dev/null 2>&1 &
    SH
    chmod +x "$HOME/.local/bin/fence"
    echo "Installed /Applications/Fence.app and $HOME/.local/bin/fence"

# Remove installed .app and CLI shim.
[group('build')]
[macos]
uninstall:
    rm -rf /Applications/Fence.app
    rm -f ~/.local/bin/fence
    @echo "Removed /Applications/Fence.app and ~/.local/bin/fence"

# Re-copy sans woff2 files from @fontsource and regenerate static/styles/fonts.css.
[group('build')]
vendor-fonts:
    bun run vendor-fonts
