// UzTranslit — WebAssembly port of spec/SPEC.md v1.0.0 (AssemblyScript).
//
// A faithful port of SPEC §5: the same index-based scanners and helper names as core/js/uztranslit.js
// (isCyr, isLat, isApos, nextLetterIsUpper, caseOut, cyrToLatin, latinToCyrScan, convertWordWithDict,
// latToNew, newToLat, detect). Strings are UTF-16 code units, exactly like JavaScript.
//
// On top of the reference behaviour the engine can split its output back into the caller's input
// segments (rich-text runs): the caller passes segment boundaries (source offsets), every scanner
// step reports the source range it consumed, and each boundary is mapped to an output offset. A
// boundary that falls inside a multi-character step (a digraph, a dictionary stem) is placed
// proportionally. Non-letters are always single-character steps, so whitespace never moves.
//
// ABI (all offsets in UTF-16 code units, see uztranslit-wasm.mjs):
//   inputBuffer(n)    -> pointer to write n code units of input
//   boundaryBuffer(k) -> pointer to k i32 source offsets; convert() overwrites them with output offsets
//   convert(n, from, to, options, okina, tutuq, k) -> output length; output at outputPtr()
//   detectInput(n)    -> 0 cyr | 1 lat | 2 new

// ---------------------------------------------------------------- scripts and options
const CYR: i32 = 0;
const LAT: i32 = 1;
const NEW: i32 = 2;
const AUTO: i32 = 3;

const OPT_DROP_HARD_SIGN_AFTER_O: i32 = 1;
const OPT_TS_FINAL: i32 = 2;
const OPT_DICTIONARY: i32 = 4;
const OPT_SKIP_URLS: i32 = 8;

const NONE: i32 = -1; // "no character" (out of the slice, or an empty option string)

// ---------------------------------------------------------------- character classes (SPEC §3)
const F_CYR: u8 = 1;
const F_CYR_UP: u8 = 2;
const F_LAT: u8 = 4;
const F_LAT_UP: u8 = 8;
const F_APOS: u8 = 16;
const F_CYR_VOWEL: u8 = 32;
const F_LAT_VOWEL: u8 = 64;
const F_SPACE: u8 = 128; // JavaScript RegExp \s, for the URL/e-mail tokeniser (SPEC §5.6)

const CASE_N: i32 = 0x500; // every letter of the four alphabets is below U+0500
const FLAGS: usize = memory.data(65536);
const LOWER: usize = memory.data(CASE_N << 1);
const UPPER: usize = memory.data(CASE_N << 1);
const C2L: usize = memory.data(CASE_N << 2); // lowercase Cyrillic -> up to two Latin code units
const L2C: usize = memory.data(CASE_N << 1); // lowercase Latin -> one Cyrillic code unit

const CYR_LOWER = "абвгдеёжзийклмнопрстуфхцчшщъыьэюяўқғҳ";
const CYR_UPPER = "АБВГДЕЁЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯЎҚҒҲ";
const LAT_LOWER = "abcdefghijklmnopqrstuvwxyzöğşçōõ";
const LAT_UPPER = "ABCDEFGHIJKLMNOPQRSTUVWXYZÖĞŞÇŌÕ";
const APOS = "'ʻʼ‘’`´";
const CYR_VOWELS = "аеёиоуэюяўы";
const LAT_VOWELS = "aeiouöōõ";
const C2L_SRC = "а a|б b|в v|г g|д d|ж j|з z|и i|й y|к k|л l|м m|н n|о o|п p|р r|т t|у u|ф f|х x|қ q|ҳ h|э e|ы i|ё yo|ю yu|я ya";
const L2C_SRC = "a а|b б|d д|f ф|g г|h ҳ|i и|j ж|k к|l л|m м|n н|o о|p п|q қ|r р|s с|t т|u у|v в|x х|y й|z з|c ц|w в|ö ў|ō ў|õ ў|ğ ғ|ş ш|ç ч";

