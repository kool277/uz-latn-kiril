import { Component, inject } from '@angular/core';
import { I18nService } from '../services/i18n.service';
import { appDownloads, RELEASE_INFO, releaseFileUrl } from './release-info';

export const REPO_URL = 'https://github.com/kool277/uz-latn-kiril';

/** "Yuklab olish / Downloads": the Office macros, ribbon and add-in manifest and the LibreOffice extensions, served from this
 *  site, and the apps of the latest GitHub release (direct links; only files that release has). */
@Component({
  selector: 'app-downloads-panel',
  template: `
    <section class="card dl" id="downloads" aria-labelledby="dl-title">
      <h2 id="dl-title">{{ i18n.t('dl.title') }}</h2>
      <ul>
        @for (d of items; track d.file) {
          <li>
            <a class="btn" [href]="'downloads/' + d.file" [attr.download]="d.file">⬇ {{ i18n.t(d.label) }}</a>
            <span class="muted hint">{{ i18n.t(d.hint) }}</span>
          </li>
        }
      </ul>
      @if (release && apps.length) {
        <h3>{{ i18n.t('dl.appsTitle') }}</h3>
        <ul data-testid="apps">
          @for (a of apps; track a.url) {
            <li>
              <a class="btn" [href]="a.url" rel="noopener">⬇ {{ i18n.t(a.label) }}</a>
              <span class="muted hint">{{ i18n.t('dl.appMeta', { version: release.tag, size: i18n.num(a.size / 1048576, 1) }) }}</span>
            </li>
          }
        </ul>
        <p class="muted">{{ i18n.t('dl.unsigned') }}</p>
        <p class="muted">
          <a [href]="checksums" rel="noopener">{{ i18n.t('dl.checksums') }}</a> ·
          <a [href]="repo + '/releases/latest'" rel="noopener" target="_blank">{{ i18n.t('dl.releases') }}</a>
        </p>
      } @else {
        <p class="muted">{{ i18n.t('dl.soon') }} <a [href]="repo + '/releases/latest'" rel="noopener" target="_blank">{{ i18n.t('dl.releases') }}</a></p>
      }
    </section>
  `,
  styles: `
    .dl { margin-top: 18px; padding: 14px 16px; }
    h2 { margin: 0 0 10px; font: 700 1.1rem/1.2 var(--serif); }
    h3 { margin: 16px 0 10px; font: 700 1rem/1.2 var(--serif); }
    ul { list-style: none; margin: 0; padding: 0; display: grid; gap: 10px; }
    li { display: flex; flex-wrap: wrap; align-items: center; gap: 4px 12px; }
    .hint { font-size: .85rem; }
    p { margin: 12px 0 0; font-size: .9rem; }
  `
})
export class DownloadsPanel {
  protected readonly i18n = inject(I18nService);
  protected readonly repo = REPO_URL;
  protected readonly release = inject(RELEASE_INFO);
  protected readonly apps = appDownloads(this.release, REPO_URL);
  protected readonly checksums = this.release ? releaseFileUrl(this.release, REPO_URL, 'SHA256SUMS.txt') : '';
  protected readonly items = [
    { file: 'UzTranslit.bas', label: 'dl.office', hint: 'dl.officeHint' },
    { file: 'UzTranslitRibbon.bas', label: 'dl.ribbon', hint: 'dl.ribbonHint' },
    { file: 'uztranslit-office-addin.xml', label: 'dl.addin', hint: 'dl.addinHint' },
    { file: 'uztranslit-libreoffice.oxt', label: 'dl.lo', hint: 'dl.loHint' },
    { file: 'uztranslit-libreoffice-python.oxt', label: 'dl.loPython', hint: 'dl.loPythonHint' }
  ];
}
