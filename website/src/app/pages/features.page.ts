import { ChangeDetectionStrategy, Component } from '@angular/core';
import { FeatureSectionComponent } from '../components/feature-section.component';

@Component({
  selector: 'page-features',
  standalone: true,
  imports: [FeatureSectionComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div class="container">
      <header class="page-header">
        <span class="eyebrow">Features</span>
        <h1>Everything Fence does, in detail.</h1>
        <p class="lead">
          The whole point of Fence is to stay out of your way. Here's what's in the box.
        </p>
      </header>

      <feature-section
        eyebrow="Editor"
        title="Split-view editing with real-time preview"
        imageSrc="/screenshots/hero.png"
        imagePosition="right"
      >
        <p>
          Type Markdown on the left, see it rendered on the right. Parsing is debounced so
          the preview stays responsive even on long documents — stale parses are dropped
          via a generation counter.
        </p>
        <p>
          Code fences are highlighted using a custom lexer, with a textarea-plus-overlay
          technique so the editor stays a real, native textarea.
        </p>
      </feature-section>

      <feature-section
        eyebrow="File tree"
        title="Open a folder, work in it"
        imageSrc="/screenshots/hero.png"
        imagePosition="left"
      >
        <p>
          Pick a directory and Fence will treat it as your workspace. The tree updates as
          you create, rename, or remove files from outside the app — chokidar watches the
          directory and pushes events to the renderer through Elm's port system.
        </p>
        <p>
          Files with no unsaved changes are auto-reloaded when modified elsewhere.
        </p>
      </feature-section>

      <feature-section
        eyebrow="Themes"
        title="A library of themes, all in oklch"
        imageSrc="/screenshots/hero.png"
        imagePosition="right"
      >
        <p>
          Pick from Catppuccin Mocha, Catppuccin Latte, Fleet Dark, GitHub Dark, VS Code
          Dark+, Dracula, One Dark, Tokyo Night, and Nord. Colors are defined in oklch so
          contrast and saturation behave consistently across themes.
        </p>
        <p>The site you're on right now uses the same palette tokens as the editor.</p>
      </feature-section>

      <feature-section
        eyebrow="Frontmatter"
        title="YAML frontmatter, parsed and previewed"
        imageSrc="/screenshots/hero.png"
        imagePosition="left"
      >
        <p>
          Documents with frontmatter render with the metadata visible above the document
          body. The parser is hand-rolled in elm/parser combinators — small, predictable,
          and doesn't choke on the YAML subset that Markdown frontmatter actually uses.
        </p>
      </feature-section>

      <feature-section
        eyebrow="Layout"
        title="Resizable panes with persisted state"
        imagePosition="right"
      >
        <p>
          Drag the dividers to size the sidebar, editor, and preview. Sidebar clamps to
          8–40% of window width; editor/preview to 15–85%. The split you choose is saved
          to Electron's state file and restored on next launch.
        </p>
      </feature-section>
    </div>
  `,
  styles: [
    `
      .page-header {
        max-width: 720px;
        margin: var(--space-8) auto var(--space-7);
        text-align: center;
      }
      .page-header .lead {
        margin: 0 auto;
      }
    `,
  ],
})
export default class FeaturesPage {}