// Latin -> Cyrillic stem dictionary (SPEC §6). Keys: lowercase, ASCII apostrophe.
const DICT_SRC = "obyekt объект|subyekt субъект|adyutant адъютант|inyeksiya инъекция|konyunktura конъюнктура|" +
  "kompyuter компьютер|intervyu интервью|premyera премьера|batalyon батальон|bulyon бульон|medalyon медальон|" +
  "shampinyon шампиньон|kanyon каньон|senyor сеньор|tatyana татьяна|ilya илья|nyuton ньютон|" +
  "yoga йога|yogurt йогурт|york йорк|" +
  "sirk цирк|sement цемент|senzura цензура|sentner центнер|sentr центр|sex цех|sikl цикл|silindr цилиндр|" +
  "sisterna цистерна|sitata цитата|sitrus цитрус|sellofan целлофан|sellyuloza целлюлоза|selsiy цельсий|" +
  "seremoniya церемония|sivilizatsiya цивилизация|sianid цианид|sink цинк|sirkul циркуль|sokol цоколь|sunami цунами|sitadel цитадель|sirka сирка|sinkop синкоп|sinkret синкрет|sinklinal синклинал|" +
  "leksiya лекция|aksiya акция|funksiya функция|seksiya секция|fraksiya фракция|reaksiya реакция|sanksiya санкция|" +
  "konstruksiya конструкция|produksiya продукция|redaksiya редакция|kolleksiya коллекция|infeksiya инфекция|" +
  "proporsiya пропорция|porsiya порция|konferensiya конференция|litsenziya лицензия|litsey лицей|ofitser офицер|" +
  "protsent процент|protsess процесс|protsedura процедура|konsert концерт|konsepsiya концепция|konsentratsiya концентрация|" +
  "konsern концерн|potensial потенциал|differensial дифференциал|sotsial социал|sotsiologiya социология|spetsial специал|spetsifik специфик|" +
  "kvarts кварц|shprits шприц|plats плац|blits блиц";

function markCode(c: i32, flag: u8): void {
  const p = FLAGS + <usize>c;
  store<u8>(p, load<u8>(p) | flag);
}

function markAll(set: string, flag: u8): void {
  for (let i = 0; i < set.length; i++) markCode(set.charCodeAt(i), flag);
}

// Parses "k v|k v|…" (single-code-unit keys) into a code-unit table.
function fillTable(src: string, table: usize, width: i32): void {
  let i = 0;
  const n = src.length;
  while (i < n) {
    const k = src.charCodeAt(i);
    let j = i + 2;
    let slot = 0;
    while (j < n && src.charCodeAt(j) != 0x7C) {
      if (slot < width) store<u16>(table + (<usize>(k * width + slot) << 1), <u16>src.charCodeAt(j));
      slot++;
      j++;
    }
    i = j + 1;
  }
}

// ---------------------------------------------------------------- dictionary index
const DICT_MAX: i32 = 512;
const DK_OFF: usize = memory.data(DICT_MAX << 2); // key offset (code units into DICT_SRC)
const DK_LEN: usize = memory.data(DICT_MAX << 2);
const DV_OFF: usize = memory.data(DICT_MAX << 2);
const DV_LEN: usize = memory.data(DICT_MAX << 2);
const BUCKET: usize = memory.data(27 << 3); // per first letter a–z: [start, end) into the sorted key list
let dictCount: i32 = 0;
let dictPtr: usize = 0;

@inline function di(base: usize, k: i32): i32 { return load<i32>(base + (<usize>k << 2)); }
@inline function dset(base: usize, k: i32, v: i32): void { store<i32>(base + (<usize>k << 2), v); }

function initDictionary(): void {
  dictPtr = changetype<usize>(DICT_SRC);
  const n = DICT_SRC.length;
  let i = 0;
  while (i < n && dictCount < DICT_MAX) {
    let sp = i;
    while (DICT_SRC.charCodeAt(sp) != 0x20) sp++;
    let end = sp + 1;
    while (end < n && DICT_SRC.charCodeAt(end) != 0x7C) end++;
    dset(DK_OFF, dictCount, i);
    dset(DK_LEN, dictCount, sp - i);
    dset(DV_OFF, dictCount, sp + 1);
    dset(DV_LEN, dictCount, end - sp - 1);
    dictCount++;
    i = end + 1;
  }
  // sort by (first letter, length desc): the first prefix hit in a bucket is the longest key (SPEC §5.2)
  for (let a = 1; a < dictCount; a++) {
    const ko = di(DK_OFF, a), kl = di(DK_LEN, a), vo = di(DV_OFF, a), vl = di(DV_LEN, a);
    const kf = DICT_SRC.charCodeAt(ko);
    let b = a - 1;
    while (b >= 0) {
      const bf = DICT_SRC.charCodeAt(di(DK_OFF, b));
      if (bf < kf || (bf == kf && di(DK_LEN, b) >= kl)) break;
      dset(DK_OFF, b + 1, di(DK_OFF, b)); dset(DK_LEN, b + 1, di(DK_LEN, b));
      dset(DV_OFF, b + 1, di(DV_OFF, b)); dset(DV_LEN, b + 1, di(DV_LEN, b));
      b--;
    }
    dset(DK_OFF, b + 1, ko); dset(DK_LEN, b + 1, kl); dset(DV_OFF, b + 1, vo); dset(DV_LEN, b + 1, vl);
  }
  for (let k = 0; k < dictCount; k++) {
    const f = DICT_SRC.charCodeAt(di(DK_OFF, k)) - 0x61;
    if (f < 0 || f >= 26) continue;
    const bp = BUCKET + (<usize>f << 3);
    if (load<i32>(bp + 4) == 0) store<i32>(bp, k);
    store<i32>(bp + 4, k + 1);
  }
}

