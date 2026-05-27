import { ChangeDetectionStrategy, Component } from '@angular/core';
import { RouterLink } from '@angular/router';

@Component({
  selector: 'site-footer',
  standalone: true,
  imports: [RouterLink],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <footer class="site-footer">
      <div class="container site-footer__inner">
        <div>
          <p class="site-footer__brand">Fence</p>
          <p class="site-footer__tagline">A split-view Markdown editor, made for focused writing.</p>
        </div>
        <div class="site-footer__cols">
          <div>
            <h4>Product</h4>
            <a routerLink="/features">Features</a>
            <a routerLink="/download">Download</a>
            <a routerLink="/changelog">Changelog</a>
          </div>
          <div>
            <h4>Docs</h4>
            <a routerLink="/docs">Getting started</a>
            <a routerLink="/about">About</a>
          </div>
          <div>
            <h4>Project</h4>
            <a href="https://github.com/HelgeSverre/fence" target="_blank" rel="noopener">GitHub</a>
            <a
              href="https://github.com/HelgeSverre/fence/issues"
              target="_blank"
              rel="noopener"
              >Issues</a
            >
            <a
              href="https://github.com/HelgeSverre/fence/releases"
              target="_blank"
              rel="noopener"
              >Releases</a
            >
          </div>
        </div>
      </div>
      <div class="container site-footer__legal">
        <span>MIT licensed</span>
        <span>Built with Elm + Electron</span>
      </div>
    </footer>
  `,
  styles: [
    `
      .site-footer {
        border-top: 1px solid var(--border);
        background: var(--bg-surface);
        padding: var(--space-7) 0 var(--space-5);
        margin-top: var(--space-9);
      }
      .site-footer__inner {
        display: grid;
        grid-template-columns: 1fr 2fr;
        gap: var(--space-7);
      }
      .site-footer__brand {
        font-weight: 700;
        font-size: 1.1rem;
        color: var(--text-primary);
        margin-bottom: var(--space-1);
      }
      .site-footer__tagline {
        color: var(--text-muted);
        font-size: 0.92rem;
      }
      .site-footer__cols {
        display: grid;
        grid-template-columns: repeat(3, 1fr);
        gap: var(--space-5);
      }
      .site-footer__cols h4 {
        font-size: 0.78rem;
        letter-spacing: 0.1em;
        text-transform: uppercase;
        color: var(--text-muted);
        margin-bottom: var(--space-3);
      }
      .site-footer__cols a {
        display: block;
        color: var(--text-secondary);
        font-size: 0.92rem;
        padding: 3px 0;
      }
      .site-footer__cols a:hover {
        color: var(--accent-text);
      }
      .site-footer__legal {
        display: flex;
        justify-content: space-between;
        margin-top: var(--space-6);
        padding-top: var(--space-4);
        border-top: 1px solid var(--border);
        font-size: 0.82rem;
        color: var(--text-muted);
      }
      @media (max-width: 720px) {
        .site-footer__inner {
          grid-template-columns: 1fr;
        }
        .site-footer__cols {
          grid-template-columns: repeat(3, 1fr);
        }
      }
    `,
  ],
})
export class SiteFooterComponent {}
