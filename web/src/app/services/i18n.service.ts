import { computed, Injectable, signal } from '@angular/core';
import { en } from '../i18n/en';
import { ru } from '../i18n/ru';
import { MessageKey, uz } from '../i18n/uz';
import { uzNew } from '../i18n/uz-new';

export type Lang = 'uz' | 'uz-new' | 'ru' | 'en';
export type { MessageKey };

export interface LangInfo {
  id: Lang;
  /** the language's name in itself, shown in the switcher */
  name: string;
  /** value of <html lang> */
  htmlLang: string;
  /** locale for numbers */
  locale: string;
}

export const LANGS: readonly LangInfo[] = [
  { id: 'uz', name: 'Oʻzbekcha (1995)', htmlLang: 'uz-Latn', locale: 'uz-Latn-UZ' },
  { id: 'uz-new', name: 'Özbekça (2026)', htmlLang: 'uz-Latn', locale: 'uz-Latn-UZ' },
  { id: 'ru', name: 'Русский', htmlLang: 'ru', locale: 'ru-RU' },
  { id: 'en', name: 'English', htmlLang: 'en', locale: 'en-US' }
];

/** Every table has every key (TypeScript checks it); a new string goes into all four. */
export const MESSAGES: Record<Lang, Record<MessageKey, string>> = { uz, 'uz-new': uzNew, ru, en };

export function isLang(v: unknown): v is Lang {
  return LANGS.some(l => l.id === v);
}

/** Interface language: Uzbek in Latin 1995 (default) or Latin 2026, Russian, English. */
@Injectable({ providedIn: 'root' })
export class I18nService {
  readonly lang = signal<Lang>('uz');
  readonly info = computed(() => LANGS.find(l => l.id === this.lang()) ?? LANGS[0]);

  t(key: MessageKey | string, params?: Record<string, string | number>): string {
    const table = MESSAGES[this.lang()] as Record<string, string>;
    let s = table[key] ?? (en as Record<string, string>)[key] ?? key;
    if (params) for (const k in params) s = s.replace('{' + k + '}', String(params[k]));
    return s;
  }

  /** A number formatted for the interface language (1 234,5 / 1,234.5). */
  num(n: number, fractionDigits = 0): string {
    return n.toLocaleString(this.info().locale, { maximumFractionDigits: fractionDigits });
  }
}
