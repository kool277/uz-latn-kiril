import { Script } from './types';

const SCRIPT_SUBTAG = /^[A-Za-z]{4}$/;

function scriptName(to: Script, like: string): string {
  const s = to === 'cyr' ? 'Cyrl' : 'Latn';
  return like === like.toUpperCase() ? s.toUpperCase() : like === like.toLowerCase() ? s.toLowerCase() : s;
}

/**
 * Moves an Uzbek language tag to the target script (uz-Cyrl-UZ ↔ uz-Latn-UZ, uz → uz-Cyrl) so that word
 * processors pick the right spell checker; tags of other languages come back unchanged.
 */
export function uzLangTag(tag: string, to: Script): string {
  const sep = tag.includes('_') ? '_' : '-';
  const parts = tag.split(/[-_]/);
  if (parts[0].toLowerCase() !== 'uz') return tag;
  if (parts.length > 1 && SCRIPT_SUBTAG.test(parts[1])) {
    const cur = parts[1].toLowerCase();
    if (cur !== 'cyrl' && cur !== 'latn') return tag;
    parts[1] = scriptName(to, parts[1]);
    return parts.join(sep);
  }
  if (to !== 'cyr') return tag; // plain "uz" already means Latin script
  parts.splice(1, 0, 'Cyrl');
  return parts.join(sep);
}

/** ISO 15924 code for an ODF fo:script value of Uzbek text. */
export function uzScriptCode(value: string, to: Script): string {
  const v = value.toLowerCase();
  return v === 'cyrl' || v === 'latn' ? scriptName(to, value) : value;
}
