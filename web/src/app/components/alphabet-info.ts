import { Component, inject } from '@angular/core';
import { I18nService } from '../services/i18n.service';

/** The letters law OʻRQ-1184 changes. */
@Component({
  selector: 'app-alphabet-info',
  template: `
    <section class="note" [attr.aria-label]="i18n.t('info.law')">
      <p class="lead"><b>{{ i18n.t('info.law') }}</b></p>
      <table class="alpha">
        <thead><tr><th scope="col">1995</th><th></th><th scope="col">2026</th><th scope="col">{{ i18n.t('info.example') }}</th></tr></thead>
        <tbody>
          @for (r of rows; track r[0]) {
            <tr><td class="big">{{ r[0] }}</td><td class="arrow" aria-hidden="true">→</td><td class="big">{{ r[1] }}</td><td>{{ r[2] }}</td></tr>
          }
        </tbody>
      </table>
      <p>{{ i18n.t('info.notes') }}</p>
    </section>
  `,
  styles: `
    .note { margin-top: 18px; }
    .lead { margin: 0 0 4px; color: var(--ink); }
    table { border-collapse: collapse; margin: 6px 0; font-size: .95rem; }
    td, th { padding: 4px 12px 4px 0; text-align: left; }
    th { color: var(--muted); font-weight: 500; }
    .big { font-family: var(--serif); font-size: 1.25rem; color: var(--ink); white-space: nowrap; }
    .arrow { color: var(--accent); }
    p { margin: 6px 0 0; }
  `
})
export class AlphabetInfo {
  protected readonly i18n = inject(I18nService);
  protected readonly rows = [
    ['Oʻ oʻ', 'Ö ö', 'Oʻzbekiston → Özbekiston'],
    ['Gʻ gʻ', 'Ğ ğ', 'gʻalaba → ğalaba'],
    ['Sh sh', 'Ş ş', 'shahar → şahar'],
    ['Ch ch', 'Ç ç', 'chiroyli → çiroyli']
  ];
}
