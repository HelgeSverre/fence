import { ChangeDetectionStrategy, Component } from '@angular/core';
import { DownloadCardComponent } from '../components/download-card.component';

@Component({
  selector: 'page-download',
  standalone: true,
  imports: [DownloadCardComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div class="container">
      <header class="page-header">
        <span class="eyebrow">Download</span>
        <h1>Get Fence for your machine.</h1>
        <p class="lead">
          Builds are published on GitHub Releases. Pick your platform below and grab the
          latest version.
        </p>
      </header>

      <div class="download-grid">
        <download-card
          os="mac"
          subtitle="DMG and ZIP (Intel + Apple Silicon)"
          href="https://github.com/HelgeSverre/fence/releases/latest"
        />
        <download-card
          os="win"
          subtitle="NSIS installer (.exe)"
          href="https://github.com/HelgeSverre/fence/releases/latest"
        />
        <download-card
          os="linux"
          subtitle="AppImage and .deb"
          href="https://github.com/HelgeSverre/fence/releases/latest"
        />
      </div>

      <section class="install">
        <h2>Install notes</h2>
        <h3>macOS</h3>
        <p>
          Open the <code>.dmg</code> and drag <strong>Fence</strong> to your Applications
          folder. The builds are signed and notarized — Gatekeeper will accept them on
          first launch.
        </p>

        <h3>Windows</h3>
        <p>
          Run the <code>.exe</code> installer. It's a per-user install, so no
          administrator prompt.
        </p>

        <h3>Linux</h3>
        <p>
          The AppImage is portable — <code>chmod +x</code> and run. The
          <code>.deb</code> can be installed with <code>sudo dpkg -i fence_*.deb</code> on
          Debian/Ubuntu.
        </p>

        <h3>Building from source</h3>
        <p>
          Clone the repo and run <code>npm install</code> followed by
          <code>npm run dev</code>. See the
          <a href="https://github.com/HelgeSverre/fence#readme" target="_blank" rel="noopener"
            >README</a
          >
          for details.
        </p>
      </section>
    </div>
  `,
  styles: [
    `
      .page-header {
        max-width: 640px;
        margin: var(--space-8) auto var(--space-7);
        text-align: center;
      }
      .page-header .lead {
        margin: 0 auto;
      }
      .download-grid {
        display: grid;
        grid-template-columns: repeat(3, 1fr);
        gap: var(--space-4);
        max-width: 960px;
        margin: 0 auto;
      }
      @media (max-width: 800px) {
        .download-grid {
          grid-template-columns: 1fr;
        }
      }
      .install {
        max-width: var(--max-prose);
        margin: var(--space-9) auto 0;
      }
      .install h3 {
        margin-top: var(--space-5);
      }
    `,
  ],
})
export default class DownloadPage {}
