import { Component, computed, effect, ElementRef, inject, signal, untracked, viewChild } from '@angular/core';
import { EXPORT_MIME, ExportFormat } from '../engine/export';
import { Script } from '../engine/types';
import { EngineService } from '../services/engine.service';
import { saveBlob } from '../services/file-jobs.service';
import { I18nService } from '../services/i18n.service';
import { SettingsService } from '../services/settings.service';
import { ToastService } from '../services/toast.service';

function isSpace(c: number): boolean {
  return c <= 0x20 || c === 0xa0 || c === 0x1680 || (c >= 0x2000 && c <= 0x200a) || c === 0x2028 || c === 0x2029 ||
    c === 0x202f || c === 0x205f || c === 0x3000 || c === 0xfeff;
}

function countWords(text: string): number {
  let n = 0, inWord = false;
  for (let i = 0; i < text.length; i++) {
    const space = isSpace(text.charCodeAt(i));
    if (!space && !inWord) n++;
    inWord = !space;
  }
  return n;
}

/** Two panes: text in, converted text out, live. */
@Component({
  selector: 'app-text-converter',
  templateUrl: './text-converter.html',
  styleUrl: './text-converter.css',
  host: { '(document:keydown.control.enter)': 'copy()', '(document:keydown.meta.enter)': 'copy()' }
})
export class TextConverter {
  private readonly engine = inject(EngineService);
  private readonly settings = inject(SettingsService);
  private readonly toast = inject(ToastService);
  protected readonly i18n = inject(I18nService);

  readonly source = signal('');
  readonly result = signal('');
  /** what auto-detection found (null when the source script was chosen by hand) */
  readonly detected = signal<Script | null>(null);
  protected readonly effFrom = signal<Script | null>(null);
  protected readonly effTo = signal<Script>('new');
  protected readonly formats: ExportFormat[] = ['txt', 'docx', 'odt', 'html'];
  private readonly dst = viewChild<ElementRef<HTMLTextAreaElement>>('dst');
  private readonly src = viewChild<ElementRef<HTMLTextAreaElement>>('src');
  private seq = 0;
  private timer: ReturnType<typeof setTimeout> | undefined;

  protected readonly sourceStats = computed(() => this.stats(this.source()));
  protected readonly resultStats = computed(() => this.stats(this.result()));
  protected readonly detectedLabel = computed(() => {
    const d = this.detected();
    return d && this.source() ? this.i18n.t('text.detected', { script: this.i18n.t('name.' + d) }) : '';
  });
  protected readonly directionLabel = computed(() => {
    const f = this.effFrom();
    return f ? this.i18n.t('text.direction', { from: this.i18n.t('name.' + f), to: this.i18n.t('name.' + this.effTo()) }) : '';
  });

  constructor() {
    const linked = this.settings.applyDeepLink(location.search);
    if (linked !== null) this.source.set(linked);
    this.engine.warmUp();
    effect(() => {
      const text = this.source();
      this.settings.key();
      untracked(() => this.schedule(text));
    });
  }

  private stats(text: string): string {
    return this.i18n.t('text.stats', { chars: text.length.toLocaleString(), words: countWords(text).toLocaleString() });
  }

  private schedule(text: string): void {
    clearTimeout(this.timer);
    // short texts convert on every keystroke; long ones once typing pauses
    if (text.length < 50000) void this.run(text);
    else this.timer = setTimeout(() => void this.run(text), 250);
  }

  private async run(text: string): Promise<void> {
    const id = ++this.seq;
    if (!text) {
      this.result.set('');
      this.detected.set(null);
      this.effFrom.set(null);
      return;
    }
    const chosen = this.settings.from();
    let to = this.settings.to();
    let from: Script;
    if (chosen === 'auto') {
      from = await this.engine.detect(text);
      // already in the target script: convert to the other alphabet instead
      if (from === to) to = from === 'cyr' ? 'new' : 'cyr';
    } else from = chosen;
    const r = await this.engine.convertText(text, from, to, this.settings.options());
    if (id !== this.seq) return; // a newer edit is on its way
    this.result.set(r.text);
    this.detected.set(chosen === 'auto' ? from : null);
    this.effFrom.set(from);
    this.effTo.set(to);
  }

  protected onInput(ev: Event): void {
    this.source.set((ev.target as HTMLTextAreaElement).value);
  }

  protected clear(): void {
    this.source.set('');
    this.src()?.nativeElement.focus();
  }

  protected async paste(): Promise<void> {
    try {
      this.source.set(await navigator.clipboard.readText());
    } catch {
      this.src()?.nativeElement.focus();
      this.toast.show(this.i18n.t('text.pasteHint'));
    }
  }

  async copy(): Promise<void> {
    const text = this.result();
    if (!text) return;
    try {
      await navigator.clipboard.writeText(text);
    } catch {
      const el = this.dst()?.nativeElement;
      el?.select();
      document.execCommand('copy');
    }
    this.toast.show(this.i18n.t('text.copied'));
  }

  protected async export(format: ExportFormat, menu: HTMLDetailsElement): Promise<void> {
    menu.open = false;
    const text = this.result();
    if (!text) return;
    const bytes = await this.engine.exportText(text, format, this.effTo());
    saveBlob(new Blob([bytes as BlobPart], { type: EXPORT_MIME[format] }), `natija-${this.effTo()}.${format}`);
  }
}
