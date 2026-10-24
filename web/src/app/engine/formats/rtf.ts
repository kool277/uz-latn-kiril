import { applyEdits, Edit, Paragraph, Segment, SEP_OBJECT } from '../text-model';
import { Prepared } from './prepared';

/**
 * Rich Text Format. A run is a stretch of pure text (plain characters, \'hh bytes, \uN escapes and
 * text-like symbols such as \rquote); any other control word or brace ends it, so formatting is never
 * inside a rewritten range. Runs of one paragraph are converted together, each written back as \uN
 * escapes. Pictures, field codes, font tables and other non-text destinations are left untouched.
 */

const SKIP_DEST = new Set(('fonttbl colortbl stylesheet listtable listoverridetable revtbl rsidtbl generator info pict object objdata ' +
  'fldinst themedata colorschememapping latentstyles datastore xmlnstbl filetbl bkmkstart bkmkend pntxta pntxtb pntext ' +
  'leveltext levelnumbers listtext sp sn sv nonshppict mmathPr mmath oMath oMathPara atnid atnauthor atndate userprops docvar ' +
  'template background pgdsctbl protusertbl wgrffmtfilter passwordhash xform defchp defpap ftnsep ftnsepc ftncn aftnsep ' +
  'aftnsepc aftncn fldtype formfield').split(' '));
// starred destinations that do contain document text
const STARRED_TEXT = new Set(['shpinst']);
// destinations with their own text (not part of the surrounding paragraph)
const OWN_TEXT = /^(footnote|annotation|header[lrf]?|footer[lrf]?|shptxt)$/;
const PARA_BREAK = new Set(['par', 'sect', 'page', 'cell', 'row', 'nestcell', 'nestrow', 'column']);
const SEP_WORDS: Record<string, string> = { tab: '\t', line: '\n', chftn: SEP_OBJECT, chpgn: SEP_OBJECT, chdate: SEP_OBJECT };
// control words that are just characters: they belong to the run (\rquote is how Word writes oʻzbek's mark)
const CHAR_WORDS: Record<string, string> = { lquote: '‘', rquote: '’', ldblquote: '“', rdblquote: '”', emdash: '—', endash: '–', bullet: '•', emspace: '\u2003', enspace: '\u2002', qmspace: '\u2005' };
const CHAR_SYMBOLS: Record<string, string> = { '~': '\u00a0', '_': '‑', '-': '\u00ad' };

const CHARSET_CP: Record<number, number> = {
  0: 1252, 2: 1252, 77: 10000, 128: 932, 129: 949, 130: 1361, 134: 936, 136: 950, 161: 1253, 162: 1254, 163: 1258,
  177: 1255, 178: 1256, 186: 1257, 204: 1251, 222: 874, 238: 1250, 254: 437, 255: 850
};

function decoderFor(cp: number): TextDecoder {
  const label = cp === 437 ? 'ibm437' : cp === 850 ? 'ibm850' : cp === 866 ? 'ibm866' : cp === 932 ? 'shift_jis' : cp === 936 ? 'gbk' :
    cp === 949 ? 'euc-kr' : cp === 950 ? 'big5' : cp === 10000 ? 'macintosh' : cp === 874 ? 'windows-874' : `windows-${cp}`;
  try { return new TextDecoder(label); } catch { return new TextDecoder('windows-1252'); }
}

interface State {
  skip: boolean;
  uc: number;
  font: number;
  dest: string;
  own: boolean;
}

interface RtfSegment extends Segment {
  uc: number;
}

export function isRtf(bytes: Uint8Array): boolean {
  return bytes.length > 5 && bytes[0] === 0x7b && bytes[1] === 0x5c && bytes[2] === 0x72 && bytes[3] === 0x74 && bytes[4] === 0x66;
}

