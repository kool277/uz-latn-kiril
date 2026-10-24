import { Component, inject } from '@angular/core';
import { I18nService } from '../services/i18n.service';

export const REPO_URL = 'https://github.com/kool277/uz-latn-kiril';

/** "Yuklab olish / Downloads": the Office macros, ribbon and add-in manifest and the LibreOffice extensions, served from this site. */
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
      <p class="muted">{{ i18n.t('dl.soon') }} <a [href]="repo + '/releases'" rel="noopener" target="_blank">{{ i18n.t('dl.releases') }}</a></p>
    </section>
  `,
  styles: `
    .dl { margin-top: 18px; padding: 14px 16px; }
    h2 { margin: 0 0 10px; font: 700 1.1rem/1.2 var(--serif); }
    ul { list-style: none; margin: 0; padding: 0; display: grid; gap: 10px; }
    li { display: flex; flex-wrap: wrap; align-items: center; gap: 4px 12px; }
    .hint { font-size: .85rem; }
    p { margin: 12px 0 0; font-size: .9rem; }
  `
})
export class DownloadsPanel {
  protected readonly i18n = inject(I18nService);
  protected readonly repo = REPO_URL;
  protected readonly items = [
    { file: 'UzTranslit.bas', label: 'dl.office', hint: 'dl.officeHint' },
    { file: 'UzTranslitRibbon.bas', label: 'dl.ribbon', hint: 'dl.ribbonHint' },
    { file: 'uztranslit-office-addin.xml', label: 'dl.addin', hint: 'dl.addinHint' },
    { file: 'uztranslit-libreoffice.oxt', label: 'dl.lo', hint: 'dl.loHint' },
    { file: 'uztranslit-libreoffice-python.oxt', label: 'dl.loPython', hint: 'dl.loPythonHint' }
  ];
}
