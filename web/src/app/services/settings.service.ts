import { computed, effect, inject, Injectable, signal } from '@angular/core';
import { Meta, Title } from '@angular/platform-browser';
import { ConvertOptions, Script, Source } from '../engine/types';
import { I18nService, isLang, Lang } from './i18n.service';

const SCRIPTS: readonly Script[] = ['cyr', 'lat', 'new'];
const KEY = 'uzt.settings.v1';

interface Stored {
  from: Source;
  to: Script;
  ascii: boolean;
  skipUrls: boolean;
  dictionary: boolean;
  dropHardSignAfterO: boolean;
  tsFinal: boolean;
  theme: 'light' | 'dark' | null;
  lang: Lang;
}

/** ?lang=… in the address, then the remembered choice, then a Russian-first browser; otherwise Uzbek. */
function initialLang(saved: unknown): Lang {
  const q = new URLSearchParams(location.search).get('lang');
  if (isLang(q)) return q;
  if (isLang(saved)) return saved;
  return /^ru\b/i.test(navigator.languages?.[0] ?? navigator.language ?? '') ? 'ru' : 'uz';
}

function load(): Partial<Stored> {
  try {
    const raw = localStorage.getItem(KEY);
    const v = raw ? JSON.parse(raw) : {};
    return v && typeof v === 'object' ? v : {};
  } catch {
    return {};
  }
}

/** Direction, options and UI preferences; remembered in this browser only. */
@Injectable({ providedIn: 'root' })
export class SettingsService {
  private readonly i18n = inject(I18nService);
  private readonly title = inject(Title);
  private readonly meta = inject(Meta);
  private readonly saved = load();

  readonly from = signal<Source>(this.saved.from === 'auto' || SCRIPTS.includes(this.saved.from as Script) ? this.saved.from! : 'auto');
  readonly to = signal<Script>(SCRIPTS.includes(this.saved.to as Script) ? this.saved.to! : 'new');
  readonly ascii = signal(this.saved.ascii === true);
  readonly skipUrls = signal(this.saved.skipUrls !== false);
  readonly dictionary = signal(this.saved.dictionary !== false);
  readonly dropHardSignAfterO = signal(this.saved.dropHardSignAfterO !== false);
  readonly tsFinal = signal(this.saved.tsFinal !== false);
  readonly theme = signal<'light' | 'dark' | null>(this.saved.theme === 'light' || this.saved.theme === 'dark' ? this.saved.theme : null);

  readonly options = computed<ConvertOptions>(() => ({
    okina: this.ascii() ? "'" : 'ʻ',
    tutuq: this.ascii() ? "'" : 'ʼ',
    skipUrls: this.skipUrls(),
    dictionary: this.dictionary(),
    dropHardSignAfterO: this.dropHardSignAfterO(),
    tsFinal: this.tsFinal()
  }));

  /** Changes whenever anything that affects a conversion result changes. */
  readonly key = computed(() => JSON.stringify([this.from(), this.to(), this.options()]));

  constructor() {
    this.i18n.lang.set(initialLang(this.saved.lang));
    effect(() => {
      const s: Stored = {
        from: this.from(), to: this.to(), ascii: this.ascii(), skipUrls: this.skipUrls(), dictionary: this.dictionary(),
        dropHardSignAfterO: this.dropHardSignAfterO(), tsFinal: this.tsFinal(), theme: this.theme(), lang: this.i18n.lang()
      };
      try { localStorage.setItem(KEY, JSON.stringify(s)); } catch { /* private mode: settings are not remembered */ }
    });
    effect(() => {
      const t = this.theme();
      if (t) document.documentElement.setAttribute('data-theme', t);
      else document.documentElement.removeAttribute('data-theme');
    });
    effect(() => {
      document.documentElement.setAttribute('lang', this.i18n.info().htmlLang);
      this.title.setTitle(this.i18n.t('doc.title'));
      this.meta.updateTag({ name: 'description', content: this.i18n.t('doc.description') });
    });
  }

  /** ?text=…&from=…&to=… deep links; returns the text to put in the editor. */
  applyDeepLink(search: string): string | null {
    const q = new URLSearchParams(search);
    const from = q.get('from'), to = q.get('to');
    if (from === 'auto' || SCRIPTS.includes(from as Script)) this.from.set(from as Source);
    if (SCRIPTS.includes(to as Script)) this.to.set(to as Script);
    const text = q.get('text');
    return text === null ? null : text.slice(0, 100000);
  }

  swap(detected: Script | null): void {
    const cur = this.from() === 'auto' ? detected ?? 'lat' : (this.from() as Script);
    this.from.set(this.to());
    this.to.set(cur);
  }
}