function init(): void {
  markAll(CYR_LOWER, F_CYR);
  markAll(CYR_UPPER, F_CYR | F_CYR_UP);
  markAll(LAT_LOWER, F_LAT);
  markAll(LAT_UPPER, F_LAT | F_LAT_UP);
  markAll(APOS, F_APOS);
  markAll(CYR_VOWELS, F_CYR_VOWEL);
  markAll(LAT_VOWELS, F_LAT_VOWEL);
  for (let i = 0; i < CYR_VOWELS.length; i++) markAll(String.fromCharCode(CYR_UPPER.charCodeAt(CYR_LOWER.indexOf(CYR_VOWELS.charAt(i)))), F_CYR_VOWEL);
  for (let i = 0; i < LAT_VOWELS.length; i++) markAll(String.fromCharCode(LAT_UPPER.charCodeAt(LAT_LOWER.indexOf(LAT_VOWELS.charAt(i)))), F_LAT_VOWEL);
  // RegExp \s: [\t\n\v\f\r \u00a0\u1680\u2000-\u200a\u2028\u2029\u202f\u205f\u3000\ufeff]
  for (let c = 0x09; c <= 0x0D; c++) markCode(c, F_SPACE);
  for (let c = 0x2000; c <= 0x200A; c++) markCode(c, F_SPACE);
  markCode(0x20, F_SPACE); markCode(0xA0, F_SPACE); markCode(0x1680, F_SPACE); markCode(0x2028, F_SPACE);
  markCode(0x2029, F_SPACE); markCode(0x202F, F_SPACE); markCode(0x205F, F_SPACE); markCode(0x3000, F_SPACE);
  markCode(0xFEFF, F_SPACE);
  for (let i = 0; i < CASE_N; i++) {
    store<u16>(LOWER + (<usize>i << 1), <u16>i);
    store<u16>(UPPER + (<usize>i << 1), <u16>i);
  }
  for (let i = 0; i < CYR_LOWER.length; i++) {
    const lo = CYR_LOWER.charCodeAt(i), up = CYR_UPPER.charCodeAt(i);
    store<u16>(LOWER + (<usize>up << 1), <u16>lo);
    store<u16>(UPPER + (<usize>lo << 1), <u16>up);
  }
  for (let i = 0; i < LAT_LOWER.length; i++) {
    const lo = LAT_LOWER.charCodeAt(i), up = LAT_UPPER.charCodeAt(i);
    store<u16>(LOWER + (<usize>up << 1), <u16>lo);
    store<u16>(UPPER + (<usize>lo << 1), <u16>up);
  }
  fillTable(C2L_SRC, C2L, 2);
  fillTable(L2C_SRC, L2C, 1);
  initDictionary();
}
init();

@inline function fl(c: i32): u8 { return c < 0 ? 0 : load<u8>(FLAGS + <usize>c); }
@inline function isCyr(c: i32): bool { return (fl(c) & F_CYR) != 0; }
@inline function isCyrUpper(c: i32): bool { return (fl(c) & F_CYR_UP) != 0; }
@inline function isLat(c: i32): bool { return (fl(c) & F_LAT) != 0; }
@inline function isLatUpper(c: i32): bool { return (fl(c) & F_LAT_UP) != 0; }
@inline function isApos(c: i32): bool { return (fl(c) & F_APOS) != 0; }
@inline function isSpace(c: i32): bool { return (fl(c) & F_SPACE) != 0; }
@inline function isCyrVowel(c: i32): bool { return (fl(c) & F_CYR_VOWEL) != 0; }
@inline function isLatVowel(c: i32): bool { return (fl(c) & F_LAT_VOWEL) != 0; }
@inline function isLetter(c: i32): bool { return (fl(c) & (F_CYR | F_LAT)) != 0; }
@inline function isUpperLetter(c: i32): bool { return (fl(c) & (F_CYR_UP | F_LAT_UP)) != 0; }
@inline function caseTable(t: usize, c: i32): i32 { return <i32>load<u16>(t + (<usize>c << 1)); }
@inline function cyrLower(c: i32): i32 { return isCyrUpper(c) ? caseTable(LOWER, c) : c; }
@inline function cyrUpper(c: i32): i32 { return (fl(c) & (F_CYR | F_CYR_UP)) == F_CYR ? caseTable(UPPER, c) : c; }
@inline function latLower(c: i32): i32 { return isLatUpper(c) ? caseTable(LOWER, c) : c; }
@inline function latUpper(c: i32): i32 { return (fl(c) & (F_LAT | F_LAT_UP)) == F_LAT ? caseTable(UPPER, c) : c; }
@inline function upperChar(c: i32): i32 { return latUpper(cyrUpper(c)); }
@inline function asciiLower(c: i32): i32 { return c >= 0x41 && c <= 0x5A ? c + 0x20 : c; }
@inline function isWordChar(c: i32): bool { // RegExp \w
  return (c >= 0x30 && c <= 0x39) || (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A) || c == 0x5F;
}

