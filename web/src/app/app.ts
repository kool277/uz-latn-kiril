import { Component, computed, inject, signal } from '@angular/core';
import { AlphabetInfo } from './components/alphabet-info';
import { DirectionBar } from './components/direction-bar';
import { DownloadsPanel, REPO_URL } from './components/downloads-panel';
import { FileConverter } from './components/file-converter';
import { TextConverter } from './components/text-converter';
import { EngineService } from './services/engine.service';
import { FileJobsService } from './services/file-jobs.service';
import { I18nService } from './services/i18n.service';
import { SettingsService } from './services/settings.service';
import { ToastService } from './services/toast.service';

type Tab = 'text' | 'files';

@Component({
  selector: 'app-root',
  imports: [DirectionBar, TextConverter, FileConverter, AlphabetInfo, DownloadsPanel],
  templateUrl: './app.html',
  styleUrl: './app.css',
  host: {
    '(document:dragover)': 'onDragOver($event)',
    '(document:drop)': 'onDrop($event)'
  }
})
export class App {
  protected readonly i18n = inject(I18nService);
  protected readonly settings = inject(SettingsService);
  protected readonly engine = inject(EngineService);
  protected readonly toast = inject(ToastService);
  private readonly jobs = inject(FileJobsService);

  protected readonly tab = signal<Tab>('text');
  protected readonly repo = REPO_URL;
  protected readonly version = '1.0.0';
  protected readonly engineLabel = computed(() => {
    const k = this.engine.kind();
    return k ? this.i18n.t(k === 'wasm' ? 'engine.wasm' : 'engine.js', { n: this.engine.threads }) : this.i18n.t('engine.loading');
  });

  protected select(tab: Tab): void {
    this.tab.set(tab);
  }

  protected tabKey(ev: KeyboardEvent): void {
    if (ev.key !== 'ArrowLeft' && ev.key !== 'ArrowRight') return;
    ev.preventDefault();
    const next: Tab = this.tab() === 'text' ? 'files' : 'text';
    this.tab.set(next);
    document.getElementById('tab-' + next)?.focus();
  }

  protected toggleTheme(): void {
    const cur = this.settings.theme();
    const dark = matchMedia('(prefers-color-scheme: dark)').matches;
    this.settings.theme.set(cur ? (cur === 'dark' ? 'light' : 'dark') : dark ? 'light' : 'dark');
  }

  protected toggleLang(): void {
    this.i18n.lang.update(l => (l === 'uz' ? 'en' : 'uz'));
  }

  // files dropped anywhere on the page go to the Files tab
  protected onDragOver(ev: DragEvent): void {
    if (ev.dataTransfer?.types.includes('Files')) ev.preventDefault();
  }

  protected onDrop(ev: DragEvent): void {
    if (!ev.dataTransfer?.files.length) return;
    ev.preventDefault();
    this.tab.set('files');
    this.jobs.add(ev.dataTransfer.files);
  }
}
