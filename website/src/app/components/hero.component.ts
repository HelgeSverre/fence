import { ChangeDetectionStrategy, Component, Input } from '@angular/core';

@Component({
  selector: 'fence-hero',
  standalone: true,
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <section class="hero">
      <div class="container hero__inner">
        <div class="hero__copy">
          @if (eyebrow) {
            <span class="eyebrow">{{ eyebrow }}</span>
          }
          <h1>{{ headline }}</h1>
          <p class="lead">{{ subhead }}</p>
          <div class="hero__ctas">
            <a [href]="ctaHref" class="btn btn--primary">{{ ctaLabel }}</a>
            @if (secondaryHref) {
              <a [href]="secondaryHref" class="btn btn--ghost">{{ secondaryLabel }}</a>
            }
          </div>
        </div>
        <div class="hero__media">
          <ng-content />
        </div>
      </div>
    </section>
  `,
  styles: [
    `
      .hero {
        padding: var(--space-9) 0 var(--space-7);
        background: radial-gradient(
          ellipse 80% 60% at 50% -10%,
          oklch(from var(--accent) l c h / 0.12),
          transparent 70%
        );
      }
      .hero__inner {
        display: grid;
        grid-template-columns: 1fr 1.1fr;
        gap: var(--space-7);
        align-items: center;
      }
      .hero__ctas {
        display: flex;
        gap: var(--space-3);
        margin-top: var(--space-5);
        flex-wrap: wrap;
      }
      .hero__media {
        border: 1px solid var(--border);
        border-radius: var(--radius-xl);
        overflow: hidden;
        background: var(--bg-surface);
        box-shadow: 0 24px 60px -20px oklch(from var(--accent) l c h / 0.25);
      }
      .hero__media ::ng-deep img {
        display: block;
        width: 100%;
      }
      @media (max-width: 880px) {
        .hero__inner {
          grid-template-columns: 1fr;
        }
      }
    `,
  ],
})
export class HeroComponent {
  @Input({ required: true }) headline!: string;
  @Input({ required: true }) subhead!: string;
  @Input({ required: true }) ctaHref!: string;
  @Input({ required: true }) ctaLabel!: string;
  @Input() eyebrow?: string;
  @Input() secondaryHref?: string;
  @Input() secondaryLabel?: string;
}
