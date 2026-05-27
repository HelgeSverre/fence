import { ChangeDetectionStrategy, Component, Input, computed } from '@angular/core';

type OS = 'mac' | 'win' | 'linux';

const OS_LABEL: Record<OS, string> = {
  mac: 'macOS',
  win: 'Windows',
  linux: 'Linux',
};

@Component({
  selector: 'download-card',
  standalone: true,
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <a class="download-card" [href]="href" target="_blank" rel="noopener">
      <div class="download-card__icon" aria-hidden="true">
        @switch (os) {
          @case ('mac') {
            <svg viewBox="0 0 24 24" width="32" height="32" fill="currentColor"><path d="M16.37 1.43c.07 1.4-.49 2.78-1.36 3.78-.86 1-2.28 1.76-3.65 1.65-.13-1.36.55-2.78 1.4-3.66.93-.99 2.5-1.74 3.61-1.77zM20.5 17.8c-.55 1.27-.81 1.83-1.51 2.95-1 1.55-2.4 3.49-4.13 3.5-1.54.02-1.94-.99-4.04-.98-2.09.01-2.53 1-4.07.98-1.74-.01-3.06-1.76-4.06-3.31-2.8-4.34-3.1-9.43-1.37-12.14C2.55 7.16 4.59 6.13 6.49 6.13c1.95 0 3.17 1.07 4.79 1.07 1.57 0 2.52-1.07 4.77-1.07 1.7 0 3.5.92 4.79 2.52-4.21 2.31-3.52 8.33-.34 9.15z"/></svg>
          }
          @case ('win') {
            <svg viewBox="0 0 24 24" width="32" height="32" fill="currentColor"><path d="M3 5.5L11 4v8H3V5.5zM3 12.5h8V20l-8-1.3v-6.2zM12 3.85L22 2v10H12V3.85zM12 12.85h10V22l-10-1.4v-7.75z"/></svg>
          }
          @case ('linux') {
            <svg viewBox="0 0 24 24" width="32" height="32" fill="currentColor"><path d="M12.5 2C9.91 2 8 4 8 7.5c0 2.42.69 3.4 1.41 4.84.41.83.43 1.41.43 1.99 0 .8-.62 1.42-1.34 2.36C7.65 17.81 7 18.86 7 20c0 1.86 2.91 2 5.5 2s5.5-.14 5.5-2c0-1.14-.65-2.19-1.5-3.31-.72-.94-1.34-1.56-1.34-2.36 0-.58.02-1.16.43-1.99C16.31 10.9 17 9.92 17 7.5 17 4 15.09 2 12.5 2zm-1.78 4.05a.97.97 0 011.06.94c.02.54-.42 1-1 1.01a.97.97 0 01-1.06-.94c-.02-.54.42-1 1-1.01zm2.56 0a.97.97 0 011 1.01c-.02.55-.5.97-1.06.94a.97.97 0 01-1-1c.02-.55.5-.97 1.06-.95z"/></svg>
          }
        }
      </div>
      <div class="download-card__copy">
        <h3>{{ label() }}</h3>
        <p>{{ subtitle }}</p>
      </div>
      <span class="download-card__arrow" aria-hidden="true">→</span>
    </a>
  `,
  styles: [
    `
      .download-card {
        display: flex;
        align-items: center;
        gap: var(--space-4);
        padding: var(--space-5);
        border: 1px solid var(--border);
        border-radius: var(--radius-lg);
        background: var(--bg-surface);
        color: var(--text-primary);
        transition: border-color 0.15s, transform 0.15s, background 0.15s;
      }
      .download-card:hover {
        border-color: var(--accent);
        background: var(--state-hover);
        color: var(--text-primary);
      }
      .download-card__icon {
        width: 56px;
        height: 56px;
        display: flex;
        align-items: center;
        justify-content: center;
        border-radius: var(--radius-md);
        background: var(--bg-overlay);
        color: var(--accent-text);
      }
      .download-card__copy {
        flex: 1;
      }
      .download-card__copy h3 {
        margin-bottom: 2px;
      }
      .download-card__copy p {
        margin: 0;
        font-size: 0.9rem;
        color: var(--text-muted);
      }
      .download-card__arrow {
        font-size: 1.25rem;
        color: var(--text-muted);
      }
    `,
  ],
})
export class DownloadCardComponent {
  @Input({ required: true }) os!: OS;
  @Input({ required: true }) href!: string;
  @Input() subtitle = '';

  protected readonly label = computed(() => OS_LABEL[this.os]);
}
