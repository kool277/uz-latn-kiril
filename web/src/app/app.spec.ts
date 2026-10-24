import { signal } from '@angular/core';
import { TestBed } from '@angular/core/testing';
import { App } from './app';
import { EngineService } from './services/engine.service';
import { LANGS, MESSAGES } from './services/i18n.service';
import { SettingsService } from './services/settings.service';

/** Workers and WebAssembly live in the e2e tests; here the engine is a stub that upper-cases. */
class FakeEngine {
  readonly kind = signal<'wasm' | null>('wasm');
  readonly threads = 4;
  readonly running = signal(0);
  warmUp(): void {}
  async detect(text: string) { return /[а-яёўқғҳ]/i.test(text) ? 'cyr' : 'lat'; }
  async convertText(text: string, from: string) { return { text: text.toUpperCase(), from }; }
}

describe('App', () => {
  beforeEach(async () => {
    localStorage.clear();
    history.replaceState(null, '', '/');
    await TestBed.configureTestingModule({
      imports: [App],
      providers: [{ provide: EngineService, useClass: FakeEngine }]
    }).compileComponents();
  });

  it('renders the title, the engine badge and both tabs', async () => {
    const fixture = TestBed.createComponent(App);
    await fixture.whenStable();
    const el = fixture.nativeElement as HTMLElement;
    expect(el.querySelector('h1')?.textContent).toContain('Yangi lotin');
    expect(el.querySelector('[data-testid=engine]')?.textContent).toContain('WebAssembly · 4');
    expect([...el.querySelectorAll('[role=tab]')].map(t => t.textContent?.trim())).toEqual(['Matn', 'Fayllar']);
  });

  it('shows the converted text', async () => {
    const fixture = TestBed.createComponent(App);
    const el = fixture.nativeElement as HTMLElement;
    const src = el.querySelector<HTMLTextAreaElement>('[data-testid=source]')!;
    src.value = 'shahar';
    src.dispatchEvent(new Event('input'));
    await fixture.whenStable();
    await new Promise(r => setTimeout(r));
    fixture.detectChanges();
    expect(el.querySelector<HTMLTextAreaElement>('[data-testid=result]')!.value).toBe('SHAHAR');
  });

  it('switches tabs and the interface language', async () => {
    const fixture = TestBed.createComponent(App);
    const el = fixture.nativeElement as HTMLElement;
    el.querySelector<HTMLButtonElement>('#tab-files')!.click();
    await fixture.whenStable();
    expect(el.querySelector('#panel-files')!.hasAttribute('hidden')).toBe(false);
    expect(el.querySelector('#panel-text')!.hasAttribute('hidden')).toBe(true);
    const select = el.querySelector<HTMLSelectElement>('[data-testid=lang]')!;
    for (const [lang, files, paste, htmlLang, title] of [
      ['en', 'Files', 'Paste', 'en', 'Uzbek alphabet converter'],
      ['ru', 'Файлы', 'Вставить', 'ru', 'конвертер узбекского алфавита'],
      ['uz-new', 'Fayllar', 'Qöyiş', 'uz-Latn', 'Özbek alifbo konvertori'],
      ['uz', 'Fayllar', 'Qoʻyish', 'uz-Latn', 'Oʻzbek alifbo konvertori']
    ]) {
      select.value = lang;
      select.dispatchEvent(new Event('change'));
      await fixture.whenStable();
      expect(el.querySelector('#tab-files')!.textContent?.trim()).toBe(files);
      expect([...el.querySelectorAll('button')].some(b => b.textContent?.trim() === paste)).toBe(true);
      expect(document.documentElement.lang).toBe(htmlLang);
      expect(document.title).toContain(title);
    }
  });
});

describe('message tables', () => {
  const keys = Object.keys(MESSAGES.uz).sort();
  const placeholders = (s: string) => (s.match(/\{\w+\}/g) ?? []).sort().join(' ');

  it.each(LANGS.map(l => l.id))('%s has every key, with the same placeholders', id => {
    const table = MESSAGES[id] as Record<string, string>;
    expect(Object.keys(table).sort()).toEqual(keys);
    for (const k of keys) expect(placeholders(table[k]), k).toBe(placeholders((MESSAGES.uz as Record<string, string>)[k]));
  });

  it('Latin 2026 uses the new letters, except in examples of the old spelling', () => {
    // the placeholder's input example, and Isʼhoq → Ishoq (in 2026 Latin "sh" is s+h, since ş is the letter)
    const oldSpellingExamples = ["O'zbekiston Respublikasi, Toshkent shahri", '«Isʼhoq» → «Ishoq»'];
    for (const [k, v] of Object.entries(MESSAGES['uz-new'])) {
      const rest = oldSpellingExamples.reduce((s, e) => s.replace(e, ''), v).replace(/\{\w+\}/g, '');
      expect(/[OoGg][ʻ'‘’]|[Ss][Hh]|[Cc][Hh]/.test(rest), `${k}: ${v}`).toBe(false);
    }
  });
});

describe('SettingsService', () => {
  beforeEach(() => localStorage.clear());

  it('reads ?text=…&from=…&to=… and ignores unknown scripts', () => {
    const s = TestBed.inject(SettingsService);
    expect(s.applyDeepLink('?text=Salom&from=lat&to=cyr')).toBe('Salom');
    expect(s.from()).toBe('lat');
    expect(s.to()).toBe('cyr');
    s.applyDeepLink('?to=klingon');
    expect(s.to()).toBe('cyr');
  });

  it('builds engine options from the switches', () => {
    const s = TestBed.inject(SettingsService);
    s.ascii.set(true);
    s.skipUrls.set(false);
    expect(s.options()).toEqual({ okina: "'", tutuq: "'", skipUrls: false, dictionary: true, dropHardSignAfterO: true, tsFinal: true });
  });

  it('swap uses the detected script when the source is automatic', () => {
    const s = TestBed.inject(SettingsService);
    s.from.set('auto');
    s.to.set('new');
    s.swap('cyr');
    expect([s.from(), s.to()]).toEqual(['new', 'cyr']);
  });
});
