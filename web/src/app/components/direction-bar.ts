import { Component, inject, input } from '@angular/core';
import { Script, Source } from '../engine/types';
import { I18nService } from '../services/i18n.service';
import { SettingsService } from '../services/settings.service';

/** Source and target script, the swap button and the conversion options. */
@Component({
  selector: 'app-direction-bar',
  templateUrl: './direction-bar.html',
  styleUrl: './direction-bar.css'
})
export class DirectionBar {
  protected readonly s = inject(SettingsService);
  protected readonly i18n = inject(I18nService);
  /** the script auto-detection found, for the swap button */
  readonly detected = input<Script | null>(null);

  protected readonly sources: Source[] = ['auto', 'cyr', 'lat', 'new'];
  protected readonly targets: Script[] = ['cyr', 'lat', 'new'];

  protected keyFrom(ev: KeyboardEvent): void {
    const v = this.step(this.sources, this.s.from(), ev);
    if (v) { this.s.from.set(v); this.focus(ev, v); }
  }

  protected keyTo(ev: KeyboardEvent): void {
    const v = this.step(this.targets, this.s.to(), ev);
    if (v) { this.s.to.set(v); this.focus(ev, v); }
  }

  /** Arrow keys move the selection within a radio group. */
  private step<T>(group: T[], current: T, ev: KeyboardEvent): T | null {
    const d = ev.key === 'ArrowRight' || ev.key === 'ArrowDown' ? 1 : ev.key === 'ArrowLeft' || ev.key === 'ArrowUp' ? -1 : 0;
    if (!d) return null;
    ev.preventDefault();
    return group[(group.indexOf(current) + d + group.length) % group.length];
  }

  private focus(ev: KeyboardEvent, v: string): void {
    (ev.currentTarget as HTMLElement).querySelector<HTMLElement>(`[data-v="${v}"]`)?.focus();
  }
}
