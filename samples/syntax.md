---
title: Syntax Highlighting QA
description: Manual eyeball test for every fence language Fence supports
---

# Syntax Highlighting QA

Open this file in Fence and scroll the preview pane. Every section below is one
fenced code block in a language Fence claims to highlight. Read each block and
check that comments, strings, numbers, keywords and types are actually coloured
differently from each other — and that nothing bleeds (an unterminated string
swallowing the rest of the block is the classic failure). Switch themes while
scrolling; the colours change, the token boundaries must not.

The last section is the control group: languages with no lexer, which must
render as plain unstyled text.

## Contents

- [Fence edge cases](#fence-edge-cases)
- [elm](#elm) · [javascript](#javascript) · [typescript](#typescript) · [python](#python)
- [css](#css) · [json](#json) · [sql](#sql) · [xml / html](#xml--html)
- [go](#go) · [c](#c) · [cpp](#cpp) · [rust](#rust) · [nix](#nix)
- [php](#php) · [dart](#dart) · [fsharp](#fsharp) · [kotlin](#kotlin)
- [bash](#bash) · [dockerfile](#dockerfile) · [yaml](#yaml) · [toml](#toml)
- [ruby](#ruby) · [java](#java) · [csharp](#csharp) · [swift](#swift) · [scala](#scala)
- [Planned / not yet highlighted](#planned--not-yet-highlighted)

## Fence edge cases

A fence with no info string at all — should render plain:

```
GET /v1/documents?limit=50 HTTP/1.1
Authorization: Bearer sk-live-2f9c...
Accept: application/json
```

A fence whose info string carries extra words after the language. The first word
is the language; the rest is metadata and must not break the lookup:

```js title="app.js" {3-5} showLineNumbers
const routes = new Map();
export function register(path, handler) {
  if (routes.has(path)) throw new Error(`duplicate route: ${path}`);
  routes.set(path, handler);
  return () => routes.delete(path);
}
```

A tilde-delimited fence, which CommonMark treats exactly like a backtick fence:

~~~python
def chunk(items, size):
    """Yield successive slices of `size`."""
    for i in range(0, len(items), size):
        yield items[i : i + size]
~~~

An indented code block — four spaces, no fence, no info string, so no
highlighting is possible:

    $ fence samples/syntax.md
    loaded 1 document (14.2 KB) in 38ms

A fence containing another fence, escaped by using more backticks on the outside:

````markdown
Here is how you tag a block:

```elm
main : Program () Model Msg
```
````

## elm

```elm
module Invoice exposing (Invoice, Line, total, decoder)

import Json.Decode as D exposing (Decoder)


{-| A single billable line. `quantity` is never zero -- see `Line.make`.
-}
type alias Line =
    { sku : String
    , quantity : Int
    , unitCents : Int
    }


type Invoice
    = Draft (List Line)
    | Issued { number : String, lines : List Line, vatRate : Float }


total : Invoice -> Int
total invoice =
    case invoice of
        Draft lines ->
            List.foldl (\l acc -> acc + l.quantity * l.unitCents) 0 lines

        Issued { lines, vatRate } ->
            let
                net =
                    List.sum (List.map (\l -> l.quantity * l.unitCents) lines)
            in
            net + round (toFloat net * vatRate)


decoder : Decoder Line
decoder =
    D.map3 Line
        (D.field "sku" D.string)
        (D.field "quantity" D.int)
        (D.field "unit_cents" D.int)
```

## javascript

```javascript
import { createHash } from "node:crypto";

/**
 * Signed, expiring download links.
 * @param {string} secret - HMAC key, 32 bytes of entropy or better.
 */
export class LinkSigner {
  #secret;
  static TTL_MS = 15 * 60 * 1000; // 15 minutes

  constructor(secret) {
    if (typeof secret !== "string" || secret.length < 32) {
      throw new TypeError(`secret too short: ${secret?.length ?? 0} chars`);
    }
    this.#secret = secret;
  }

  sign(path, now = Date.now()) {
    const expires = now + LinkSigner.TTL_MS;
    const raw = `${path}\n${expires}\n\u2713`;
    const mac = createHash("sha256").update(raw).digest("hex").slice(0, 0x20);
    return `${path}?exp=${expires}&sig=${mac}`;
  }

  /* Block comment: constant-time compare lives in `timingSafeEqual`,
     this regex is only a shape check. */
  static looksSigned(url) {
    return /[?&]sig=[0-9a-f]{32}\b/.test(url);
  }
}

const signer = new LinkSigner(process.env.LINK_SECRET ?? "dev".repeat(16));
console.log(signer.sign("/files/report.pdf"), 1_000_000, 0b1010, 0o755, 3.5e-9);
```

## typescript

```typescript
type Result<T, E = Error> =
  | { readonly ok: true; value: T }
  | { readonly ok: false; error: E };

export interface Retry {
  attempts: number;
  backoffMs: number;
  jitter?: boolean;
}

const DEFAULTS: Readonly<Retry> = { attempts: 3, backoffMs: 250, jitter: true };

export async function withRetry<T>(
  fn: (attempt: number) => Promise<T>,
  opts: Partial<Retry> = {},
): Promise<Result<T>> {
  const { attempts, backoffMs, jitter } = { ...DEFAULTS, ...opts };
  let last: unknown;

  for (let i = 1; i <= attempts; i++) {
    try {
      return { ok: true, value: await fn(i) };
    } catch (err: unknown) {
      last = err; // keep the *first* useful stack in a real impl
      const wait = backoffMs * 2 ** (i - 1) * (jitter ? Math.random() : 1);
      await new Promise((r) => setTimeout(r, wait));
    }
  }
  return { ok: false, error: last instanceof Error ? last : new Error(String(last)) };
}

export const isOk = <T, E>(r: Result<T, E>): r is { ok: true; value: T } => r.ok;
```

## python

```python
from __future__ import annotations

import re
from dataclasses import dataclass, field
from functools import lru_cache
from typing import Iterator

SLUG_RE = re.compile(r"[^a-z0-9]+")
MAX_TITLE = 0x80  # 128


@dataclass(slots=True, frozen=True)
class Heading:
    """One `#`-prefixed line, already stripped of its hashes."""

    level: int
    text: str
    anchors: list[str] = field(default_factory=list)

    def __post_init__(self) -> None:
        if not 1 <= self.level <= 6:
            raise ValueError(f"bad heading level: {self.level!r}")

    @property
    def slug(self) -> str:
        return SLUG_RE.sub("-", self.text.lower()).strip("-")


@lru_cache(maxsize=256)
def outline(source: str) -> tuple[Heading, ...]:
    return tuple(_scan(source))


def _scan(source: str) -> Iterator[Heading]:
    for line in source.splitlines():
        if (stripped := line.lstrip()).startswith("#"):
            hashes, _, rest = stripped.partition(" ")
            if set(hashes) == {"#"}:
                yield Heading(len(hashes), rest.strip()[:MAX_TITLE])


if __name__ == "__main__":
    print(*outline("# One\n\n## Two \u2014 with an em dash\n"), sep="\n")
```

## css

```css
@import url("./fonts.css") layer(base);

:root {
  --bg: oklch(0.19 0.02 275);
  --fg: oklch(0.92 0.01 275);
  --accent: oklch(0.74 0.15 30 / 85%);
  --gutter: clamp(0.75rem, 2vw + 0.25rem, 2rem);
}

/* Preview pane: measure-limited, never wider than the reader wants. */
.preview[data-theme="catppuccin-mocha"] .md-code-block {
  background: color-mix(in oklch, var(--bg) 88%, white 12%);
  border-inline-start: 3px solid var(--accent);
  padding: var(--gutter);
  font-feature-settings: "liga" 0, "calt" 1;
  tab-size: 4;
}

.preview h2:has(+ pre) {
  margin-block-end: 0.35em;
}

@media (prefers-reduced-motion: no-preference) {
  .preview a::after {
    content: " \2197";
    transition: opacity 120ms ease-out;
  }
}

@supports not (color: oklch(0 0 0)) {
  :root { --bg: #1e1e2e; --fg: #cdd6f4; }
}
```

## json

```json
{
  "name": "fence",
  "version": "0.5.0",
  "private": true,
  "build": {
    "appId": "no.helgesverre.fence",
    "files": ["js/**/*", "static/**/*", "electron/**/*"],
    "mac": { "category": "public.app-category.developer-tools", "hardenedRuntime": true }
  },
  "preferences": {
    "theme": "catppuccin-mocha",
    "previewMaxWidth": 72,
    "monoPreview": false,
    "fontScale": 1.05,
    "escaped": "a \"quoted\" path: C:\\Users\\helge\\notes \u2014 with \\u2014 too",
    "nulls": [null, true, false, 0, -17, 6.02e23, 1e-7]
  }
}
```

## sql

```sql
-- Monthly retention cohort for workspaces that opened at least one document.
WITH first_seen AS (
    SELECT workspace_id,
           DATE_TRUNC('month', MIN(opened_at)) AS cohort_month
    FROM document_opens
    WHERE opened_at >= TIMESTAMP '2024-01-01 00:00:00'
    GROUP BY workspace_id
),
activity AS (
    SELECT o.workspace_id,
           DATE_TRUNC('month', o.opened_at) AS active_month,
           COUNT(*) FILTER (WHERE o.bytes > 1024 * 512) AS big_docs
    FROM document_opens o
    GROUP BY 1, 2
)
SELECT f.cohort_month,
       EXTRACT(MONTH FROM AGE(a.active_month, f.cohort_month))::INT AS month_index,
       COUNT(DISTINCT a.workspace_id) AS retained,
       ROUND(AVG(a.big_docs), 2) AS avg_big_docs
FROM first_seen f
JOIN activity a USING (workspace_id)
WHERE a.active_month >= f.cohort_month
  AND f.cohort_month <> DATE '1970-01-01'
GROUP BY 1, 2
HAVING COUNT(DISTINCT a.workspace_id) > 5
ORDER BY 1 DESC, 2 ASC
LIMIT 100;
```

## xml / html

```html
<!doctype html>
<html lang="en" data-theme="catppuccin-mocha">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>Fence &mdash; a markdown editor</title>
    <link rel="stylesheet" href="/static/styles/main.css" />
    <!-- The Elm bundle boots itself; no inline config. -->
    <script type="module" src="/js/main.js" defer></script>
  </head>
  <body class="app-shell" style="--preview-max-width: 72ch">
    <aside id="sidebar" aria-label="Files" data-width="22%">
      <ul role="tree">
        <li role="treeitem" aria-expanded="true" data-path="/notes">
          notes
          <ul role="group">
            <li role="treeitem" data-path="/notes/todo.md">todo.md</li>
          </ul>
        </li>
      </ul>
    </aside>
    <main>
      <textarea id="hidden-input" autocapitalize="off" spellcheck="false"></textarea>
      <section class="preview"><!-- rendered by Preview.elm --></section>
    </main>
  </body>
</html>
```

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
  <dict>
    <key>CFBundleIdentifier</key>
    <string>no.helgesverre.fence</string>
    <key>CFBundleDocumentTypes</key>
    <array>
      <dict>
        <key>CFBundleTypeExtensions</key>
        <array><string>md</string><string>markdown</string></array>
        <key>LSHandlerRank</key>
        <string>Alternate</string>
      </dict>
    </array>
    <!-- Entity soup: &amp; &lt; &gt; &#x2014; -->
    <key>NSHumanReadableCopyright</key>
    <string>&#169; 2026 Helge Sverre &amp; contributors</string>
  </dict>
</plist>
```

## go

```go
package watcher

import (
	"context"
	"errors"
	"fmt"
	"path/filepath"
	"sync"
	"time"
)

// ErrClosed is returned once Stop has been called.
var ErrClosed = errors.New("watcher: closed")

type Event struct {
	Path string
	Op   Op
	At   time.Time
}

type Op uint8

const (
	Create Op = 1 << iota
	Write
	Remove
)

func (o Op) String() string {
	switch {
	case o&Create != 0:
		return "create"
	case o&Write != 0:
		return "write"
	default:
		return fmt.Sprintf("op(%#02x)", uint8(o))
	}
}

/* Debounce coalesces bursts from editors that write-then-rename. */
func Debounce(ctx context.Context, in <-chan Event, window time.Duration) <-chan Event {
	out := make(chan Event)
	var mu sync.Mutex
	pending := map[string]Event{}

	go func() {
		defer close(out)
		tick := time.NewTicker(window)
		defer tick.Stop()
		for {
			select {
			case <-ctx.Done():
				return
			case ev, ok := <-in:
				if !ok {
					return
				}
				mu.Lock()
				pending[filepath.Clean(ev.Path)] = ev
				mu.Unlock()
			case <-tick.C:
				mu.Lock()
				for k, ev := range pending {
					out <- ev
					delete(pending, k)
				}
				mu.Unlock()
			}
		}
	}()
	return out
}
```

## c

```c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define ARENA_ALIGN   16u
#define ALIGN_UP(n, a) (((n) + (a) - 1) & ~((size_t)(a) - 1))

#ifndef ARENA_DEFAULT
#  define ARENA_DEFAULT (1 << 20) /* 1 MiB */
#endif

typedef struct arena {
    unsigned char *base;
    size_t         used;
    size_t         cap;
} arena_t;

/* Bump allocator: free() the whole thing or nothing at all. */
static void *arena_alloc(arena_t *a, size_t n)
{
    size_t want = ALIGN_UP(n, ARENA_ALIGN);
    if (a->used + want > a->cap) {
        fprintf(stderr, "arena: out of space (%zu/%zu)\n", a->used, a->cap);
        return NULL;
    }
    void *p = a->base + a->used;
    a->used += want;
    return memset(p, 0, want);
}

int main(int argc, char **argv)
{
    arena_t a = { .base = malloc(ARENA_DEFAULT), .used = 0, .cap = ARENA_DEFAULT };
    if (!a.base) return EXIT_FAILURE;

    char *greeting = arena_alloc(&a, 64);
    snprintf(greeting, 64, "argc=%d\targv0=%s\tsep='%c'\n", argc, argv[0], '\\');
    fputs(greeting, stdout);

    const unsigned mask = 0xDEADBEEFu, oct = 0755, bin = 0b1011;
    printf("%u %o %d %.3f %e\n", mask, oct, bin, 3.14159, 6.02e23);

    free(a.base);
    return 0;
}
```

## cpp

```cpp
#include <algorithm>
#include <chrono>
#include <optional>
#include <string_view>
#include <unordered_map>
#include <vector>

namespace fence::cache {

using namespace std::chrono_literals;

template <typename K, typename V>
class LruCache {
public:
    explicit LruCache(std::size_t capacity) : cap_{capacity} {
        static_assert(sizeof(K) > 0, "key must be a complete type");
    }

    [[nodiscard]] std::optional<V> get(const K& key) noexcept {
        if (auto it = map_.find(key); it != map_.end()) {
            touch(it->second.second);
            return it->second.first;
        }
        return std::nullopt;
    }

    void put(K key, V value) {
        if (map_.size() >= cap_ && !map_.contains(key)) evict_oldest();
        map_.insert_or_assign(std::move(key), std::pair{std::move(value), ++clock_});
    }

private:
    void touch(std::uint64_t& stamp) noexcept { stamp = ++clock_; }

    void evict_oldest() {
        auto oldest = std::min_element(map_.begin(), map_.end(),
            [](const auto& a, const auto& b) { return a.second.second < b.second.second; });
        if (oldest != map_.end()) map_.erase(oldest);
    }

    std::size_t cap_;
    std::uint64_t clock_{0};
    std::unordered_map<K, std::pair<V, std::uint64_t>> map_;
};

// R"(raw string)" and char literals should not confuse the lexer.
inline constexpr std::string_view kPathSep = R"(\\?\C:\Users)";
inline constexpr char kTab = '\t';

}  // namespace fence::cache
```

## rust

```rust
use std::collections::BTreeMap;
use std::fmt;
use std::path::{Path, PathBuf};

/// Frontmatter parsed off the top of a document.
#[derive(Debug, Default, Clone, PartialEq)]
pub struct Frontmatter {
    pub fields: BTreeMap<String, String>,
    pub body_offset: usize,
}

#[derive(Debug)]
pub enum ParseError {
    Unterminated { line: usize },
    BadKey(String),
}

impl fmt::Display for ParseError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            ParseError::Unterminated { line } => write!(f, "unterminated block at line {line}"),
            ParseError::BadKey(k) => write!(f, "bad key: {k:?}"),
        }
    }
}

impl std::error::Error for ParseError {}

pub fn parse(src: &str) -> Result<Frontmatter, ParseError> {
    let mut fm = Frontmatter::default();
    if !src.starts_with("---\n") {
        return Ok(fm);
    }
    for (i, line) in src.lines().enumerate().skip(1) {
        if line == "---" {
            fm.body_offset = i + 1;
            return Ok(fm);
        }
        let (k, v) = line.split_once(':').ok_or_else(|| ParseError::BadKey(line.into()))?;
        fm.fields.insert(k.trim().to_owned(), v.trim().trim_matches('"').to_owned());
    }
    Err(ParseError::Unterminated { line: src.lines().count() })
}

pub fn sidecar(doc: &Path) -> PathBuf {
    doc.with_extension("meta.json")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_simple_block() {
        let fm = parse("---\ntitle: \"Hi \\u{1F600}\"\n---\nbody").unwrap();
        assert_eq!(fm.fields.len(), 1_usize);
        assert!(matches!(parse("---\ntitle: x\n"), Err(ParseError::Unterminated { .. })));
    }
}
```

## nix

```nix
{ lib, stdenv, fetchFromGitHub, bun, electron_44, makeWrapper, ... }:

let
  version = "0.5.0";
  themes = [ "catppuccin-mocha" "catppuccin-latte" "github-dark" ];
in
stdenv.mkDerivation (finalAttrs: {
  pname = "fence";
  inherit version;

  src = fetchFromGitHub {
    owner = "helgesverre";
    repo = "fence";
    rev = "v${version}";
    hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
  };

  nativeBuildInputs = [ bun makeWrapper ];

  # Bun's lockfile is binary; --frozen-lockfile keeps CI honest.
  buildPhase = ''
    runHook preBuild
    bun install --frozen-lockfile --no-progress
    bun run build
    runHook postBuild
  '';

  installPhase = ''
    mkdir -p $out/share/fence $out/bin
    cp -r dist/* $out/share/fence/
    makeWrapper ${electron_44}/bin/electron $out/bin/fence \
      --add-flags $out/share/fence/electron/main.js
  '';

  passthru.availableThemes = themes;

  meta = with lib; {
    description = "A desktop Markdown editor built with Elm and Electron";
    homepage = "https://github.com/helgesverre/fence";
    license = licenses.mit;
    platforms = platforms.darwin ++ platforms.linux;
    maintainers = [ ];
  };
})
```

## php

```php
<?php

declare(strict_types=1);

namespace App\Support;

use InvalidArgumentException;
use Stringable;

/**
 * Immutable byte size, printed the way humans expect.
 */
final class ByteSize implements Stringable
{
    private const UNITS = ['B', 'KiB', 'MiB', 'GiB', 'TiB'];

    public function __construct(private readonly int $bytes)
    {
        if ($bytes < 0) {
            throw new InvalidArgumentException("negative size: {$bytes}");
        }
    }

    public static function fromString(string $input): self
    {
        if (!preg_match('/^(\d+(?:\.\d+)?)\s*([kmgt]?i?b)$/i', trim($input), $m)) {
            throw new InvalidArgumentException(sprintf('cannot parse %s', var_export($input, true)));
        }
        $power = array_search(strtolower($m[2]), array_map('strtolower', self::UNITS), true);

        return new self((int) round((float) $m[1] * (1024 ** ($power ?: 0))));
    }

    public function __toString(): string
    {
        $n = $this->bytes;
        foreach (self::UNITS as $i => $unit) {
            if ($n < 1024 || $i === count(self::UNITS) - 1) {
                return $i === 0 ? "{$n} {$unit}" : number_format($n, 1) . " {$unit}";
            }
            $n /= 1024;
        }
        return 'heredoc fallthrough'; # unreachable
    }
}

$size = ByteSize::fromString('700 KiB');
echo <<<TXT
    reference document: {$size}
    escaped dollar: \$size, backslash: \\, hex: 0x1F4, octal: 0o755
    TXT;
```

## dart

```dart
import 'dart:async';
import 'dart:convert';

/// A single autosave attempt, retried with a widening window.
class Autosaver {
  Autosaver(this.write, {this.debounce = const Duration(milliseconds: 400)});

  final Future<void> Function(String path, String body) write;
  final Duration debounce;
  final Map<String, Timer> _pending = <String, Timer>{};

  static const int maxInflight = 4;
  static final RegExp _tempSuffix = RegExp(r'\.(tmp|swp|~)$');

  void schedule(String path, String body) {
    if (_tempSuffix.hasMatch(path)) return; // editor scratch files
    _pending[path]?.cancel();
    _pending[path] = Timer(debounce, () async {
      try {
        await write(path, body);
      } on FormatException catch (e, st) {
        // ignore: avoid_print
        print('autosave failed for $path: ${e.message}\n$st');
      } finally {
        _pending.remove(path);
      }
    });
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'pending': _pending.keys.toList(growable: false),
        'debounceMs': debounce.inMilliseconds,
      };

  @override
  String toString() => jsonEncode(toJson());
}

enum SaveState { clean, dirty, saving, failed }

extension on SaveState {
  bool get blocksClose => switch (this) {
        SaveState.dirty || SaveState.saving => true,
        _ => false,
      };
}
```

## fsharp

```fsharp
module Fence.Outline

open System
open System.Text.RegularExpressions

/// A heading with its nesting depth, 1..6.
type Heading =
    { Level: int
      Text: string
      Slug: string }

type Node =
    | Leaf of Heading
    | Branch of Heading * Node list

let private slugRe = Regex(@"[^a-z0-9]+", RegexOptions.Compiled)

let private slugify (text: string) =
    slugRe.Replace(text.ToLowerInvariant(), "-").Trim('-')

let parseLine (line: string) : Heading option =
    match line.TrimStart() with
    | s when s.StartsWith "#" ->
        let hashes = s |> Seq.takeWhile ((=) '#') |> Seq.length
        let body = s.Substring(hashes).Trim()
        if hashes <= 6 && body <> "" then
            Some { Level = hashes; Text = body; Slug = slugify body }
        else None
    | _ -> None

let rec private build depth (headings: Heading list) =
    match headings with
    | [] -> [], []
    | h :: rest when h.Level > depth ->
        let children, remaining = build h.Level rest
        let node = if List.isEmpty children then Leaf h else Branch(h, children)
        let siblings, tail = build depth remaining
        node :: siblings, tail
    | _ -> [], headings

let outline (source: string) =
    source.Split('\n')
    |> Array.choose parseLine
    |> List.ofArray
    |> build 0
    |> fst

[<EntryPoint>]
let main argv =
    argv |> Array.iter (IO.File.ReadAllText >> outline >> printfn "%A")
    0
```

## kotlin

```kotlin
package no.helgesverre.fence

import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlin.time.Duration.Companion.milliseconds

@JvmInline
value class DocumentId(val raw: String) {
    init { require(raw.isNotBlank()) { "document id must not be blank" } }
}

sealed interface DocEvent {
    data class Opened(val id: DocumentId, val bytes: Long) : DocEvent
    data class Edited(val id: DocumentId, val generation: Int) : DocEvent
    data object Closed : DocEvent
}

class DocumentStore(private val root: String) {
    private val cache = HashMap<DocumentId, String>(64)

    companion object {
        const val MAX_CACHED = 0x20
        private val DEBOUNCE = 400.milliseconds
    }

    suspend fun load(id: DocumentId): String = cache.getOrPut(id) {
        // In the real app this hits fs-ops.js over IPC.
        """
        ---
        title: ${id.raw}
        ---
        Loaded from $root with a ${'$'} sign and a tab:\t done.
        """.trimIndent()
    }

    fun events(): Flow<DocEvent> = flow {
        emit(DocEvent.Opened(DocumentId("todo.md"), 700L * 1_024))
        repeat(3) { emit(DocEvent.Edited(DocumentId("todo.md"), it + 1)) }
        emit(DocEvent.Closed)
    }

    fun describe(e: DocEvent): String = when (e) {
        is DocEvent.Opened -> "opened ${e.id.raw} (${e.bytes} B)"
        is DocEvent.Edited -> "edit #${e.generation}"
        DocEvent.Closed -> "closed"
    }
}
```

## bash

```bash
#!/usr/bin/env bash
# Package the app and verify the notarized artifact before upload.
set -euo pipefail
IFS=$'\n\t'

readonly APP_NAME="Fence"
readonly DIST_DIR="${DIST_DIR:-dist}"
VERSION="$(jq -r '.version' package.json)"

log() { printf '\033[1;34m==>\033[0m %s\n' "$*" >&2; }

die() {
  printf 'error: %s\n' "$1" >&2
  exit "${2:-1}"
}

cleanup() {
  local code=$?
  [[ -d "${tmp:-}" ]] && rm -rf -- "$tmp"
  exit $code
}
trap cleanup EXIT INT TERM

tmp="$(mktemp -d)"
[[ -n "$VERSION" && "$VERSION" != "null" ]] || die "no version in package.json" 2

log "building ${APP_NAME} v${VERSION}"
bun run build 2>&1 | tee "$tmp/build.log"

shopt -s nullglob
for dmg in "$DIST_DIR"/*.dmg; do
  size=$(( $(stat -f%z "$dmg") / 1024 / 1024 ))
  log "checking $(basename "$dmg") (${size} MiB)"
  if ! spctl --assess --type open --context context:primary-signature "$dmg"; then
    die "gatekeeper rejected ${dmg}"
  fi
done

case "${1:-}" in
  --upload) gh release upload "v$VERSION" "$DIST_DIR"/*.dmg --clobber ;;
  ''|--dry-run) log "dry run; nothing uploaded" ;;
  *) die "unknown flag: $1" ;;
esac
```

## dockerfile

```dockerfile
# syntax=docker/dockerfile:1.7
ARG BUN_VERSION=1.1.30
ARG NODE_ENV=production

FROM oven/bun:${BUN_VERSION}-slim AS deps
WORKDIR /app
COPY package.json bun.lock ./
RUN --mount=type=cache,target=/root/.bun/install/cache \
    bun install --frozen-lockfile

FROM deps AS build
COPY . .
ENV NODE_ENV=${NODE_ENV}
RUN bun run build && \
    find dist -name '*.map' -delete

FROM nginx:1.27-alpine AS runtime
LABEL org.opencontainers.image.source="https://github.com/helgesverre/fence" \
      org.opencontainers.image.licenses="MIT"

RUN apk add --no-cache curl tini \
 && addgroup -S app && adduser -S -G app app
COPY --from=build --chown=app:app /app/dist /usr/share/nginx/html
COPY docker/nginx.conf /etc/nginx/conf.d/default.conf

USER app
EXPOSE 8080/tcp
VOLUME ["/var/cache/nginx"]
HEALTHCHECK --interval=30s --timeout=3s --retries=3 \
  CMD curl -fsS http://localhost:8080/healthz || exit 1

ENTRYPOINT ["/sbin/tini", "--"]
CMD ["nginx", "-g", "daemon off;"]
```

## yaml

```yaml
# CI: build on every push, package only on tags.
name: build
on:
  push:
    branches: [main]
    tags: ["v*.*.*"]
  workflow_dispatch: {}

env:
  BUN_VERSION: "1.1.30"
  ELM_HOME: ${{ github.workspace }}/.elm

defaults:
  run: { shell: bash }

jobs:
  test:
    runs-on: ${{ matrix.os }}
    timeout-minutes: 20
    strategy:
      fail-fast: false
      matrix:
        os: [ubuntu-latest, macos-14]
        include:
          - os: macos-14
            notarize: true
    steps:
      - uses: actions/checkout@v4
        with: { fetch-depth: 0 }
      - name: Install
        run: |
          curl -fsSL https://bun.sh/install | bash
          echo "$HOME/.bun/bin" >> "$GITHUB_PATH"
      - name: Test
        run: bun run test
      - name: Notes
        # Folded scalar keeps this on one line; block scalar below keeps newlines.
        run: >
          echo "matrix=${{ matrix.os }}"
          && echo done
      - name: Literal
        run: |
          echo 'single quoted: no \escapes'
          echo "double quoted: \t is a tab"
      - if: startsWith(github.ref, 'refs/tags/')
        run: bun run build
```

## toml

```toml
# Cargo-style manifest with most of the scalar shapes TOML allows.
[package]
name = "fence-highlight"
version = "0.5.0"
edition = "2021"
rust-version = "1.79"
description = "Lexers for the Fence markdown editor"
license = "MIT OR Apache-2.0"
keywords = ["markdown", "syntax", "highlighting"]

[dependencies]
serde = { version = "1.0", features = ["derive"], default-features = false }
regex = "1.10"
once_cell = "1"

[dependencies.tokio]
version = "1.38"
features = ["rt-multi-thread", "macros", "fs"]
optional = true

[features]
default = ["async"]
async = ["dep:tokio"]

[profile.release]
lto = "fat"
codegen-units = 1
panic = "abort"
strip = true

[workspace.metadata.bench]
warmup_ms = 250
samples = 0x64
ratios = [0.5, 1.0, 2.5e-1]
enabled = true
started_at = 2026-09-12T08:30:00Z
path_windows = 'C:\Users\helge\fence'
banner = """
multi-line basic string
with an escaped quote: \" and a tab: \t
"""
```

## ruby

```ruby
# frozen_string_literal: true

require "json"
require "pathname"

module Fence
  # Walks a workspace and reports the documents worth indexing.
  class Workspace
    include Enumerable

    IGNORED = %w[.git node_modules dist elm-stuff].freeze
    MAX_BYTES = 2 * 1024 * 1024 # 2 MiB

    attr_reader :root, :extensions

    def initialize(root, extensions: %i[md markdown mdx])
      @root = Pathname.new(root).expand_path
      @extensions = extensions.map(&:to_s)
      raise ArgumentError, "#{@root} is not a directory" unless @root.directory?
    end

    def each(&block)
      return enum_for(:each) unless block_given?

      @root.find do |path|
        Find.prune if path.directory? && IGNORED.include?(path.basename.to_s)
        next unless path.file? && extensions.include?(path.extname.delete(".").downcase)

        yield Document.new(path, path.size) if path.size <= MAX_BYTES
      end
    end

    Document = Struct.new(:path, :bytes) do
      def title
        path.each_line.lazy.grep(/\A\#\s+/).first&.sub(/\A\#+\s*/, "")&.strip || path.basename(".*").to_s
      end

      def to_h = { path: path.to_s, bytes:, title: }
    end

    def to_json(*args)
      map(&:to_h).to_json(*args)
    end
  end
end

=begin
Block comment: `Find.prune` needs `require "find"`; left out on purpose
so the highlighter has something dangling to colour.
=end
puts Fence::Workspace.new(ARGV.fetch(0, ".")).to_json if $PROGRAM_NAME == __FILE__
```

## java

```java
package no.helgesverre.fence;

import java.nio.file.Path;
import java.time.Instant;
import java.util.List;
import java.util.Objects;
import java.util.concurrent.ConcurrentHashMap;
import java.util.stream.Collectors;

/**
 * In-memory index of open documents.
 *
 * @param <T> the payload attached to each entry
 */
public final class DocumentIndex<T> implements AutoCloseable {

    public record Entry<T>(Path path, long bytes, Instant seenAt, T payload) {
        public Entry {
            Objects.requireNonNull(path, "path");
            if (bytes < 0L) throw new IllegalArgumentException("negative size: " + bytes);
        }
    }

    private static final int MAX_ENTRIES = 0x400;
    private static final char PATH_SEP = '/';

    private final ConcurrentHashMap<Path, Entry<T>> entries = new ConcurrentHashMap<>();

    @SafeVarargs
    public final void putAll(Entry<T>... incoming) {
        for (var e : incoming) {
            if (entries.size() >= MAX_ENTRIES) break;
            entries.put(e.path(), e);
        }
    }

    @Override
    @SuppressWarnings("unchecked")
    public void close() {
        entries.clear();
    }

    public List<String> summarize() {
        return entries.values().stream()
                .sorted((a, b) -> Long.compare(b.bytes(), a.bytes()))
                .map(e -> "%s\t%,d bytes\t%s".formatted(e.path(), e.bytes(), e.seenAt()))
                .collect(Collectors.toUnmodifiableList());
    }

    public static void main(String[] args) {
        var index = new DocumentIndex<String>();
        index.putAll(new Entry<>(Path.of("notes", "todo.md"), 1_024L, Instant.now(), "dirty"));
        index.summarize().forEach(System.out::println);
        System.out.printf("sep=%c bin=%d hex=%d%n", PATH_SEP, 0b1010, 0xCAFE);
    }
}
```

## csharp

```csharp
using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;

namespace Fence.Indexing;

public enum SaveState { Clean, Dirty, Saving, Failed }

public readonly record struct DocumentId(string Value)
{
    public override string ToString() => Value;
}

/// <summary>Debounced writer that never loses the last edit.</summary>
public sealed class Autosaver : IAsyncDisposable
{
    private const int MaxInflight = 4;
    private static readonly TimeSpan Debounce = TimeSpan.FromMilliseconds(400);

    private readonly Dictionary<DocumentId, CancellationTokenSource> _pending = new();
    private readonly Func<DocumentId, string, CancellationToken, Task> _write;

    public Autosaver(Func<DocumentId, string, CancellationToken, Task> write)
        => _write = write ?? throw new ArgumentNullException(nameof(write));

    public void Schedule(DocumentId id, string body)
    {
        if (_pending.Remove(id, out var old)) old.Cancel();

        var cts = new CancellationTokenSource();
        _pending[id] = cts;

        _ = Task.Run(async () =>
        {
            try
            {
                await Task.Delay(Debounce, cts.Token).ConfigureAwait(false);
                await _write(id, body, cts.Token).ConfigureAwait(false);
            }
            catch (OperationCanceledException) { /* superseded by a newer edit */ }
        }, cts.Token);
    }

    public string Describe(SaveState state) => state switch
    {
        SaveState.Dirty or SaveState.Saving => $"blocking close ({_pending.Count} pending)",
        SaveState.Failed => @"failed; see C:\Users\helge\logs",
        _ => "clean",
    };

    public async ValueTask DisposeAsync()
    {
        foreach (var cts in _pending.Values) cts.Cancel();
        await Task.WhenAll(Enumerable.Empty<Task>()).ConfigureAwait(false);
    }
}
```

## swift

```swift
import Foundation

/// Frontmatter parsed off the top of a markdown document.
public struct Frontmatter: Equatable, Codable {
    public var fields: [String: String]
    public var bodyOffset: Int

    public init(fields: [String: String] = [:], bodyOffset: Int = 0) {
        self.fields = fields
        self.bodyOffset = bodyOffset
    }
}

public enum ParseError: Error, CustomStringConvertible {
    case unterminated(line: Int)
    case badKey(String)

    public var description: String {
        switch self {
        case .unterminated(let line): return "unterminated block at line \(line)"
        case .badKey(let key): return "bad key: \(key)"
        }
    }
}

public protocol DocumentLoading: AnyObject {
    func load(_ url: URL) async throws -> String
}

extension String {
    /// Splits `---` delimited frontmatter from the body.
    public func parseFrontmatter() throws -> Frontmatter {
        guard hasPrefix("---\n") else { return Frontmatter() }
        var fm = Frontmatter()
        for (i, line) in split(separator: "\n", omittingEmptySubsequences: false).enumerated().dropFirst() {
            if line == "---" {
                fm.bodyOffset = i + 1
                return fm
            }
            guard let sep = line.firstIndex(of: ":") else {
                throw ParseError.badKey(String(line))
            }
            let key = line[..<sep].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: sep)...].trimmingCharacters(in: .whitespaces)
            fm.fields[key] = value.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        }
        throw ParseError.unterminated(line: count)
    }
}

let sample = #"---\ntitle: "Raw \#(1 + 1) strings"\n---"#
print(sample, 0xFF, 0b1010, 1_000_000, 2.5e-3, "tab:\tdone")
```

## scala

```scala
package fence.outline

import scala.annotation.tailrec
import scala.util.matching.Regex

/** A `#`-prefixed heading with its nesting depth. */
final case class Heading(level: Int, text: String):
  require(level >= 1 && level <= 6, s"bad level: $level")
  lazy val slug: String = Heading.slugRe.replaceAllIn(text.toLowerCase, "-").stripSuffix("-")

object Heading:
  private val slugRe: Regex = raw"[^a-z0-9]+".r

  def parse(line: String): Option[Heading] =
    line.trim match
      case s if s.startsWith("#") =>
        val hashes = s.takeWhile(_ == '#').length
        Option.when(hashes <= 6 && s.drop(hashes).trim.nonEmpty)(Heading(hashes, s.drop(hashes).trim))
      case _ => None

enum Node:
  case Leaf(heading: Heading)
  case Branch(heading: Heading, children: List[Node])

object Outline:
  def apply(source: String): List[Node] =
    build(0, source.linesIterator.flatMap(Heading.parse).toList)._1

  @tailrec
  private def drop(depth: Int, hs: List[Heading]): List[Heading] = hs match
    case h :: rest if h.level > depth => drop(depth, rest)
    case other                        => other

  private def build(depth: Int, hs: List[Heading]): (List[Node], List[Heading]) =
    hs match
      case Nil => (Nil, Nil)
      case h :: rest if h.level > depth =>
        val (kids, remaining)   = build(h.level, rest)
        val (siblings, tail)    = build(depth, remaining)
        val node = if kids.isEmpty then Node.Leaf(h) else Node.Branch(h, kids)
        (node :: siblings, tail)
      case _ => (Nil, hs)

  @main def run(paths: String*): Unit =
    paths.foreach(p => println(s"$p -> ${apply(io.Source.fromFile(p).mkString).size} nodes"))
```

## Planned / not yet highlighted

Fence has no lexer for the languages below. Every block in this section is
expected to render as plain, unstyled monospace text — same font and background
as the highlighted blocks, but a single uniform colour, no token colours at all.
If any of these suddenly look colourful, either a lexer landed (update this
file) or the fence tag is being misrouted to the wrong lexer.

```lua
local Buffer = {}
Buffer.__index = Buffer

--- Create a line buffer from a source string.
-- @param src string
function Buffer.new(src)
  local self = setmetatable({ lines = {}, dirty = false }, Buffer)
  for line in string.gmatch(src, "([^\n]*)\n?") do
    table.insert(self.lines, line)
  end
  return self
end

function Buffer:replace(from, to, text)
  assert(from <= to, ("bad range: %d..%d"):format(from, to))
  self.dirty = true
  return table.concat(self.lines, "\n", from, to):gsub("%s+$", text)
end

--[[ Block comment.
     Numbers: 0xFF, 1e-3, 42 ]]
return setmetatable(Buffer, { __call = function(_, s) return Buffer.new(s) end })
```

```haskell
{-# LANGUAGE OverloadedStrings #-}

module Fence.Outline (Heading(..), outline) where

import qualified Data.Text as T
import Data.Char (isAlphaNum, toLower)

data Heading = Heading
  { level :: !Int
  , text  :: !T.Text
  } deriving (Eq, Show)

-- | Slugify a heading for anchor links.
slugify :: T.Text -> T.Text
slugify = T.intercalate "-" . T.words . T.map keep . T.toLower
  where
    keep c | isAlphaNum c = c
           | otherwise    = ' '

outline :: T.Text -> [Heading]
outline = foldr step [] . T.lines
  where
    step line acc = case T.span (== '#') (T.stripStart line) of
      (hashes, rest)
        | not (T.null hashes) && T.length hashes <= 6 && not (T.null (T.strip rest)) ->
            Heading (T.length hashes) (T.strip rest) : acc
        | otherwise -> acc
```

```r
library(dplyr)
library(ggplot2)

# Retention by cohort, plotted as a heatmap.
retention <- opens %>%
  mutate(cohort = floor_date(opened_at, "month")) %>%
  group_by(cohort, month_index = interval(cohort, opened_at) %/% months(1)) %>%
  summarise(workspaces = n_distinct(workspace_id), .groups = "drop") %>%
  filter(month_index >= 0L, workspaces > 5)

fit <- lm(log(workspaces) ~ month_index + factor(cohort), data = retention)
print(summary(fit)$coefficients[, c(1, 4)])

ggplot(retention, aes(month_index, cohort, fill = workspaces)) +
  geom_tile(colour = "white", linewidth = 0.25) +
  scale_fill_viridis_c(trans = "log10", na.value = "grey90") +
  labs(title = "Workspace retention", x = "Months since first open", y = NULL) +
  theme_minimal(base_size = 11)
```

```perl
#!/usr/bin/perl
use strict;
use warnings;
use feature qw(say);

my %count;
my $re = qr/^\s*(#{1,6})\s+(.+?)\s*$/;

while (my $line = <STDIN>) {
    chomp $line;
    next unless $line =~ $re;
    my ($hashes, $title) = ($1, $2);
    $count{ length $hashes }++;
    (my $slug = lc $title) =~ s/[^a-z0-9]+/-/g;
    printf "%-6s %s\n", "h" . length($hashes), $slug;
}

say sprintf("total: %d headings across %d levels",
    eval { my $t = 0; $t += $_ for values %count; $t }, scalar keys %count);

__END__
Everything after __END__ is documentation, not code.
```

```powershell
#Requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$DistDir,
    [ValidateSet('dmg', 'exe', 'AppImage')][string]$Kind = 'dmg',
    [switch]$Upload
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-ArtifactSize {
    <#
        .SYNOPSIS
        Size of each build artifact, in MiB.
    #>
    [OutputType([pscustomobject])]
    param([string]$Path)

    Get-ChildItem -Path $Path -Filter "*.$Kind" | ForEach-Object {
        [pscustomobject]@{
            Name = $_.Name
            MiB  = [math]::Round($_.Length / 1MB, 2)
        }
    }
}

$artifacts = Get-ArtifactSize -Path $DistDir
$artifacts | Format-Table -AutoSize
if ($Upload) { gh release upload "v$env:VERSION" "$DistDir/*.$Kind" --clobber }
```

```zig
const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Frontmatter = struct {
    fields: std.StringHashMap([]const u8),
    body_offset: usize = 0,

    pub fn init(allocator: Allocator) Frontmatter {
        return .{ .fields = std.StringHashMap([]const u8).init(allocator) };
    }

    pub fn deinit(self: *Frontmatter) void {
        self.fields.deinit();
    }
};

pub const ParseError = error{ Unterminated, BadKey };

pub fn parse(allocator: Allocator, src: []const u8) !Frontmatter {
    var fm = Frontmatter.init(allocator);
    errdefer fm.deinit();
    if (!std.mem.startsWith(u8, src, "---\n")) return fm;

    var it = std.mem.splitScalar(u8, src[4..], '\n');
    var line_no: usize = 1;
    while (it.next()) |line| : (line_no += 1) {
        if (std.mem.eql(u8, line, "---")) {
            fm.body_offset = line_no + 1;
            return fm;
        }
        const sep = std.mem.indexOfScalar(u8, line, ':') orelse return ParseError.BadKey;
        try fm.fields.put(line[0..sep], std.mem.trim(u8, line[sep + 1 ..], " \t\""));
    }
    return ParseError.Unterminated;
}

test "parses a simple block" {
    var fm = try parse(std.testing.allocator, "---\ntitle: hi\n---\nbody");
    defer fm.deinit();
    try std.testing.expectEqual(@as(usize, 2), fm.body_offset);
}
```

```objective-c
#import <Foundation/Foundation.h>

static const NSUInteger kMaxCachedDocuments = 0x40;

NS_ASSUME_NONNULL_BEGIN

@interface FNDocumentCache : NSObject

@property (nonatomic, readonly) NSUInteger count;
@property (nonatomic, copy, nullable) void (^onEvict)(NSURL *url);

- (instancetype)initWithCapacity:(NSUInteger)capacity NS_DESIGNATED_INITIALIZER;
- (nullable NSString *)bodyForURL:(NSURL *)url error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END

@implementation FNDocumentCache {
    NSMutableDictionary<NSURL *, NSString *> *_bodies;
}

- (instancetype)initWithCapacity:(NSUInteger)capacity {
    if ((self = [super init])) {
        _bodies = [NSMutableDictionary dictionaryWithCapacity:MIN(capacity, kMaxCachedDocuments)];
    }
    return self;
}

- (nullable NSString *)bodyForURL:(NSURL *)url error:(NSError **)error {
    NSString *cached = _bodies[url];
    if (cached) return cached;

    NSString *body = [NSString stringWithContentsOfURL:url encoding:NSUTF8StringEncoding error:error];
    if (!body) {
        NSLog(@"read failed: %@ (%@)", url.lastPathComponent, (*error).localizedDescription);
        return nil;
    }
    _bodies[url] = body;  // TODO: evict LRU once over capacity
    return body;
}

@end
```

Finally, a fence tagged with a language that does not exist at all. It must fall
back to plain text exactly like the ones above, not error and not swallow the
rest of the document:

```blorptran
~~ BLORPTRAN 88 ~~
BEGIN PROGRAM outline
  LET counter := 0b1010 :: WORD
  FOR EACH line IN document DO
    IF line MATCHES /^#+ / THEN counter := counter + 1 ENDIF
  ENDFOR
  EMIT "headings: " & counter TO console
END PROGRAM
```
