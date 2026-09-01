import { ChangeDetectionStrategy, Component } from '@angular/core';
import { RouteMeta } from '@analogjs/router';

export const routeMeta: RouteMeta = {
  title: 'Download — Fence',
  meta: [
    { name: 'description', content: 'Download Fence for macOS (Intel and Apple Silicon), Windows, and Linux, or install it with Homebrew.' },
    { property: 'og:title', content: 'Download — Fence' },
    { property: 'og:description', content: 'Download Fence for macOS (Intel and Apple Silicon), Windows, and Linux, or install it with Homebrew.' },
  ],
};

@Component({
  selector: 'page-download',
  standalone: true,
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <section class="download-hero">
      <div class="container">
        <span class="eyebrow">Download · v0.1.1</span>
        <h1>Get Fence on your machine in under a minute.</h1>
        <p class="lead">
          Free and MIT licensed. No accounts, no telemetry, no nagging upgrades.
        </p>
        <div class="download-hero__meta">
          <span><strong>3</strong> platforms</span>
          <span class="dot">·</span>
          <span><strong>Intel</strong> + Apple Silicon</span>
          <span class="dot">·</span>
          <span>Signed &amp; notarized on macOS</span>
        </div>
      </div>
    </section>

    <section class="download-cards">
      <div class="container">
        <div class="download-grid">
          <a
            class="dl-card dl-card--mac"
            href="https://github.com/HelgeSverre/fence/releases/latest"
            target="_blank"
            rel="noopener"
          >
            <div class="dl-card__bg" aria-hidden="true"></div>
            <div class="dl-card__icon">
              <svg viewBox="0 0 24 24" width="40" height="40" fill="currentColor"><path d="M16.37 1.43c.07 1.4-.49 2.78-1.36 3.78-.86 1-2.28 1.76-3.65 1.65-.13-1.36.55-2.78 1.4-3.66.93-.99 2.5-1.74 3.61-1.77zM20.5 17.8c-.55 1.27-.81 1.83-1.51 2.95-1 1.55-2.4 3.49-4.13 3.5-1.54.02-1.94-.99-4.04-.98-2.09.01-2.53 1-4.07.98-1.74-.01-3.06-1.76-4.06-3.31-2.8-4.34-3.1-9.43-1.37-12.14C2.55 7.16 4.59 6.13 6.49 6.13c1.95 0 3.17 1.07 4.79 1.07 1.57 0 2.52-1.07 4.77-1.07 1.7 0 3.5.92 4.79 2.52-4.21 2.31-3.52 8.33-.34 9.15z"/></svg>
            </div>
            <div class="dl-card__os">macOS</div>
            <div class="dl-card__arch">Separate Intel and Apple Silicon builds</div>
            <div class="dl-card__formats">
              <span>.dmg</span>
              <span>Homebrew</span>
            </div>
            <div class="dl-card__cta">
              Download
              <span aria-hidden="true">↓</span>
            </div>
          </a>

          <a
            class="dl-card dl-card--win"
            href="https://github.com/HelgeSverre/fence/releases/latest"
            target="_blank"
            rel="noopener"
          >
            <div class="dl-card__bg" aria-hidden="true"></div>
            <div class="dl-card__icon">
              <svg viewBox="0 0 24 24" width="40" height="40" fill="currentColor"><path d="M3 5.5L11 4v8H3V5.5zM3 12.5h8V20l-8-1.3v-6.2zM12 3.85L22 2v10H12V3.85zM12 12.85h10V22l-10-1.4v-7.75z"/></svg>
            </div>
            <div class="dl-card__os">Windows</div>
            <div class="dl-card__arch">x64 · Windows 10 and later</div>
            <div class="dl-card__formats">
              <span>.exe installer</span>
            </div>
            <div class="dl-card__cta">
              Download
              <span aria-hidden="true">↓</span>
            </div>
          </a>

          <a
            class="dl-card dl-card--linux"
            href="https://github.com/HelgeSverre/fence/releases/latest"
            target="_blank"
            rel="noopener"
          >
            <div class="dl-card__bg" aria-hidden="true"></div>
            <div class="dl-card__icon">
              <svg viewBox="0 0 24 24" width="40" height="40" fill="currentColor"><path d="M12.5 2C9.91 2 8 4 8 7.5c0 2.42.69 3.4 1.41 4.84.41.83.43 1.41.43 1.99 0 .8-.62 1.42-1.34 2.36C7.65 17.81 7 18.86 7 20c0 1.86 2.91 2 5.5 2s5.5-.14 5.5-2c0-1.14-.65-2.19-1.5-3.31-.72-.94-1.34-1.56-1.34-2.36 0-.58.02-1.16.43-1.99C16.31 10.9 17 9.92 17 7.5 17 4 15.09 2 12.5 2z"/></svg>
            </div>
            <div class="dl-card__os">Linux</div>
            <div class="dl-card__arch">x64 · Ubuntu, Fedora, Arch, etc.</div>
            <div class="dl-card__formats">
              <span>AppImage</span>
              <span>.deb</span>
            </div>
            <div class="dl-card__cta">
              Download
              <span aria-hidden="true">↓</span>
            </div>
          </a>
        </div>

        <p class="download-cards__note">
          All builds are published to
          <a
            href="https://github.com/HelgeSverre/fence/releases"
            target="_blank"
            rel="noopener"
            >GitHub Releases</a
          >. Looking for an older version? They're all there.
        </p>
      </div>
    </section>

    <section class="install-section">
      <div class="container">
        <header class="install-section__head">
          <span class="eyebrow">Install</span>
          <h2>Two steps, tops.</h2>
        </header>
      </div>
      <div class="container install-grid">
        <article class="install-card">
          <div class="install-card__head">
            <span class="install-card__chip">macOS</span>
            <h3>Drag &amp; drop</h3>
          </div>
          <p>
            Open the <code>.dmg</code> and drag Fence to Applications. Pick the
            <code>arm64</code> file on Apple Silicon.
          </p>
          <pre><code># or with Homebrew
brew install --cask helgesverre/tap/fence</code></pre>
        </article>

        <article class="install-card">
          <div class="install-card__head">
            <span class="install-card__chip">Windows</span>
            <h3>Per-user install</h3>
          </div>
          <p>
            Run <code>Fence-Setup-*.exe</code>. It installs per-user, so no admin prompt.
          </p>
        </article>

        <article class="install-card">
          <div class="install-card__head">
            <span class="install-card__chip">Linux</span>
            <h3>AppImage or .deb</h3>
          </div>
          <p>AppImage is portable — just <code>chmod +x</code> and run.</p>
          <pre><code># Ubuntu / Debian
sudo dpkg -i fence_*_amd64.deb</code></pre>
        </article>
      </div>
    </section>

    <section class="source-cta">
      <div class="container">
        <div class="source-cta__inner">
          <div>
            <h2>Or build from source.</h2>
            <p class="lead">
              Clone the repo and run <code>bun install &amp;&amp; bun run dev</code>. Elm
              + Vite + Electron — nothing exotic.
            </p>
          </div>
          <div class="source-cta__actions">
            <a
              href="https://github.com/HelgeSverre/fence"
              class="btn btn--ghost"
              target="_blank"
              rel="noopener"
            >
              View on GitHub →
            </a>
          </div>
        </div>
      </div>
    </section>
  `,
  styles: [
    `
      .download-hero {
        padding: var(--space-9) 0 var(--space-7);
        background:
          radial-gradient(ellipse 60% 50% at 20% 0%, oklch(from var(--accent) l c h / 0.18), transparent 60%),
          radial-gradient(ellipse 60% 50% at 80% 0%, oklch(from var(--syntax-heading) l c h / 0.14), transparent 60%);
        text-align: center;
      }
      .download-hero h1 {
        max-width: 720px;
        margin: 0 auto var(--space-4);
      }
      .download-hero .lead {
        margin: 0 auto;
      }
      .download-hero__meta {
        display: inline-flex;
        flex-wrap: wrap;
        align-items: center;
        gap: var(--space-3);
        margin-top: var(--space-5);
        padding: 10px 18px;
        border: 1px solid var(--border);
        border-radius: 999px;
        background: oklch(from var(--bg-surface) l c h / 0.6);
        font-family: var(--font-mono);
        font-size: 0.82rem;
        color: var(--text-muted);
      }
      .download-hero__meta strong {
        color: var(--text-primary);
        font-weight: 600;
      }
      .download-hero__meta .dot {
        color: var(--text-muted);
        opacity: 0.5;
      }

      .download-cards {
        padding: var(--space-7) 0 var(--space-6);
      }
      .download-grid {
        display: grid;
        grid-template-columns: repeat(3, 1fr);
        gap: var(--space-4);
        max-width: 1080px;
        margin: 0 auto;
      }
      @media (max-width: 880px) {
        .download-grid {
          grid-template-columns: 1fr;
        }
      }
      .dl-card {
        position: relative;
        display: flex;
        flex-direction: column;
        gap: var(--space-2);
        padding: var(--space-6);
        border: 1px solid var(--border);
        border-radius: var(--radius-xl);
        background: var(--bg-surface);
        color: var(--text-primary);
        overflow: hidden;
        transition: transform 0.2s, border-color 0.2s, box-shadow 0.2s;
        text-decoration: none;
        isolation: isolate;
      }
      .dl-card:hover {
        transform: translateY(-4px);
        border-color: var(--accent);
        box-shadow: 0 24px 60px -20px oklch(from var(--accent) l c h / 0.4);
        color: var(--text-primary);
      }
      .dl-card__bg {
        position: absolute;
        inset: -50%;
        background: radial-gradient(
          circle at 50% 0%,
          oklch(from var(--accent) l c h / 0.18),
          transparent 60%
        );
        opacity: 0.5;
        z-index: -1;
        transition: opacity 0.2s;
      }
      .dl-card:hover .dl-card__bg {
        opacity: 1;
      }
      .dl-card--win .dl-card__bg {
        background: radial-gradient(
          circle at 50% 0%,
          oklch(from var(--syntax-list) l c h / 0.18),
          transparent 60%
        );
      }
      .dl-card--linux .dl-card__bg {
        background: radial-gradient(
          circle at 50% 0%,
          oklch(from var(--syntax-heading) l c h / 0.18),
          transparent 60%
        );
      }
      .dl-card__icon {
        width: 64px;
        height: 64px;
        display: flex;
        align-items: center;
        justify-content: center;
        border-radius: var(--radius-md);
        background: var(--bg-overlay);
        color: var(--accent-text);
        margin-bottom: var(--space-2);
      }
      .dl-card--win .dl-card__icon {
        color: var(--syntax-list);
      }
      .dl-card--linux .dl-card__icon {
        color: var(--syntax-heading);
      }
      .dl-card__os {
        font-size: 1.4rem;
        font-weight: 700;
        letter-spacing: -0.01em;
        color: var(--text-primary);
      }
      .dl-card__arch {
        font-size: 0.88rem;
        color: var(--text-muted);
      }
      .dl-card__formats {
        display: flex;
        gap: var(--space-1);
        flex-wrap: wrap;
        margin-top: var(--space-2);
      }
      .dl-card__formats span {
        display: inline-block;
        padding: 3px 9px;
        border-radius: var(--radius-sm);
        background: var(--bg-overlay);
        color: var(--text-secondary);
        font-family: var(--font-mono);
        font-size: 0.78rem;
      }
      .dl-card__cta {
        display: inline-flex;
        align-items: center;
        gap: var(--space-2);
        margin-top: var(--space-4);
        padding-top: var(--space-4);
        border-top: 1px solid var(--border);
        font-weight: 600;
        font-size: 0.92rem;
        color: var(--accent-text);
      }
      .download-cards__note {
        text-align: center;
        margin-top: var(--space-6);
        color: var(--text-muted);
        font-size: 0.9rem;
      }

      .install-section {
        padding: var(--space-7) 0;
      }
      .install-section__head {
        text-align: center;
        margin-bottom: var(--space-6);
      }
      .install-grid {
        display: grid;
        grid-template-columns: repeat(3, 1fr);
        gap: var(--space-4);
        max-width: 1080px;
        margin: 0 auto;
      }
      @media (max-width: 880px) {
        .install-grid {
          grid-template-columns: 1fr;
        }
      }
      .install-card {
        padding: var(--space-5);
        border: 1px solid var(--border);
        border-radius: var(--radius-lg);
        background: var(--bg-surface);
      }
      .install-card__head {
        display: flex;
        align-items: center;
        gap: var(--space-3);
        margin-bottom: var(--space-3);
      }
      .install-card__chip {
        display: inline-block;
        padding: 3px 9px;
        border-radius: var(--radius-sm);
        background: oklch(from var(--accent) l c h / 0.15);
        color: var(--accent-text);
        font-family: var(--font-mono);
        font-size: 0.72rem;
        letter-spacing: 0.06em;
        text-transform: uppercase;
      }
      .install-card h3 {
        margin: 0;
      }
      .install-card pre {
        margin: var(--space-2) 0 0;
        font-size: 0.82rem;
      }

      .source-cta {
        padding: var(--space-7) 0 var(--space-5);
      }
      .source-cta__inner {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: var(--space-5);
        padding: var(--space-6) var(--space-7);
        border: 1px solid var(--border);
        border-radius: var(--radius-xl);
        background: var(--bg-surface);
      }
      .source-cta h2 {
        margin-bottom: var(--space-2);
      }
      .source-cta .lead {
        margin: 0;
      }
      .source-cta__actions {
        flex-shrink: 0;
      }
      @media (max-width: 720px) {
        .source-cta__inner {
          flex-direction: column;
          align-items: flex-start;
        }
      }
    `,
  ],
})
export default class DownloadPage {}