export function prepareRtf(bytes: Uint8Array): Prepared {
  const src = new TextDecoder('latin1').decode(bytes); // RTF is 7-bit; stray 8-bit bytes map 1:1
  const n = src.length;
  const paras: Paragraph<RtfSegment>[] = [];
  const fontCharset = new Map<number, number>();
  const decoders = new Map<number, TextDecoder>();
  let ansiCp = 1252, defFont = -1, fontInTable = -1;
  let st: State = { skip: false, uc: 1, font: -1, dest: '', own: false };
  const stack: State[] = [];
  let groupStart = false, starred = false;
  let para = new Paragraph<RtfSegment>();
  let runStart = -1, runText = '';
  let pending: number[] = [];

  const cpOf = () => {
    const cs = fontCharset.get(st.font >= 0 ? st.font : defFont);
    return cs === undefined || cs === 1 ? ansiCp : CHARSET_CP[cs] ?? ansiCp;
  };
  const flushBytes = () => {
    if (!pending.length) return;
    const cp = cpOf();
    let d = decoders.get(cp);
    if (!d) decoders.set(cp, d = decoderFor(cp));
    runText += d.decode(new Uint8Array(pending));
    pending = [];
  };
  const endRun = (at: number) => {
    flushBytes();
    if (runStart >= 0 && at > runStart) para.add({ start: runStart, end: at, text: runText, uc: st.uc });
    runStart = -1;
    runText = '';
  };
  const endPara = () => {
    if (para.segments) paras.push(para);
    para = new Paragraph<RtfSegment>();
  };
  const textChar = (at: number, ch: string) => {
    if (st.skip) return;
    if (runStart < 0) runStart = at;
    flushBytes();
    runText += ch;
  };

  let i = 0;
  while (i < n) {
    const c = src.charCodeAt(i);
    if (c === 0x7b) { // {
      endRun(i);
      stack.push(st);
      st = { ...st, dest: '', own: false };
      groupStart = true;
      starred = false;
      i++;
      continue;
    }
    if (c === 0x7d) { // }
      endRun(i);
      const closing = st;
      st = stack.pop() ?? st;
      if (closing.own && !closing.skip) endPara();
      groupStart = false;
      i++;
      continue;
    }
    if (c === 0x0d || c === 0x0a) { endRun(i); i++; continue; } // source line breaks are not text
    if (c !== 0x5c) { // a plain character (8-bit bytes are in the current code page)
      if (!st.skip) {
        if (runStart < 0) runStart = i;
        if (c >= 0x80) pending.push(c); else { flushBytes(); runText += src[i]; }
      }
      groupStart = false;
      i++;
      continue;
    }
    const d = src.charCodeAt(i + 1);
    if ((d >= 0x61 && d <= 0x7a) || (d >= 0x41 && d <= 0x5a)) { // control word
      let j = i + 1;
      while (j < n && /[A-Za-z]/.test(src[j])) j++;
      const word = src.slice(i + 1, j);
      let k = j;
      if (src[k] === '-' || /[0-9]/.test(src[k] ?? '')) { k++; while (k < n && /[0-9]/.test(src[k])) k++; }
      const param = k > j ? parseInt(src.slice(j, k), 10) : NaN;
      if (src[k] === ' ') k++;
      const isDest = groupStart || starred;
      groupStart = false;
      if (word === 'u' && !isNaN(param)) {
        textChar(i, String.fromCharCode(param < 0 ? param + 65536 : param));
        let skipN = st.uc; // fallback characters for readers without Unicode
        while (skipN > 0 && k < n) {
          if (src[k] === '\\' && src[k + 1] === "'") k += 4;
          else if (src[k] === '{' || src[k] === '}' || src[k] === '\\') break;
          else k++;
          skipN--;
        }
        starred = false;
        i = k;
        continue;
      }
      if (word in CHAR_WORDS) { textChar(i, CHAR_WORDS[word]); starred = false; i = k; continue; }
      endRun(i);
      if (word === 'bin' && !isNaN(param)) { i = k + Math.max(0, param); starred = false; continue; }
      if (isDest) {
        st.dest = word;
        if ((starred && !STARRED_TEXT.has(word)) || SKIP_DEST.has(word)) st.skip = true;
        else if (OWN_TEXT.test(word) && !st.skip) { endPara(); st.own = true; }
      }
      starred = false;
      switch (word) {
        case 'ansicpg': if (!isNaN(param)) ansiCp = param; break;
        case 'mac': ansiCp = 10000; break;
        case 'pc': ansiCp = 437; break;
        case 'pca': ansiCp = 850; break;
        case 'deff': if (!isNaN(param)) defFont = param; break;
        case 'uc': if (!isNaN(param)) st.uc = param; break;
        case 'f':
          if (st.dest === 'fonttbl' || stack.some(s => s.dest === 'fonttbl')) fontInTable = param;
          else st.font = param;
          break;
        case 'fcharset': if (fontInTable >= 0 && !isNaN(param)) fontCharset.set(fontInTable, param); break;
        case 'plain': st.font = -1; break;
        default:
          if (st.skip) break;
          if (PARA_BREAK.has(word)) endPara();
          else if (word in SEP_WORDS) para.sep(SEP_WORDS[word]);
      }
      i = k;
      continue;
    }
    if (d === 0x27) { // \'hh
      const hex = parseInt(src.slice(i + 2, i + 4), 16);
      if (!st.skip && !isNaN(hex)) { if (runStart < 0) runStart = i; pending.push(hex); }
      groupStart = false;
      i += 4;
      continue;
    }
    if (d === 0x2a) { starred = true; i += 2; continue; } // \*
    if (d === 0x5c || d === 0x7b || d === 0x7d) { textChar(i, src[i + 1]); groupStart = false; i += 2; continue; } // \\ \{ \}
    const sym = src[i + 1];
    if (sym in CHAR_SYMBOLS) { textChar(i, CHAR_SYMBOLS[sym]); groupStart = false; i += 2; continue; }
    endRun(i);
    if ((d === 0x0d || d === 0x0a) && !st.skip) endPara(); // \<newline> is \par
    groupStart = false;
    i += 2;
  }
  endRun(n);
  endPara();

  return {
    format: 'rtf',
    mime: 'application/rtf',
    paras,
    parts: 1,
    warnings: [],
    finish: () => {
      const edits: Edit[] = [];
      for (const p of paras) {
        for (const it of p.items) {
          if (typeof it === 'string' || it.out === undefined || it.out === it.text) continue;
          edits.push({ start: it.start, end: it.end, text: encodeRtf(it.out, it.uc) });
        }
      }
      if (!edits.length) return null;
      const out = applyEdits(src, edits);
      const result = new Uint8Array(out.length);
      for (let k = 0; k < out.length; k++) result[k] = out.charCodeAt(k);
      return result;
    }
  };
}

/** RTF for a converted run: ASCII as is (escaping \ { }), everything else as \uN plus uc fallback marks. */
function encodeRtf(s: string, uc: number): string {
  let out = '';
  for (let k = 0; k < s.length; k++) {
    const c = s.charCodeAt(k);
    if (c === 0x5c || c === 0x7b || c === 0x7d) out += '\\' + s[k];
    else if (c >= 0x20 && c < 0x7f) out += s[k];
    else out += '\\u' + (c > 32767 ? c - 65536 : c) + (uc > 0 ? '?'.repeat(uc) : ' ');
  }
  return out;
}