// ---------------------------------------------------------------- buffers
let inPtr: usize = 0;
let inCap: i32 = 0;
let outPtr: usize = 0;
let outCap: i32 = 0;
let outLen: i32 = 0;
let bPtr: usize = 0;
let bCap: i32 = 0;
let keyPtr: usize = 0;
let keyCap: i32 = 0;

function grow(ptr: usize, bytes: usize): usize {
  return ptr ? heap.realloc(ptr, bytes) : heap.alloc(bytes);
}

export function inputBuffer(n: i32): usize {
  if (n > inCap) { inCap = max(n, 1024); inPtr = grow(inPtr, <usize>inCap << 1); }
  return inPtr;
}

export function boundaryBuffer(n: i32): usize {
  if (n > bCap) { bCap = max(n, 64); bPtr = grow(bPtr, <usize>bCap << 2); }
  return bPtr;
}

export function outputPtr(): usize { return outPtr; }

function growOut(min: i32): void {
  outCap = max(max(outCap << 1, min), 1024);
  outPtr = grow(outPtr, <usize>outCap << 1);
}

@inline function put(c: i32): void {
  if (outLen >= outCap) growOut(outLen + 1);
  store<u16>(outPtr + (<usize>outLen << 1), <u16>c);
  outLen++;
}

@inline function at(i: i32): i32 { return <i32>load<u16>(inPtr + (<usize>i << 1)); }

// The scanners see only the slice [sa, sb), like the JS reference sees `text` (SPEC §5.6 converts the
// text between URL tokens separately; the dictionary scans one word at a time).
let sa: i32 = 0;
let sb: i32 = 0;
@inline function ch(i: i32): i32 { return i >= sa && i < sb ? at(i) : NONE; }

// ---------------------------------------------------------------- segment boundaries
let bCount: i32 = 0;
let bIdx: i32 = 0;
let stepSrc: i32 = 0;
let stepOut: i32 = 0;

// Called after every scanner step: source [stepSrc, srcEnd) produced output [stepOut, outLen).
@inline function step(srcEnd: i32): void {
  if (bIdx < bCount) splitStep(srcEnd);
  stepSrc = srcEnd;
  stepOut = outLen;
}

function splitStep(srcEnd: i32): void {
  while (bIdx < bCount) {
    const p = bPtr + (<usize>bIdx << 2);
    const b = load<i32>(p);
    if (b >= srcEnd) return;
    let s = stepOut;
    if (b > stepSrc) { // boundary inside a multi-character step: place it proportionally (round half up)
      const inL = <i64>(srcEnd - stepSrc);
      const outL = <i64>(outLen - stepOut);
      s = stepOut + <i32>((outL * <i64>(b - stepSrc) * 2 + inL) / (inL * 2));
    }
    store<i32>(p, s);
    bIdx++;
  }
}

function finishSplits(): void {
  while (bIdx < bCount) {
    store<i32>(bPtr + (<usize>bIdx << 2), outLen);
    bIdx++;
  }
}

// ---------------------------------------------------------------- options
let okina: i32 = 0x2BB;
let tutuq: i32 = 0x2BC;
let dropHardSignAfterO = true;
let tsFinal = true;
let dictionary = true;
let resolvedFrom: i32 = LAT;

@inline function putOpt(c: i32): void { if (c != NONE) put(c); }

// ---------------------------------------------------------------- casing rule (SPEC §4)
function nextLetterIsUpper(i: i32): bool {
  let j = i + 1;
  if (j < sb && isApos(at(j))) j++;
  if (j < sb && isLetter(at(j))) return isUpperLetter(at(j));
  let k = i - 1;
  if (k >= sa && isApos(at(k))) k--;
  if (k >= sa && isLetter(at(k))) return isUpperLetter(at(k));
  return false;
}

