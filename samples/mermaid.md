# Mermaid rendering sample

A manual-QA document for Fence's Mermaid support. Each section below holds one
realistic diagram of a given type, so a reader can scroll the preview pane and
check every renderer in a single pass. Fence uses Mermaid 12 with the `dagre`
layout, the `classic` look and `securityLevel: "strict"`, so labels are plain
text — no embedded HTML.

Diagrams that Mermaid itself still marks as beta live in their own section at
the end: a failure there is expected noise, not a regression.

## Contents

- [Flowchart (graph TD)](#flowchart-graph-td)
- [Flowchart (flowchart LR)](#flowchart-flowchart-lr)
- [Sequence diagram](#sequence-diagram)
- [Class diagram](#class-diagram)
- [State diagram](#state-diagram)
- [Entity relationship diagram](#entity-relationship-diagram)
- [Gantt chart](#gantt-chart)
- [Pie chart](#pie-chart)
- [User journey](#user-journey)
- [Git graph](#git-graph)
- [Mindmap](#mindmap)
- [Timeline](#timeline)
- [Quadrant chart](#quadrant-chart)
- [Requirement diagram](#requirement-diagram)
- [C4 context diagram](#c4-context-diagram)
- [Experimental / may not render](#experimental--may-not-render)
- [Error handling](#error-handling)

## Flowchart (graph TD)

The document open path, from a click in the file tree to painted preview. It
exercises subgraphs, rhombus/stadium/cylinder/circle node shapes, edge labels,
class assignment and dotted edges.

```mermaid
graph TD
    Click([User clicks a file in the tree]) --> Read[/"main.js: readFile IPC"/]
    Read --> Cache{Already in the<br>chunk cache?}
    Cache -- yes --> Reuse[Reuse parsed chunks]
    Cache -- no --> Split

    subgraph Renderer [Elm renderer process]
        Split[Markdown.splitChunks] --> Front[Frontmatter.extract]
        Front --> Parse[Markdown.begin / step]
        Parse --> Budget{Character<br>budget spent?}
        Budget -- no --> Parse
        Budget -- yes --> Yield[Yield to the next Frame]
        Yield --> Parse
    end

    subgraph Main [Electron main process]
        Disk[(Workspace on disk)]
        Watch[chokidar watcher]
        Disk --> Watch
    end

    Read --> Disk
    Reuse --> Paint
    Parse --> Paint((First screen painted))
    Watch -. change event .-> Reload[Auto-reload if clean]
    Reload -. re-enters .-> Split

    class Paint done
    class Budget,Cache decision
    classDef done fill:#2e7d32,stroke:#1b5e20,color:#ffffff
    classDef decision fill:#f9a825,stroke:#f57f17,color:#1a1a1a
    style Disk fill:#37474f,stroke:#263238,color:#ffffff
```

## Flowchart (flowchart LR)

The same app seen as a release pipeline, laid out left to right with the newer
`flowchart` keyword, multi-hop edges and a link style override.

```mermaid
flowchart LR
    Commit[/git push to main/] --> Lint

    subgraph CI [GitHub Actions]
        direction TB
        Lint[elm-format --validate] --> Unit[elm-test + node tests]
        Unit --> Build[vite build]
        Build --> E2E[Playwright e2e]
    end

    E2E --> Gate{All green?}
    Gate -- no --> Fail>Annotate the PR and stop]
    Gate -- yes --> Pack

    subgraph Release [electron-builder]
        direction TB
        Pack[Package app] --> Mac[macOS dmg]
        Pack --> Win[Windows nsis]
        Pack --> Linux[Linux AppImage]
    end

    Mac & Win & Linux --> Sign{{Sign and notarize}}
    Sign --> Publish[(GitHub release)]
    Publish -. updates .-> Cask[Homebrew cask]

    class Fail bad
    class Publish good
    classDef bad fill:#c62828,stroke:#8e0000,color:#ffffff
    classDef good fill:#1565c0,stroke:#0d47a1,color:#ffffff
    linkStyle 11 stroke:#8e24aa,stroke-width:2px
```

## Sequence diagram

Saving a dirty buffer, including the watcher echo that Fence has to ignore.
Covers participants, activations, a loop, `alt`/`opt` blocks and notes.

```mermaid
sequenceDiagram
    autonumber
    actor User
    participant Elm as Elm renderer
    participant Pre as preload bridge
    participant Main as Electron main
    participant FS as fs-ops + chokidar

    User->>Elm: Cmd+S
    activate Elm
    Note right of Elm: Buffer is dirty, cursor position is kept

    Elm->>Pre: writeFile(path, contents)
    activate Pre
    Pre->>Main: IPC invoke "write-file"
    activate Main

    alt path inside the workspace
        Main->>FS: atomic write to a temp file
        activate FS
        loop retry up to 3 times
            FS-->>Main: EBUSY, back off
        end
        FS-->>Main: rename succeeded
        deactivate FS
        Main-->>Pre: { ok: true, mtime }
    else path escaped the workspace
        Main-->>Pre: { ok: false, reason: "outside workspace" }
        Note over Main,Pre: Validated in validate.js<br>before any disk access
    end

    deactivate Main
    Pre-->>Elm: result
    deactivate Pre

    opt write succeeded
        Elm->>Elm: clear dirty flag, push undo checkpoint
    end

    FS->>Main: watcher "change" for the same file
    Main->>Elm: fileChanged
    Note over Elm: mtime matches the write we just made,<br>so the reload is suppressed

    Elm-->>User: title bar drops the dot
    deactivate Elm
```

## Class diagram

The renderer side of the editor as types. Covers inheritance, composition,
aggregation, generics, visibility markers, abstract members and cardinalities.

```mermaid
classDiagram
    direction LR

    class Document {
        +String path
        +TextBuffer buffer
        -Bool dirty
        +save() Result~Unit, IoError~
        +reloadFrom(String) Document
    }

    class TextBuffer {
        -Array~String~ lines
        +lineCount() Int
        +insertAt(Position, String) TextBuffer
        +deleteRange(Range) TextBuffer
        +slice(Range) List~String~
    }

    class UndoStack~T~ {
        -List~T~ past
        -List~T~ future
        +push(T) UndoStack~T~
        +undo() Maybe~T~
        +redo() Maybe~T~
    }

    class Renderer {
        <<interface>>
        +render(Block)* Html
    }

    class MarkdownRenderer {
        +render(Block) Html
        #highlight(String, String) Html
    }

    class PreviewPane {
        +Float scrollTop
        +syncTo(Int) Cmd
    }

    class Position {
        <<value>>
        +Int row
        +Int col
    }

    Document "1" *-- "1" TextBuffer : owns
    Document "1" *-- "1" UndoStack~TextBuffer~ : history
    Document "1" o-- "0..*" Position : cursors
    Renderer <|.. MarkdownRenderer : implements
    PreviewPane ..> MarkdownRenderer : uses
    PreviewPane --> Document : observes

    note for UndoStack~T~ "Coalesces edits made<br>within 300 ms"
```

## State diagram

The lifecycle of an open document, with composite states, a fork/join for the
two parses that run side by side, and a choice node for the close prompt.

```mermaid
stateDiagram-v2
    direction TB
    [*] --> Empty

    Empty --> Loading : open file
    Loading --> Ready : contents decoded
    Loading --> LoadFailed : read error
    LoadFailed --> Empty : dismiss

    state Ready {
        [*] --> Clean
        Clean --> Dirty : keystroke
        Dirty --> Saving : Cmd+S
        Saving --> Clean : write ok
        Saving --> Dirty : write failed

        state Parsing {
            [*] --> fork_parse
            state fork_parse <<fork>>
            fork_parse --> Highlighting
            fork_parse --> Chunking
            Highlighting --> join_parse
            Chunking --> join_parse
            state join_parse <<join>>
            join_parse --> Painted
            Painted --> [*]
        }

        Dirty --> Parsing : debounce elapsed
        Parsing --> Dirty : newer generation wins
    }

    Ready --> Closing : Cmd+W
    state decide <<choice>>
    Closing --> decide
    decide --> Empty : buffer is clean
    decide --> Prompt : buffer is dirty
    Prompt --> Saving2 : Save
    Prompt --> Empty : Discard
    Prompt --> Ready : Cancel
    Saving2 --> Empty : write ok

    Ready --> Reloading : watcher change, buffer clean
    Reloading --> Ready

    note right of Prompt
        electron/main.js checks the live
        document state before the window
        is allowed to close.
    end note
```

## Entity relationship diagram

The workspace index a file-search feature would persist, with primary, foreign
and unique keys, comments and explicit cardinalities.

```mermaid
erDiagram
    WORKSPACE ||--o{ DOCUMENT : contains
    WORKSPACE ||--o{ WATCH : "is watched by"
    DOCUMENT ||--|{ HEADING : "outlines into"
    DOCUMENT ||--o{ LINK : "points out via"
    DOCUMENT }o--o{ TAG : "tagged with"
    DOCUMENT ||--o| FRONTMATTER : "may declare"
    LINK }o--|| DOCUMENT : "resolves to"

    WORKSPACE {
        string id PK
        string root_path UK "absolute, no trailing slash"
        datetime opened_at
        int document_count
    }

    DOCUMENT {
        string id PK
        string workspace_id FK
        string rel_path UK "unique within a workspace"
        int byte_size
        datetime mtime "from fs.stat, drives reindex"
        boolean indexed
    }

    FRONTMATTER {
        string document_id PK, FK
        string title
        string author
        date published
        json extra "anything the YAML parser kept"
    }

    HEADING {
        string id PK
        string document_id FK
        int level "1..6"
        string text
        int line_number
        string slug "anchor target"
    }

    LINK {
        string id PK
        string source_document_id FK
        string target_document_id FK "null until resolved"
        string raw_href
        boolean is_external
    }

    TAG {
        string id PK
        string name UK
    }

    WATCH {
        string id PK
        string workspace_id FK
        string glob
        boolean recursive
    }
```

## Gantt chart

A plausible schedule for shipping a plugin system, with sections, explicit
dependencies, milestones, an active task and a done task.

```mermaid
gantt
    title Plugin system, v0.6
    dateFormat YYYY-MM-DD
    axisFormat %b %d
    excludes weekends

    section Design
    Sandboxing spike              :done,    spike, 2026-01-05, 5d
    Write the plugin RFC          :done,    rfc, after spike, 6d
    RFC signed off                :milestone, m1, after rfc, 0d

    section Core
    Plugin host process           :active,  host, after m1, 10d
    Capability-scoped IPC         :         ipc, after host, 7d
    Manifest parser and validator :         manifest, after m1, 5d
    Load and unload at runtime    :         runtime, after ipc manifest, 6d

    section Surface
    Preview renderer hooks        :         hooks, after runtime, 5d
    Command palette contributions :         palette, after runtime, 4d
    Settings pane for plugins     :         settings, after palette, 4d

    section Release
    Docs and starter template     :         docs, after hooks settings, 5d
    Beta cut                      :milestone, m2, after docs, 0d
    Soak with three real plugins  :crit,    soak, after m2, 10d
    v0.6 ships                    :milestone, m3, after soak, 0d
```

## Pie chart

Where startup time goes on a cold open of a 700 KB reference document.

```mermaid
pie showData
    title Cold-open time budget (ms)
    "Electron boot" : 210
    "Elm init and flags" : 45
    "File read and decode" : 120
    "Editor metrics measurement" : 30
    "First chunk parse" : 150
    "Syntax highlighting" : 95
    "Preview paint" : 60
```

## User journey

A first session with the app, scored from 1 (painful) to 5 (delightful).

```mermaid
journey
    title First hour with Fence
    section Install
      Download the dmg: 4: Newcomer
      Drag to Applications: 5: Newcomer
      Clear the unsigned-binary warning: 2: Newcomer
    section First open
      Pick a notes folder: 4: Newcomer
      See the tree populate: 5: Newcomer
      Open a large file: 3: Newcomer, Power user
    section Writing
      Type with live preview: 5: Newcomer, Power user
      Find and replace: 4: Power user
      Split-pane resize: 4: Newcomer
    section Settling in
      Switch to a light theme: 5: Newcomer
      Change the editor font: 4: Power user
      Reopen and find the session restored: 5: Newcomer, Power user
```

## Git graph

How a release branch is cut, patched and merged back.

```mermaid
gitGraph
    commit id: "v0.4.2"
    commit id: "virtual editor rows"
    branch feature/mermaid
    checkout feature/mermaid
    commit id: "lazy-load mermaid"
    commit id: "error box + details"
    checkout main
    commit id: "resolve preview images"
    merge feature/mermaid id: "merge mermaid"
    branch release/0.5
    checkout release/0.5
    commit id: "bump to 0.5.0" tag: "v0.5.0"
    checkout main
    commit id: "settings pane refactor"
    checkout release/0.5
    commit id: "fix: close prompt on dirty buffer"
    commit id: "0.5.1" tag: "v0.5.1"
    checkout main
    merge release/0.5 id: "back-merge hotfix"
    commit id: "preferences record"
```

## Mindmap

The feature surface of the editor, as a map rather than a list. Uses the
shape variants (cloud, hexagon, rounded, bang) and an icon-free plain root.

```mermaid
mindmap
  root((Fence))
    Editing
      Virtualized rows
        Only visible lines in the DOM
        Hidden textarea under the caret
      Undo
        Coalesced by time
      (Find and replace)
    Preview
      ::icon(fa fa-eye)
      Progressive parsing
        Chunked at top-level headings
        Per-chunk cache
      Mermaid diagrams
      Syntax highlighting
    Workspace
      File tree
        Keyboard navigation
        Background markdown probe
      chokidar watching
      Quick open palette
    Appearance
      {{Five themes}}
      Font pickers
        Mono for the editor
        Sans for the preview
      Preview max width
    Platform
      Electron main
        State persistence
        CLI launcher
      Export
        Standalone HTML
        PDF
```

## Timeline

The project's own release history, grouped by period.

```mermaid
timeline
    title Fence release history
    section 2025
        v0.1 : First split view
             : File tree with chokidar
        v0.2 : YAML frontmatter
             : Five oklch themes
        v0.3 : Virtualized editor
             : 700 KB file opens under a second
    section 2026 H1
        v0.4 : Find and replace
             : Quick-open palette
        v0.4.1 : Document-relative preview images
        v0.4.2 : CLI launcher
               : UI fixes
        v0.5 : Session restoration
             : Safer close-on-dirty handling
    section 2026 H2
        v0.6 : Mermaid diagrams
             : Preferences record
             : Sans font bundling
```

## Quadrant chart

Where the backlog sits on effort against user-visible payoff.

```mermaid
quadrantChart
    title Backlog triage for the next two releases
    x-axis "Low effort" --> "High effort"
    y-axis "Low payoff" --> "High payoff"
    quadrant-1 "Big bets"
    quadrant-2 "Do next"
    quadrant-3 "Fill-in work"
    quadrant-4 "Money pits"
    "Mermaid diagrams": [0.42, 0.78]
    "Word count in status bar": [0.12, 0.36]
    "Wrap long lines": [0.55, 0.70]
    "Plugin system": [0.90, 0.82]
    "Vim keybindings": [0.72, 0.45]
    "PDF export tuning": [0.30, 0.52]
    "Per-folder settings": [0.48, 0.22]
    "Multi-window support": [0.80, 0.30]
    "Table formatting command": [0.25, 0.66]
```

## Requirement diagram

Traceability for the editor's performance and safety requirements.

```mermaid
requirementDiagram

requirement open_speed {
id: 1
text: A 700 KB document must paint its first screen within 200 ms.
risk: high
verifymethod: test
}

performanceRequirement scroll_budget {
id: 1.1
text: Scrolling must hold a 16 ms frame budget at 10k lines.
risk: medium
verifymethod: test
}

functionalRequirement no_data_loss {
id: 2
text: Closing a window must never silently discard unsaved edits.
risk: high
verifymethod: demonstration
}

interfaceRequirement sandbox {
id: 3
text: The renderer must reach the file system only through preload IPC.
risk: high
verifymethod: inspection
}

designConstraint dagre_only {
id: 4
text: Diagram rendering must avoid the 1.4 MB ELK layout chunk.
risk: low
verifymethod: inspection
}

element virtual_editor {
type: "module"
docRef: "src/VirtualEditor.elm"
}

element close_guard {
type: "module"
docRef: "electron/main.js"
}

element preload_bridge {
type: "module"
docRef: "electron/preload.js"
}

element mermaid_init {
type: "module"
docRef: "js/mermaid-init.js"
}

element open_gate {
type: "test case"
docRef: "e2e/virtual-editor.test.js"
}
open_speed - contains -> scroll_budget
virtual_editor - satisfies -> open_speed
virtual_editor - satisfies -> scroll_budget
close_guard - satisfies -> no_data_loss
preload_bridge - satisfies -> sandbox
mermaid_init - satisfies -> dagre_only
open_gate - verifies -> open_speed
scroll_budget - derives -> dagre_only
```

## C4 context diagram

The system context for the editor: who uses it and what it touches. C4 ships
its own renderer, so it is unaffected by the dagre layout setting.

```mermaid
C4Context
    title System context for the Fence markdown editor

    Person(author, "Author", "Writes notes and documentation in markdown")
    Person_Ext(reviewer, "Reviewer", "Receives exported HTML or PDF")

    Enterprise_Boundary(desktop, "Author's machine") {
        System(fence, "Fence", "Electron + Elm markdown editor with live preview")
        SystemDb(workspace, "Workspace folder", "Markdown files and images on local disk")
        SystemDb(state, "state.json", "Layout, recent workspaces and appearance preferences")

        System_Boundary(tooling, "Local tooling") {
            System_Ext(git, "Git", "Version control for the workspace")
            System_Ext(editorCli, "fence CLI", "Opens a path from the terminal")
        }
    }

    System_Ext(updates, "Release feed", "GitHub releases and the Homebrew cask")

    Rel(author, fence, "Edits documents in")
    BiRel(fence, workspace, "Reads and writes", "fs + chokidar")
    Rel(fence, state, "Persists layout and preferences to")
    Rel(editorCli, fence, "Launches with a path")
    Rel(author, git, "Commits the workspace with")
    Rel(fence, updates, "Checks for new versions", "HTTPS")
    Rel(fence, reviewer, "Exports HTML or PDF to")

    UpdateLayoutConfig($c4ShapeInRow="2", $c4BoundaryInRow="1")
```

## Experimental / may not render

Mermaid still labels the diagram types below as beta: their keywords carry a
`-beta` suffix and their syntax has changed between minor releases. Treat a
failure here as expected rather than as a Fence regression, and only chase it
if one of them used to render and has stopped.

### XY chart (`xychart-beta`)

Parse time against document size, as a bar and line pair.

```mermaid
xychart-beta
    title "Time to first paint by document size"
    x-axis ["10 KB", "50 KB", "100 KB", "250 KB", "500 KB", "700 KB", "1 MB"]
    y-axis "Milliseconds" 0 --> 600
    bar [18, 46, 82, 155, 260, 340, 470]
    line [22, 55, 95, 170, 290, 380, 520]
```

### Sankey (`sankey-beta`)

Where the bytes in a packaged build end up. Values are in kilobytes.

```mermaid
sankey-beta

Packaged app,Electron runtime,142000
Packaged app,App bundle,2400
App bundle,Elm bundle,520
App bundle,Mermaid,560
App bundle,Highlighting library,180
App bundle,Fonts,890
App bundle,Styles and HTML,250
Elm bundle,Editor and buffer,210
Elm bundle,Markdown and preview,180
Elm bundle,File tree and palette,130
Fonts,Mono faces,410
Fonts,Sans faces,480
```

### Block diagram (`block-beta`)

The process boundary laid out as blocks rather than as a graph.

```mermaid
block-beta
    columns 3

    renderer["Renderer process"]:3

    block:elm:3
        editor["VirtualEditor"]
        markdown["Markdown / Preview"]
        tree["FileTree"]
    end

    space
    bridge<["preload contextBridge"]>(down)
    space

    block:main:3
        ipc["IPC handlers"]
        fsops["fs-ops + chokidar"]
        session["session.json"]
    end

    disk[("Workspace on disk")]:3

    fsops --> disk
    session --> disk
    editor --> markdown

    style bridge fill:#1565c0,stroke:#0d47a1,color:#ffffff
    style disk fill:#37474f,stroke:#263238,color:#ffffff
```

## Error handling

The block below is deliberately malformed: it declares a sequence diagram and
then uses flowchart edges with an unbalanced bracket. Fence should replace it
with a "Couldn't render diagram" box containing the parser message and a
collapsed `<details>` holding the source — and the rest of this page, including
every diagram above, must keep rendering normally.

```mermaid
sequenceDiagram
    participant A
    A --> B[[[ this is not sequence syntax
    ::: neither is this
    alt unclosed
```

If instead you see a blank gap, a raw SVG error graphic, or a page that stops
rendering at this point, that is a bug in `js/mermaid-init.js`.
