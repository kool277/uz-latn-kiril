import { signal } from '@angular/core';
import { TestBed } from '@angular/core/testing';
import { App } from './app';
import { DownloadsPanel } from './components/downloads-panel';
import { appDownloads, RELEASE_INFO, ReleaseInfo } from './components/release-info';
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
    const technicalNames = ['SHA256SUMS.txt', 'SHA-256'];   // file and algorithm names are not Uzbek words
    for (const [k, v] of Object.entries(MESSAGES['uz-new'])) {
      const rest = [...oldSpellingExamples, ...technicalNames].reduce((s, e) => s.replaceAll(e, ''), v).replace(/\{\w+\}/g, '');
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

describe('download buttons for the latest release', () => {
  const repo = 'https://github.com/kool277/uz-latn-kiril';
  const release: ReleaseInfo = {
    tag: 'v1.3.0',
    files: [
      { name: 'SHA256SUMS.txt', size: 1308 },
      { name: 'UzTranslit-1.3.0-android.aab', size: 3686984 },
      { name: 'UzTranslit-1.3.0-android.apk', size: 1439717 },
      { name: 'UzTranslit-1.3.0-macOS.dmg', size: 23480401 },
      { name: 'UzTranslit-1.3.0-Office-Setup.exe', size: 16372603 },
      { name: 'UzTranslit-1.3.0-Windows-x64-setup.exe', size: 15365120 },
      { name: 'UzTranslit-1.3.0-x86_64.AppImage', size: 30231032 }
    ]
  };

  it('links every app the release has, in a fixed order, to that release', () => {
    expect(appDownloads(release, repo).map(a => [a.label, a.url])).toEqual([
      ['dl.appWindows', repo + '/releases/download/v1.3.0/UzTranslit-1.3.0-Windows-x64-setup.exe'],
      ['dl.appMac', repo + '/releases/download/v1.3.0/UzTranslit-1.3.0-macOS.dmg'],
      ['dl.appLinux', repo + '/releases/download/v1.3.0/UzTranslit-1.3.0-x86_64.AppImage'],
      ['dl.appAndroid', repo + '/releases/download/v1.3.0/UzTranslit-1.3.0-android.apk'],
      ['dl.appOffice', repo + '/releases/download/v1.3.0/UzTranslit-1.3.0-Office-Setup.exe']
    ]);
  });

  it('leaves out what a release lacks, and everything without a release', () => {
    const partial = { tag: 'v1.0.0', files: release.files.filter(f => !/\.dmg$|Office/.test(f.name)) };
    expect(appDownloads(partial, repo).map(a => a.label)).toEqual(['dl.appWindows', 'dl.appLinux', 'dl.appAndroid']);
    expect(appDownloads(null, repo)).toEqual([]);
  });

  async function render(info: ReleaseInfo | null) {
    TestBed.resetTestingModule();
    await TestBed.configureTestingModule({ imports: [DownloadsPanel], providers: [{ provide: RELEASE_INFO, useValue: info }] }).compileComponents();
    const fixture = TestBed.createComponent(DownloadsPanel);
    await fixture.whenStable();
    return fixture.nativeElement as HTMLElement;
  }

  it('shows the buttons with version and size, and the checksums', async () => {
    const el = await render(release);
    const links = [...el.querySelectorAll<HTMLAnchorElement>('[data-testid=apps] a')];
    expect(links.map(a => a.textContent?.trim())).toEqual([
      '⬇ Windows 10/11 ilovasi', '⬇ macOS ilovasi (12 va keyingi)', '⬇ Linux ilovasi (AppImage, x86-64)',
      '⬇ Android ilovasi (7 va keyingi, APK)', '⬇ Word va Excel uchun oʻrnatuvchi (Windows)'
    ]);
    expect(el.querySelector('[data-testid=apps] .hint')?.textContent?.trim()).toBe('v1.3.0 · 14,7 MB');
    const sums = [...el.querySelectorAll<HTMLAnchorElement>('a')].find(a => a.textContent?.includes('SHA256SUMS.txt'));
    expect(sums?.href).toBe(repo + '/releases/download/v1.3.0/SHA256SUMS.txt');
  });

  it('without a release: only the link to the releases page', async () => {
    const el = await render(null);
    expect(el.querySelector('[data-testid=apps]')).toBeNull();
    expect(el.textContent).toContain('GitHub Releases');
  });
});