// caseOut(text, i, srcUpper, out) for out = r0 r1 (NONE = absent)
function caseOut(i: i32, srcUpper: bool, r0: i32, r1: i32): void {
  if (r0 == NONE) { putOpt(r1); return; }
  if (!srcUpper) { put(r0); putOpt(r1); return; }
  if (r1 == NONE) { put(upperChar(r0)); return; }
  put(upperChar(r0));
  put(nextLetterIsUpper(i) ? upperChar(r1) : r1);
}

// ---------------------------------------------------------------- Cyrillic → Latin (SPEC §5.1)
function cyrToLatin(isNew: bool): void {
  for (let i = sa; i < sb; i++) {
    const c = at(i);
    if (!isCyr(c)) { put(c); step(i + 1); continue; }
    const L = cyrLower(c);
    const up = isCyrUpper(c);
    const P = i > sa ? at(i - 1) : NONE;
    const N = i + 1 < sb ? at(i + 1) : NONE;
    let r0 = NONE, r1 = NONE;
    switch (L) {
      case 0x435: { // е
        const pl = cyrLower(P);
        if (!isCyr(P) || isCyrVowel(P) || pl == 0x44A || pl == 0x44C) { r0 = 0x79; r1 = 0x65; } else r0 = 0x65;
        break;
      }
      case 0x446: { // ц
        if (isCyrVowel(P)) { r0 = 0x74; r1 = 0x73; } else r0 = 0x73;
        break;
      }
      case 0x44A: { // ъ
        const nl = cyrLower(N);
        if (nl == 0x435 || nl == 0x451 || nl == 0x44E || nl == 0x44F) break;
        if (cyrLower(P) == 0x45E && dropHardSignAfterO) break;
        r0 = tutuq;
        break;
      }
      case 0x44C: break; // ь
      case 0x448: case 0x449: { if (isNew) r0 = 0x15F; else { r0 = 0x73; r1 = 0x68; } break; } // ш щ
      case 0x447: { if (isNew) r0 = 0xE7; else { r0 = 0x63; r1 = 0x68; } break; } // ч
      case 0x45E: { if (isNew) r0 = 0xF6; else { r0 = 0x6F; r1 = okina; } break; } // ў
      case 0x493: { if (isNew) r0 = 0x11F; else { r0 = 0x67; r1 = okina; } break; } // ғ
      case 0x441: { if (!isNew && cyrLower(N) == 0x4B3) { r0 = 0x73; r1 = tutuq; } else r0 = 0x73; break; } // с(+ҳ)
      default: {
        const t = C2L + (<usize>L << 2);
        const a = <i32>load<u16>(t);
        if (a == 0) r0 = c;
        else { r0 = a; const b = <i32>load<u16>(t + 2); if (b != 0) r1 = b; }
      }
    }
    caseOut(i, up, r0, r1);
    step(i + 1);
  }
}

