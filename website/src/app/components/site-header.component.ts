import { ChangeDetectionStrategy, Component, inject } from '@angular/core';
import { RouterLink, RouterLinkActive } from '@angular/router';
import { ThemeService } from '../shared/theme.service';

@Component({
  selector: 'site-header',
  standalone: true,
  imports: [RouterLink, RouterLinkActive],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <header class="site-header">
      <div class="container site-header__inner">
        <a routerLink="/" class="brand" aria-label="Fence home">
          <svg viewBox="0 0 32 32" width="24" height="24" aria-hidden="true">
            <rect width="32" height="32" rx="6" fill="var(--bg-overlay)" />
            <path
              d="M9 8h14M9 16h10M9 24h14"
              stroke="var(--accent)"
              stroke-width="2.5"
              stroke-linecap="round"
            />
          </svg>
          <span>Fence</span>
        </a>

        <nav class="site-nav" aria-label="Primary">
          <a routerLink="/features" routerLinkActive="is-active">Features</a>
          <a routerLink="/download" routerLinkActive="is-active">Download</a>
          <a routerLink="/docs" routerLinkActive="is-active">Docs</a>
          <a routerLink="/about" routerLinkActive="is-active">About</a>
          <a routerLink="/changelog" routerLinkActive="is-active">Changelog</a>
        </nav>

        <div class="site-header__actions">
          <button
            type="button"
            class="theme-toggle"
            (click)="theme.toggle()"
            [attr.aria-label]="
              theme.current() === 'catppuccin-mocha' ? 'Switch to light theme' : 'Switch to dark theme'
            "
            title="Toggle theme"
          >
            @if (theme.current() === 'catppuccin-mocha') {
              <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M4.93 4.93l1.41 1.41M17.66 17.66l1.41 1.41M2 12h2M20 12h2M6.34 17.66l-1.41 1.41M19.07 4.93l-1.41 1.41"/></svg>
            } @else {
              <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z"/></svg>
            }
          </button>
          <a
            href="https://github.com/HelgeSverre/fence"
            class="github-link"
            aria-label="View source on GitHub"
            target="_blank"
            rel="noopener"
          >
            <svg width="20" height="20" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
              <path
                d="M12 .5a12 12 0 0 0-3.79 23.4c.6.11.82-.26.82-.58v-2c-3.34.73-4.04-1.61-4.04-1.61-.55-1.4-1.34-1.77-1.34-1.77-1.09-.74.08-.73.08-.73 1.21.09 1.85 1.24 1.85 1.24 1.08 1.84 2.83 1.31 3.52 1 .11-.78.42-1.31.76-1.62-2.66-.3-5.47-1.33-5.47-5.93 0-1.31.47-2.38 1.24-3.22-.13-.3-.54-1.52.12-3.18 0 0 1.01-.32 3.31 1.23a11.5 11.5 0 0 1 6.02 0c2.3-1.55 3.31-1.23 3.31-1.23.66 1.66.25 2.88.12 3.18.77.84 1.24 1.91 1.24 3.22 0 4.61-2.81 5.62-5.49 5.92.43.37.81 1.1.81 2.22v3.29c0 .32.22.7.83.58A12 12 0 0 0 12 .5z"
              />
            </svg>
          </a>
        </div>
      </div>
    </header>
  `,
  styles: [
    `
      .site-header {
        position: sticky;
        top: 0;
        z-index: 10;
        background: oklch(from var(--bg-base) l c h / 0.85);
        backdrop-filter: saturate(180%) blur(12px);
        -webkit-backdrop-filter: saturate(180%) blur(12px);
        border-bottom: 1px solid var(--border);
      }

      .site-header__inner {
        display: flex;
        align-items: center;
        gap: var(--space-5);
        height: 60px;
      }

      .brand {
        display: inline-flex;
        align-items: center;
        gap: var(--space-2);
        font-weight: 700;
        font-size: 1.05rem;
        color: var(--text-primary);
        letter-spacing: -0.01em;
      }

      .brand:hover {
        color: var(--text-primary);
      }

      .site-nav {
        display: flex;
        gap: var(--space-2);
        flex: 1;
        margin-left: var(--space-5);
      }

      .site-nav a {
        color: var(--text-secondary);
        padding: 6px 10px;
        border-radius: var(--radius-sm);
        font-size: 0.92rem;
      }

      .site-nav a:hover {
        background: var(--state-hover);
        color: var(--text-primary);
      }

      .site-nav a.is-active {
        color: var(--accent-text);
      }

      .site-header__actions {
        display: flex;
        align-items: center;
        gap: var(--space-1);
      }

      .theme-toggle,
      .github-link {
        display: inline-flex;
        align-items: center;
        justify-content: center;
        width: 36px;
        height: 36px;
        border-radius: var(--radius-sm);
        border: none;
        background: none;
        cursor: pointer;
        color: var(--text-secondary);
      }

      .theme-toggle:hover,
      .github-link:hover {
        background: var(--state-hover);
        color: var(--text-primary);
      }

      @media (max-width: 640px) {
        .site-nav {
          display: none;
        }
      }
    `,
  ],
})
export class SiteHeaderComponent {
  protected theme = inject(ThemeService);
}
