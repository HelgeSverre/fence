import { ChangeDetectionStrategy, Component, Input } from '@angular/core';

@Component({
  selector: 'code-block',
  standalone: true,
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <pre><code [attr.data-lang]="language"><ng-content /></code></pre>
  `,
  styles: [
    `
      :host {
        display: block;
      }
      pre {
        position: relative;
      }
      pre code {
        font-family: var(--font-mono);
        font-size: 0.88rem;
        line-height: 1.6;
        color: var(--text-primary);
      }
      pre code[data-lang]::before {
        content: attr(data-lang);
        position: absolute;
        top: var(--space-2);
        right: var(--space-3);
        font-size: 0.7rem;
        text-transform: uppercase;
        letter-spacing: 0.1em;
        color: var(--text-muted);
      }
    `,
  ],
})
export class CodeBlockComponent {
  @Input() language?: string;
}