// ---------------------------------------------------------------- Latin → Cyrillic (SPEC §5.2)
function latinToCyrScan(isNew: bool, prevCtx: i32): void {
  let i = sa;
  while (i < sb) {
    const c = at(i);
    if (isApos(c)) {
      const pc = i > sa ? at(i - 1) : prevCtx;
      const nc = i + 1 < sb ? at(i + 1) : NONE;
      if (isLat(pc) && (isLat(nc) || c == 0x2BC)) put(isLatUpper(pc) ? 0x42A : 0x44A);
      else put(c);
      i++; step(i); continue;
    }
    if (!isLat(c)) { put(c); i++; step(i); continue; }
    const L = latLower(c);
    const up = isLatUpper(c);
    const N = i + 1 < sb ? at(i + 1) : NONE;
    const N2 = i + 2 < sb ? at(i + 2) : NONE;
    const NL = latLower(N);
    const P = i > sa ? at(i - 1) : prevCtx;
    const prevIsLetter = isLat(P);
    const prevIsVowelOrApos = isLatVowel(P) || isApos(P);

    if (L == 0x6F && isApos(N)) { put(up ? 0x40E : 0x45E); i += 2; step(i); continue; } // oʻ → ў
    if (L == 0x67 && isApos(N)) { put(up ? 0x492 : 0x493); i += 2; step(i); continue; } // gʻ → ғ
    if (L == 0x73) {
      if (NL == 0x68 && !isNew) { put(up ? 0x428 : 0x448); i += 2; step(i); continue; } // sh → ш
      if (isApos(N) && latLower(N2) == 0x68) { put(up ? 0x421 : 0x441); i += 2; step(i); continue; } // sʼh
    }
    if (L == 0x63 && NL == 0x68) { put(up ? 0x427 : 0x447); i += 2; step(i); continue; } // ch → ч
    if (L == 0x79 && (NL == 0x6F || NL == 0x75 || NL == 0x61 || NL == 0x65)) {
      if (NL == 0x6F && isApos(N2)) { put(up ? 0x419 : 0x439); i += 1; step(i); continue; } // yoʻl → йўл
      if (NL == 0x65) {
        if (!prevIsLetter || prevIsVowelOrApos) put(up ? 0x415 : 0x435);
        else { put(up ? 0x42C : 0x44C); put(up ? 0x415 : 0x435); }
      } else if (NL == 0x6F) put(up ? 0x401 : 0x451);
      else if (NL == 0x75) put(up ? 0x42E : 0x44E);
      else put(up ? 0x42F : 0x44F);
      i += 2; step(i); continue;
    }
    if (L == 0x65) {
      put(!prevIsLetter || prevIsVowelOrApos ? (up ? 0x42D : 0x44D) : (up ? 0x415 : 0x435));
      i++; step(i); continue;
    }
    if (L == 0x74 && NL == 0x73) {
      const r0 = asciiLower(ch(i + 2)), r1 = asciiLower(ch(i + 3)), r2 = asciiLower(ch(i + 4));
      if (r0 == 0x69 && ((r1 == 0x79 && r2 == 0x61) || (r1 == 0x6F && r2 == 0x6E))) { // -tsiya, -tsion
        put(up ? 0x426 : 0x446); i += 2; step(i); continue;
      }
      const wordEnds = i + 2 >= sb || !isLat(at(i + 2));
      if (tsFinal && wordEnds && isLatVowel(P)) { put(up ? 0x426 : 0x446); i += 2; step(i); continue; } // abzats
    }
    const r = <i32>load<u16>(L2C + (<usize>L << 1));
    if (r == 0) { put(c); i++; step(i); continue; }
    put(up ? cyrUpper(r) : r);
    i++; step(i);
  }
}

// normKey of one source character: how many key code units it produces
@inline function normLen(c: i32): i32 {
  const L = latLower(c);
  return L == 0xF6 || L == 0x14D || L == 0xF5 || L == 0x11F || L == 0x15F || L == 0xE7 ? 2 : 1;
}

@inline function putKey(k: i32, c: i32): void { store<u16>(keyPtr + (<usize>k << 1), <u16>c); }

// normKey(word) into the key buffer; returns its length
function normKey(ws: i32, we: i32): i32 {
  const need = (we - ws) << 1;
  if (need > keyCap) { keyCap = max(need, 256); keyPtr = grow(keyPtr, <usize>keyCap << 1); }
  let k = 0;
  for (let i = ws; i < we; i++) {
    const c = latLower(at(i));
    if (isApos(c)) putKey(k++, 0x27);
    else if (c == 0xF6 || c == 0x14D || c == 0xF5) { putKey(k++, 0x6F); putKey(k++, 0x27); }
    else if (c == 0x11F) { putKey(k++, 0x67); putKey(k++, 0x27); }
    else if (c == 0x15F) { putKey(k++, 0x73); putKey(k++, 0x68); }
    else if (c == 0xE7) { putKey(k++, 0x63); putKey(k++, 0x68); }
    else putKey(k++, c);
  }
  return k;
}

// longest dictionary key that is a prefix of the normalised word, or -1
function dictLookup(keyLen: i32): i32 {
  if (keyLen == 0) return -1;
  const f = <i32>load<u16>(keyPtr) - 0x61;
  if (f < 0 || f >= 26) return -1;
  const bp = BUCKET + (<usize>f << 3);
  const end = load<i32>(bp + 4);
  for (let k = load<i32>(bp); k < end; k++) {
    const kl = di(DK_LEN, k);
    if (kl > keyLen) continue;
    const ko = dictPtr + (<usize>di(DK_OFF, k) << 1);
    let j = 0;
    while (j < kl && load<u16>(ko + (<usize>j << 1)) == load<u16>(keyPtr + (<usize>j << 1))) j++;
    if (j == kl) return k;
  }
  return -1;
}

