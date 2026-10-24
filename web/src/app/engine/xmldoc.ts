import { decodeText, Encoding, encodeText, isUnicode, normaliseLabel } from './encoding';

export interface XmlText {
  text: string;
  encoding: Encoding;
  bom: boolean;
}

const DECL = /^(\ufeff?<\?xml[^>]*?encoding\s*=\s*["'])([^"']+)(["'])/;

/** Decodes an XML file: byte-order mark first, then the declared encoding, then UTF-8 / legacy sniffing. */
export function decodeXmlBytes(bytes: Uint8Array): XmlText {
  const head = new TextDecoder('latin1').decode(bytes.subarray(0, 200));
  const m = /^<\?xml[^>]*?encoding\s*=\s*["']([^"']+)["']/.exec(head);
  const d = decodeText(bytes, m ? m[1] : null);
  return { text: d.text, encoding: d.encoding, bom: d.bom };
}

/** Encodes back; a legacy 8-bit input becomes UTF-8 and its XML declaration says so. */
export function encodeXmlText(x: XmlText): Uint8Array {
  if (isUnicode(x.encoding)) return encodeText(x.text, x.encoding, x.bom);
  const text = x.text.replace(DECL, (_m, a: string, _b: string, c: string) => a + 'UTF-8' + c);
  return encodeText(text, 'utf-8', false);
}

export function declaredEncoding(text: string): string | null {
  const m = DECL.exec(text);
  return m ? m[2] : null;
}

export { normaliseLabel };
