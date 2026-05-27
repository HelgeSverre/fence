import { ChangeDetectionStrategy, Component } from '@angular/core';
import { RouterLink } from '@angular/router';
import { HeroComponent } from '../components/hero.component';
import { FeatureCardComponent } from '../components/feature-card.component';

@Component({
  selector: 'page-home',
  standalone: true,
  imports: [RouterLink, HeroComponent, FeatureCardComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <fence-hero
      eyebrow="Markdown editor"
      headline="Write Markdown without leaving the page."
      subhead="Fence is a focused split-view Markdown editor. Edit on the left, preview on the right, file tree on the side — all the friction stripped out."
      ctaHref="/download"
      ctaLabel="Download for free"
      secondaryHref="/features"
      secondaryLabel="See features"
    >
      <img src="/screenshots/hero.png" alt="Fence editor with split view and live preview" />
    </fence-hero>

    <section class="section">
      <div class="container">
        <header class="section-header">
          <span class="eyebrow">Features</span>
          <h2>Built for people who write a lot of Markdown.</h2>
          <p class="lead">
            No accounts, no telemetry, no surprise subscription. A small, focused desktop app.
          </p>
        </header>

        <div class="features-grid">
          <feature-card
            title="Split-view editing"
            description="Editor and preview live side by side, with a resizable divider you can drag to the layout you prefer."
          >
            <svg slot="icon" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="3" width="18" height="18" rx="2"/><line x1="12" y1="3" x2="12" y2="21"/></svg>
          </feature-card>

          <feature-card
            title="File explorer"
            description="Open a folder once. Fence watches it for changes and keeps your tree in sync. Keyboard-navigable."
          >
            <svg slot="icon" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M3 7a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v9a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"/></svg>
          </feature-card>

          <feature-card
            title="YAML frontmatter"
            description="Frontmatter is parsed and rendered as a metadata block — handy when working on blog posts or docs."
          >
            <svg slot="icon" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M4 6h16M4 12h10M4 18h16"/></svg>
          </feature-card>

          <feature-card
            title="Syntax highlighting"
            description="Code fences are highlighted in both the editor overlay and the preview, with theme-aware colors."
          >
            <svg slot="icon" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="16 18 22 12 16 6"/><polyline points="8 6 2 12 8 18"/></svg>
          </feature-card>

          <feature-card
            title="A library of themes"
            description="Catppuccin, Fleet, VS Code, GitHub, Dracula, Tokyo Night, Nord, One Dark — all using oklch for perceptual consistency."
          >
            <svg slot="icon" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="9"/><path d="M12 3v18M3 12h18"/></svg>
          </feature-card>

          <feature-card
            title="Resizable panes"
            description="Drag dividers to set up the split that works for the document you're writing. Your layout is remembered."
          >
            <svg slot="icon" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M9 4v16M15 4v16M3 12h18"/></svg>
          </feature-card>
        </div>
      </div>
    </section>

    <section class="section section--cta">
      <div class="container cta-card">
        <div>
          <h2>Free, open source, and unbothered.</h2>
          <p class="lead">
            Fence ships as a native app for macOS, Windows, and Linux. MIT licensed.
          </p>
        </div>
        <div class="cta-card__actions">
          <a routerLink="/download" class="btn btn--primary">Download Fence</a>
          <a
            href="https://github.com/HelgeSverre/fence"
            class="btn btn--ghost"
            target="_blank"
            rel="noopener"
            >View on GitHub</a
          >
        </div>
      </div>
    </section>
  `,
  styles: [
    `
      .section-header {
        max-width: 640px;
        margin: 0 auto var(--space-6);
        text-align: center;
      }
      .section-header .lead {
        margin: 0 auto;
      }
      .features-grid {
        display: grid;
        grid-template-columns: repeat(3, 1fr);
        gap: var(--space-4);
      }
      @media (max-width: 880px) {
        .features-grid {
          grid-template-columns: 1fr 1fr;
        }
      }
      @media (max-width: 560px) {
        .features-grid {
          grid-template-columns: 1fr;
        }
      }
      .section--cta {
        padding-top: var(--space-7);
      }
      .cta-card {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: var(--space-5);
        padding: var(--space-7);
        border: 1px solid var(--border);
        border-radius: var(--radius-xl);
        background: var(--bg-surface);
      }
      .cta-card h2 {
        margin-bottom: var(--space-2);
      }
      .cta-card__actions {
        display: flex;
        gap: var(--space-3);
        flex-shrink: 0;
      }
      @media (max-width: 720px) {
        .cta-card {
          flex-direction: column;
          align-items: flex-start;
        }
      }
    `,
  ],
})
export default class HomePage {}