function convertWordWithDict(ws: i32, we: i32, isNew: bool): void {
  const hit = dictLookup(normKey(ws, we));
  if (hit < 0) { sa = ws; sb = we; latinToCyrScan(isNew, NONE); return; }
  // how many source characters does the stem cover? (normKey may expand ö→o', ş→sh …)
  const hitLen = di(DK_LEN, hit);
  const wordLen = we - ws;
  let consumed = 0, built = 0;
  while (built < hitLen && consumed < wordLen) { built += normLen(at(ws + consumed)); consumed++; }
  let letters = 0, uppers = 0;
  let firstUpper = false;
  for (let q = 0; q < consumed; q++) {
    const c = at(ws + q);
    if (isLat(c)) {
      letters++;
      if (isLatUpper(c)) { uppers++; if (letters == 1) firstUpper = true; }
    }
  }
  const vo = dictPtr + (<usize>di(DV_OFF, hit) << 1);
  const vl = di(DV_LEN, hit);
  const allCaps = letters >= 2 && uppers == letters;
  for (let k = 0; k < vl; k++) {
    const v = <i32>load<u16>(vo + (<usize>k << 1));
    put(allCaps || (firstUpper && k == 0) ? upperChar(v) : v);
  }
  step(ws + consumed);
  sa = ws + consumed; sb = we;
  latinToCyrScan(isNew, at(ws + consumed - 1));
}

function latinToCyr(isNew: bool): void {
  if (!dictionary) { latinToCyrScan(isNew, NONE); return; }
  const a = sa, b = sb;
  let i = a;
  while (i < b) {
    const c = at(i);
    if (!isLat(c) && !isApos(c)) { put(c); i++; step(i); continue; }
    let j = i;
    while (j < b && (isLat(at(j)) || isApos(at(j)))) j++;
    convertWordWithDict(i, j, isNew);
    i = j;
  }
  sa = a; sb = b;
}

// ---------------------------------------------------------------- Latin 1995 → Latin 2026 (SPEC §5.3)
function latToNew(): void {
  let i = sa;
  while (i < sb) {
    const c = at(i);
    const L = latLower(c);
    const up = isLatUpper(c);
    const N = i + 1 < sb ? at(i + 1) : NONE;
    const NL = latLower(N);
    if (isApos(c)) {
      const pc = i > sa ? at(i - 1) : NONE;
      if (isLat(pc) && isLat(N)) putOpt(tutuq); else put(c);
      i++; step(i); continue;
    }
    if (!isLat(c)) { put(c); i++; step(i); continue; }
    if (L == 0x6F && isApos(N)) { put(up ? 0xD6 : 0xF6); i += 2; step(i); continue; } // oʻ → ö
    if (L == 0x67 && isApos(N)) { put(up ? 0x11E : 0x11F); i += 2; step(i); continue; } // gʻ → ğ
    if (L == 0x73 && NL == 0x68) { put(up ? 0x15E : 0x15F); i += 2; step(i); continue; } // sh → ş
    if (L == 0x73 && isApos(N) && latLower(ch(i + 2)) == 0x68) { put(c); i += 2; step(i); continue; } // sʼh → sh
    if (L == 0x63 && NL == 0x68) { put(up ? 0xC7 : 0xE7); i += 2; step(i); continue; } // ch → ç
    if (L == 0x14D || L == 0xF5) { put(up ? 0xD6 : 0xF6); i++; step(i); continue; } // ō õ → ö
    put(c); i++; step(i);
  }
}

// ---------------------------------------------------------------- Latin 2026 → Latin 1995 (SPEC §5.4)
function newToLat(): void {
  let i = sa;
  while (i < sb) {
    const c = at(i);
    const L = latLower(c);
    const up = isLatUpper(c);
    const N = i + 1 < sb ? at(i + 1) : NONE;
    const NL = latLower(N);
    if (isApos(c)) {
      const pc = i > sa ? at(i - 1) : NONE;
      if (isLat(pc) && isLat(N)) putOpt(tutuq); else put(c);
      i++; step(i); continue;
    }
    if (!isLat(c)) { put(c); i++; step(i); continue; }
    if (L == 0xF6 || L == 0x14D || L == 0xF5) { put(up ? 0x4F : 0x6F); putOpt(okina); i++; step(i); continue; }
    if (L == 0x11F) { put(up ? 0x47 : 0x67); putOpt(okina); i++; step(i); continue; }
    if (L == 0x15F) { caseOut(i, up, 0x73, 0x68); i++; step(i); continue; }
    if (L == 0xE7) { caseOut(i, up, 0x63, 0x68); i++; step(i); continue; }
    if (L == 0x73 && NL == 0x68) { put(c); putOpt(tutuq); i++; step(i); continue; } // Ishoq → Isʼhoq
    put(c); i++; step(i);
  }
}

