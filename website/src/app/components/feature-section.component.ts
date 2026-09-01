import { ChangeDetectionStrategy, Component, Input } from '@angular/core';

@Component({
  selector: 'feature-section',
  standalone: true,
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <section
      class="feature-section"
      [class.feature-section--reverse]="imagePosition === 'right'"
      [class.feature-section--no-media]="!imageSrc"
    >
      <div class="feature-section__copy">
        @if (eyebrow) {
          <span class="eyebrow">{{ eyebrow }}</span>
        }
        <h2>{{ title }}</h2>
        <ng-content />
      </div>
      @if (imageSrc) {
        <div class="feature-section__media">
          <img [src]="imageSrc" [alt]="imageAlt || title" loading="lazy" width="2188" height="1323" />
        </div>
      }
    </section>
  `,
  styles: [
    `
      .feature-section {
        display: grid;
        grid-template-columns: 1fr 1fr;
        gap: var(--space-7);
        align-items: center;
        padding: var(--space-7) 0;
      }
      .feature-section--reverse .feature-section__copy {
        order: 2;
      }
      .feature-section--no-media {
        grid-template-columns: 1fr;
        max-width: var(--max-prose);
      }
      .feature-section__media {
        border: 1px solid var(--border);
        border-radius: var(--radius-lg);
        overflow: hidden;
        background: var(--bg-surface);
      }
      .feature-section__copy ::ng-deep p {
        font-size: 1.05rem;
      }
      @media (max-width: 800px) {
        .feature-section {
          grid-template-columns: 1fr;
        }
        .feature-section--reverse .feature-section__copy {
          order: 0;
        }
      }
    `,
  ],
})
export class FeatureSectionComponent {
  @Input({ required: true }) title!: string;
  @Input() eyebrow?: string;
  @Input() imageSrc?: string;
  @Input() imageAlt?: string;
  @Input() imagePosition: 'left' | 'right' = 'left';
}
