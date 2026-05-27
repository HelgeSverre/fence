import { ChangeDetectionStrategy, Component, Input } from '@angular/core';

@Component({
  selector: 'feature-card',
  standalone: true,
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <article class="card">
      <div class="card__icon" aria-hidden="true">
        <ng-content select="[slot=icon]" />
      </div>
      <h3>{{ title }}</h3>
      <p>{{ description }}</p>
    </article>
  `,
  styles: [
    `
      .card {
        padding: var(--space-5);
        border: 1px solid var(--border);
        border-radius: var(--radius-lg);
        background: var(--bg-surface);
        transition: border-color 0.2s, transform 0.2s;
      }
      .card:hover {
        border-color: var(--accent);
        transform: translateY(-2px);
      }
      .card__icon {
        width: 36px;
        height: 36px;
        display: inline-flex;
        align-items: center;
        justify-content: center;
        border-radius: var(--radius-sm);
        background: oklch(from var(--accent) l c h / 0.12);
        color: var(--accent-text);
        margin-bottom: var(--space-3);
      }
      .card h3 {
        margin-bottom: var(--space-2);
      }
      .card p {
        color: var(--text-secondary);
        font-size: 0.95rem;
        margin: 0;
      }
    `,
  ],
})
export class FeatureCardComponent {
  @Input({ required: true }) title!: string;
  @Input({ required: true }) description!: string;
}