// ---------------------------------------------------------------- detection (SPEC §5.5)
function detect(a: i32, b: i32): i32 {
  let cyr = 0, lat = 0, nw = 0, dig = 0;
  for (let i = a; i < b; i++) {
    const c = at(i);
    if (isCyr(c)) { cyr++; continue; }
    if (!isLat(c)) continue;
    lat++;
    const L = latLower(c);
    if (L == 0xF6 || L == 0x11F || L == 0x15F || L == 0xE7 || L == 0x14D || L == 0xF5) nw++;
    const N = i + 1 < b ? at(i + 1) : NONE;
    const NL = latLower(N);
    if ((L == 0x73 || L == 0x63) && NL == 0x68) dig++;
    if ((L == 0x6F || L == 0x67) && isApos(N)) dig++;
  }
  if (cyr > lat) return CYR;
  if (nw > 0 && nw >= dig) return NEW;
  return LAT;
}

// ---------------------------------------------------------------- directions
let dirFrom: i32 = LAT;
let dirTo: i32 = NEW;

function convertSlice(a: i32, b: i32): void {
  if (a >= b) return;
  sa = a; sb = b;
  if (dirFrom == CYR) cyrToLatin(dirTo == NEW);
  else if (dirTo == CYR) latinToCyr(dirFrom == NEW);
  else if (dirFrom == LAT) latToNew();
  else newToLat();
}

// URL / e-mail protection (SPEC §5.6), equivalent to /(https?:\/\/|www\.)\S+|\S+@\S+\.\S+|@\w+/g:
// the text between tokens is converted slice by slice, tokens are copied unchanged.
function urlPrefix(p: i32, n: i32): i32 {
  if (p + 4 <= n && at(p) == 0x77 && at(p + 1) == 0x77 && at(p + 2) == 0x77 && at(p + 3) == 0x2E) return 4;
  if (p + 7 <= n && at(p) == 0x68 && at(p + 1) == 0x74 && at(p + 2) == 0x74 && at(p + 3) == 0x70) {
    let q = p + 4;
    if (at(q) == 0x73) q++;
    if (q + 3 <= n && at(q) == 0x3A && at(q + 1) == 0x2F && at(q + 2) == 0x2F) return q + 3 - p;
  }
  return 0;
}

function withSkips(n: i32): void {
  let last = 0, p = 0;
  let runEnd = -1, runAt = -1;
  while (p < n) {
    const c = at(p);
    if (isSpace(c)) { p++; continue; }
    if (p >= runEnd) {
      // a new run of non-space characters: \S+@\S+\.\S+ matches from p to the run end
      // iff some '@' at x >= p+1 is followed by a '.' at y >= x+2 with y <= runEnd-2
      runEnd = p;
      while (runEnd < n && !isSpace(at(runEnd))) runEnd++;
      let dot = -1;
      for (let k = runEnd - 2; k >= p; k--) if (at(k) == 0x2E) { dot = k; break; }
      runAt = -1;
      for (let k = dot - 2; k >= p; k--) if (at(k) == 0x40) { runAt = k; break; }
    }
    let mEnd = -1;
    const pre = urlPrefix(p, n);
    if (pre > 0 && p + pre < runEnd) mEnd = runEnd;
    else if (runAt >= p + 1) mEnd = runEnd;
    else if (c == 0x40 && p + 1 < n && isWordChar(at(p + 1))) {
      mEnd = p + 2;
      while (mEnd < n && isWordChar(at(mEnd))) mEnd++;
    }
    if (mEnd < 0) { p++; continue; }
    convertSlice(last, p);
    for (let k = p; k < mEnd; k++) put(at(k));
    step(mEnd);
    last = mEnd;
    p = mEnd;
  }
  convertSlice(last, n);
}

// ---------------------------------------------------------------- exports
export function convert(n: i32, from: i32, to: i32, options: i32, okinaCode: i32, tutuqCode: i32, boundaries: i32): i32 {
  outLen = 0;
  stepSrc = 0;
  stepOut = 0;
  bIdx = 0;
  bCount = boundaries;
  okina = okinaCode;
  tutuq = tutuqCode;
  dropHardSignAfterO = (options & OPT_DROP_HARD_SIGN_AFTER_O) != 0;
  tsFinal = (options & OPT_TS_FINAL) != 0;
  dictionary = (options & OPT_DICTIONARY) != 0;
  if (n > outCap) growOut(n + (n >> 2));
  if (from == AUTO) from = detect(0, n);
  resolvedFrom = from;
  if (from == to) { // identity: every boundary stays where it is
    memory.copy(outPtr, inPtr, <usize>n << 1);
    outLen = n;
    return n;
  }
  dirFrom = from;
  dirTo = to;
  if ((options & OPT_SKIP_URLS) != 0) withSkips(n);
  else convertSlice(0, n);
  finishSplits();
  return outLen;
}

export function resolvedSource(): i32 { return resolvedFrom; }

export function detectInput(n: i32): i32 { return detect(0, n); }
