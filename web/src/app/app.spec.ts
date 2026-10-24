import { signal } from '@angular/core';
import { TestBed } from '@angular/core/testing';
import { App } from './app';
import { EngineService } from './services/engine.service';
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
    [...el.querySelectorAll<HTMLButtonElement>('button')].find(b => b.textContent?.trim() === 'English')!.click();
    await fixture.whenStable();
    expect(el.querySelector('#tab-files')!.textContent?.trim()).toBe('Files');
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
