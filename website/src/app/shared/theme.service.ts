import { Injectable, signal } from '@angular/core';

export type Theme = 'catppuccin-mocha' | 'catppuccin-latte';

const STORAGE_KEY = 'fence-site-theme';

@Injectable({ providedIn: 'root' })
export class ThemeService {
  readonly current = signal<Theme>('catppuccin-mocha');

  init(): void {
    if (typeof window === 'undefined') return;
    const stored = window.localStorage.getItem(STORAGE_KEY) as Theme | null;
    if (stored === 'catppuccin-latte' || stored === 'catppuccin-mocha') {
      this.set(stored);
    } else {
      this.apply(this.current());
    }
  }

  toggle(): void {
    this.set(this.current() === 'catppuccin-mocha' ? 'catppuccin-latte' : 'catppuccin-mocha');
  }

  set(theme: Theme): void {
    this.current.set(theme);
    this.apply(theme);
    if (typeof window !== 'undefined') {
      window.localStorage.setItem(STORAGE_KEY, theme);
    }
  }

  private apply(theme: Theme): void {
    if (typeof document !== 'undefined') {
      document.documentElement.setAttribute('data-theme', theme);
    }
  }
}
