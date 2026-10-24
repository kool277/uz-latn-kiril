/*!
 * uztranslit v1.0.0 — Uzbek script converter
 * Cyrillic (1940) ⇄ Latin 1995 ⇄ Latin 2026 (OʻRQ-1184: Oʻ→Ö, Gʻ→Ğ, Sh→Ş, Ch→Ç)
 * Reference implementation of spec/SPEC.md. Zero dependencies. UMD: browser global `UzTranslit`, CommonJS, AMD.
 * MIT License.
 */
(function (root, factory) {
  if (typeof define === 'function' && define.amd) define([], factory);
  else if (typeof module === 'object' && module.exports) module.exports = factory();
  else root.UzTranslit = factory();
})(typeof self !== 'undefined' ? self : this, function () {
  'use strict';

  var VERSION = '1.0.0';
  var OKINA = 'ʻ';   // ʻ  used in Oʻ Gʻ
  var TUTUQ = 'ʼ';   // ʼ  tutuq belgisi

  // ---------------------------------------------------------------- character classes
  var CYR_LOWER = 'абвгдеёжзийклмнопрстуфхцчшщъыьэюяўқғҳ';
  var CYR_UPPER = 'АБВГДЕЁЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯЎҚҒҲ';
  var LAT_LOWER = 'abcdefghijklmnopqrstuvwxyzöğşçōõ';
  var LAT_UPPER = 'ABCDEFGHIJKLMNOPQRSTUVWXYZÖĞŞÇŌÕ';
  var APOS = "'ʻʼ‘’`´";
  var CYR_VOWELS = 'аеёиоуэюяўы'; // а е ё и о у э ю я ў ы
  var LAT_VOWELS = 'aeiouöōõ';

  // NOTE: every helper must treat '' / undefined as "no character" ("".indexOf('') is 0 in JS!)
  function has(set, c) { return typeof c === 'string' && c.length === 1 && set.indexOf(c) >= 0; }
  function isCyr(c) { return has(CYR_LOWER, c) || has(CYR_UPPER, c); }
  function isCyrUpper(c) { return has(CYR_UPPER, c); }
  function cyrLower(c) { return has(CYR_UPPER, c) ? CYR_LOWER.charAt(CYR_UPPER.indexOf(c)) : c; }
  function cyrUpper(c) { return has(CYR_LOWER, c) ? CYR_UPPER.charAt(CYR_LOWER.indexOf(c)) : c; }
  function isCyrVowel(c) { return has(CYR_VOWELS, cyrLower(c)); }

  function isLat(c) { return has(LAT_LOWER, c) || has(LAT_UPPER, c); }
  function isLatUpper(c) { return has(LAT_UPPER, c); }
  function latLower(c) { return has(LAT_UPPER, c) ? LAT_LOWER.charAt(LAT_UPPER.indexOf(c)) : c; }
  function latUpper(c) { return has(LAT_LOWER, c) ? LAT_UPPER.charAt(LAT_LOWER.indexOf(c)) : c; }
  function isLatVowel(c) { return has(LAT_VOWELS, latLower(c)); }

  function isApos(c) { return has(APOS, c); }
  function isLetter(c) { return isCyr(c) || isLat(c); }
  function isUpperLetter(c) { return isCyrUpper(c) || isLatUpper(c); }

  function upperStr(s) { var o = ''; for (var i = 0; i < s.length; i++) o += latUpper(cyrUpper(s.charAt(i))); return o; }
  function upperFirst(s) { return s.length ? latUpper(cyrUpper(s.charAt(0))) + s.slice(1) : s; }

  // Casing rule (SPEC §4)
  function nextLetterIsUpper(text, i) {
    var j = i + 1;
    if (j < text.length && isApos(text.charAt(j))) j++;
    if (j < text.length && isLetter(text.charAt(j))) return isUpperLetter(text.charAt(j));
    var k = i - 1;
    if (k >= 0 && isApos(text.charAt(k))) k--;
    if (k >= 0 && isLetter(text.charAt(k))) return isUpperLetter(text.charAt(k));
    return false;
  }
  function caseOut(text, i, srcUpper, out) {
    if (!srcUpper || out.length === 0) return out;
    if (out.length === 1) return upperStr(out);
    return nextLetterIsUpper(text, i) ? upperStr(out) : upperFirst(out);
  }

  // ---------------------------------------------------------------- options
  var DEFAULTS = {
    okina: OKINA,
    tutuq: TUTUQ,
    dropHardSignAfterO: true,
    tsFinal: true,
    dictionary: true,
    skipUrls: true
  };
  function opts(o) {
    var r = {};
    for (var k in DEFAULTS) r[k] = (o && o[k] !== undefined) ? o[k] : DEFAULTS[k];
    return r;
  }

  // ---------------------------------------------------------------- tables
  var C2L = {
    'а': 'a', 'б': 'b', 'в': 'v', 'г': 'g', 'д': 'd', 'ж': 'j', 'з': 'z',
    'и': 'i', 'й': 'y', 'к': 'k', 'л': 'l', 'м': 'm', 'н': 'n', 'о': 'o',
    'п': 'p', 'р': 'r', 'т': 't', 'у': 'u', 'ф': 'f', 'х': 'x', 'қ': 'q',
    'ҳ': 'h', 'э': 'e', 'ы': 'i', 'ё': 'yo', 'ю': 'yu', 'я': 'ya'
  };
  var L2C = {
    a: 'а', b: 'б', d: 'д', f: 'ф', g: 'г', h: 'ҳ', i: 'и', j: 'ж',
    k: 'к', l: 'л', m: 'м', n: 'н', o: 'о', p: 'п', q: 'қ', r: 'р',
    s: 'с', t: 'т', u: 'у', v: 'в', x: 'х', y: 'й', z: 'з', c: 'ц', w: 'в',
    'ö': 'ў', 'ō': 'ў', 'õ': 'ў', 'ğ': 'ғ', 'ş': 'ш', 'ç': 'ч'
  };

  // Latin → Cyrillic stem dictionary (SPEC §6). Keys: lowercase, ASCII apostrophe.
  var DICT_SRC = 'obyekt объект|subyekt субъект|adyutant адъютант|inyeksiya инъекция|konyunktura конъюнктура|' +
    'kompyuter компьютер|intervyu интервью|premyera премьера|batalyon батальон|bulyon бульон|medalyon медальон|' +
    'shampinyon шампиньон|kanyon каньон|senyor сеньор|tatyana татьяна|ilya илья|nyuton ньютон|' +
    'yod йод|yoga йога|yogurt йогурт|york йорк|yota йота|' +
    'sirk цирк|sement цемент|senzura цензура|sentner центнер|sentr центр|sex цех|sikl цикл|silindr цилиндр|' +
    'sisterna цистерна|sitata цитата|sitrus цитрус|sellofan целлофан|sellyuloza целлюлоза|selsiy цельсий|' +
    'seremoniya церемония|sivilizatsiya цивилизация|sianid цианид|sink цинк|sirkul циркуль|sokol цоколь|sunami цунами|sitadel цитадель|' +
    'leksiya лекция|aksiya акция|funksiya функция|seksiya секция|fraksiya фракция|reaksiya реакция|sanksiya санкция|' +
    'konstruksiya конструкция|produksiya продукция|redaksiya редакция|kolleksiya коллекция|infeksiya инфекция|' +
    'proporsiya пропорция|porsiya порция|konferensiya конференция|litsenziya лицензия|litsey лицей|ofitser офицер|' +
    'protsent процент|protsess процесс|protsedura процедура|konsert концерт|konsepsiya концепция|konsentratsiya концентрация|' +
    'konsern концерн|potensial потенциал|differensial дифференциал|sotsial социал|sotsiologiya социология|spetsial специал|spetsifik специфик|' +
    'kvarts кварц|shprits шприц|plats плац|blits блиц';
  var DICT = {};
  var DICT_KEYS = [];
  (function () {
    var parts = DICT_SRC.split('|');
    for (var i = 0; i < parts.length; i++) {
      var kv = parts[i].split(' ');
      DICT[kv[0]] = kv[1];
      DICT_KEYS.push(kv[0]);
    }
    DICT_KEYS.sort(function (a, b) { return b.length - a.length; }); // longest first
  })();

  function addDictionary(entries) { // {latinStem: cyrillicStem}
    for (var k in entries) {
      var key = normKey(k);
      if (!DICT.hasOwnProperty(key)) DICT_KEYS.push(key);
      DICT[key] = entries[k];
    }
    DICT_KEYS.sort(function (a, b) { return b.length - a.length; });
  }

  // normalise a Latin word for dictionary lookup
  function normKey(word) {
    var o = '';
    for (var i = 0; i < word.length; i++) {
      var c = latLower(word.charAt(i));
      if (isApos(c)) o += "'";
      else if (c === 'ö' || c === 'ō' || c === 'õ') o += "o'";
      else if (c === 'ğ') o += "g'";
      else if (c === 'ş') o += 'sh';
      else if (c === 'ç') o += 'ch';
      else o += c;
    }
    return o;
  }

  // ---------------------------------------------------------------- Cyrillic → Latin
  function cyrToLatin(text, target, o) {
    o = opts(o);
    var isNew = target === 'new';
    var out = '';
    var n = text.length;
    for (var i = 0; i < n; i++) {
      var c = text.charAt(i);
      if (!isCyr(c)) { out += c; continue; }
      var L = cyrLower(c), up = isCyrUpper(c);
      var P = i > 0 ? text.charAt(i - 1) : '';
      var N = i + 1 < n ? text.charAt(i + 1) : '';
      var r;
      switch (L) {
        case 'е': // е
          r = (!isCyr(P) || isCyrVowel(P) || cyrLower(P) === 'ъ' || cyrLower(P) === 'ь') ? 'ye' : 'e';
          break;
        case 'ц': // ц
          r = isCyrVowel(P) ? 'ts' : 's';
          break;
        case 'ъ': // ъ
          var nl = cyrLower(N);
          if (nl === 'е' || nl === 'ё' || nl === 'ю' || nl === 'я') r = '';
          else if (cyrLower(P) === 'ў' && o.dropHardSignAfterO) r = '';
          else r = o.tutuq;
          break;
        case 'ь': r = ''; break;                                 // ь
        case 'ш': case 'щ': r = isNew ? 'ş' : 'sh'; break;   // ш щ
        case 'ч': r = isNew ? 'ç' : 'ch'; break;                 // ч
        case 'ў': r = isNew ? 'ö' : 'o' + o.okina; break;        // ў
        case 'ғ': r = isNew ? 'ğ' : 'g' + o.okina; break;        // ғ
        case 'с': r = (!isNew && cyrLower(N) === 'ҳ') ? 's' + o.tutuq : 's'; break; // с(+ҳ)
        default: r = C2L[L]; if (r === undefined) r = c;
      }
      out += caseOut(text, i, up, r);
    }
    return out;
  }

  // ---------------------------------------------------------------- Latin → Cyrillic
  function latinToCyrScan(text, source, o, prevCtx) {
    var isNew = source === 'new';
    var out = '';
    var n = text.length;
    var i = 0;
    function prevChar(idx) { return idx > 0 ? text.charAt(idx - 1) : (prevCtx || ''); }
    while (i < n) {
      var c = text.charAt(i);
      if (isApos(c)) {
        var pc = prevChar(i), nc = i + 1 < n ? text.charAt(i + 1) : '';
        if (isLat(pc) && isLat(nc)) out += isLatUpper(pc) ? 'Ъ' : 'ъ';
        else if (isLat(pc) && c === TUTUQ) out += isLatUpper(pc) ? 'Ъ' : 'ъ';
        else out += c;
        i++; continue;
      }
      if (!isLat(c)) { out += c; i++; continue; }
      var L = latLower(c), up = isLatUpper(c);
      var N = i + 1 < n ? text.charAt(i + 1) : '';
      var N2 = i + 2 < n ? text.charAt(i + 2) : '';
      var NL = latLower(N);
      var P = prevChar(i);
      var prevIsLetter = isLat(P);
      var prevIsVowelOrApos = isLatVowel(P) || isApos(P);

      if (L === 'o' && isApos(N)) { out += up ? 'Ў' : 'ў'; i += 2; continue; }
      if (L === 'g' && isApos(N)) { out += up ? 'Ғ' : 'ғ'; i += 2; continue; }
      if (L === 's') {
        if (NL === 'h' && !isNew) { out += up ? 'Ш' : 'ш'; i += 2; continue; }
        if (isApos(N) && latLower(N2) === 'h') { out += up ? 'С' : 'с'; i += 2; continue; }
      }
      if (L === 'c' && NL === 'h') { out += up ? 'Ч' : 'ч'; i += 2; continue; }
      if (L === 'y' && (NL === 'o' || NL === 'u' || NL === 'a' || NL === 'e')) {
        if (NL === 'o' && isApos(N2)) { out += up ? 'Й' : 'й'; i += 1; continue; }
        if (NL === 'e') {
          if (!prevIsLetter || prevIsVowelOrApos) out += up ? 'Е' : 'е';
          else out += (up ? 'Ь' : 'ь') + (up ? 'Е' : 'е');
        } else if (NL === 'o') out += up ? 'Ё' : 'ё';
        else if (NL === 'u') out += up ? 'Ю' : 'ю';
        else out += up ? 'Я' : 'я';
        i += 2; continue;
      }
      if (L === 'e') {
        out += (!prevIsLetter || prevIsVowelOrApos) ? (up ? 'Э' : 'э') : (up ? 'Е' : 'е');
        i++; continue;
      }
      if (L === 't' && NL === 's') {
        var rest = (text.substr(i + 2, 3)).toLowerCase();
        if (rest.indexOf('iya') === 0 || rest.indexOf('ion') === 0) { out += up ? 'Ц' : 'ц'; i += 2; continue; }
        var wordEnds = (i + 2 >= n) || !isLat(text.charAt(i + 2));
        if (o.tsFinal && wordEnds && isLatVowel(P)) { out += up ? 'Ц' : 'ц'; i += 2; continue; }
      }
      var r = L2C[L];
      if (r === undefined) { out += c; i++; continue; }
      out += up ? cyrUpper(r) : r;
      i++;
    }
    return out;
  }

  function latinToCyr(text, source, o) {
    o = opts(o);
    if (!o.dictionary) return latinToCyrScan(text, source, o, '');
    var out = '';
    var n = text.length;
    var i = 0;
    while (i < n) {
      var c = text.charAt(i);
      if (!isLat(c) && !isApos(c)) { out += c; i++; continue; }
      var j = i;
      while (j < n && (isLat(text.charAt(j)) || isApos(text.charAt(j)))) j++;
      var word = text.slice(i, j);
      out += convertWordWithDict(word, source, o);
      i = j;
    }
    return out;
  }

  function convertWordWithDict(word, source, o) {
    var key = normKey(word);
    var hit = null;
    for (var k = 0; k < DICT_KEYS.length; k++) {
      var dk = DICT_KEYS[k];
      if (key.length >= dk.length && key.slice(0, dk.length) === dk) { hit = dk; break; }
    }
    if (!hit) return latinToCyrScan(word, source, o, '');
    // how many source characters does the stem cover? (normKey may expand ö→o', ş→sh …)
    var consumed = 0, built = '';
    while (built.length < hit.length && consumed < word.length) { built += normKey(word.charAt(consumed)); consumed++; }
    var stemSrc = word.slice(0, consumed);
    var rest = word.slice(consumed);
    var value = DICT[hit];
    // casing
    var letters = 0, uppers = 0, firstUpper = false;
    for (var q = 0; q < stemSrc.length; q++) {
      var ch = stemSrc.charAt(q);
      if (isLat(ch)) { letters++; if (isLatUpper(ch)) { uppers++; if (letters === 1) firstUpper = true; } }
    }
    var cyrStem;
    if (letters >= 2 && uppers === letters) cyrStem = upperStr(value);
    else if (firstUpper) cyrStem = upperFirst(value);
    else cyrStem = value;
    var lastSrc = stemSrc.charAt(stemSrc.length - 1);
    return cyrStem + latinToCyrScan(rest, source, o, lastSrc);
  }

  // ---------------------------------------------------------------- Latin 1995 → Latin 2026
  function latToNew(text, o) {
    o = opts(o);
    var out = '';
    var n = text.length, i = 0;
    while (i < n) {
      var c = text.charAt(i), L = latLower(c), up = isLatUpper(c);
      var N = i + 1 < n ? text.charAt(i + 1) : '', NL = latLower(N);
      var N2 = i + 2 < n ? text.charAt(i + 2) : '';
      if (isApos(c)) {
        var pc = i > 0 ? text.charAt(i - 1) : '';
        out += (isLat(pc) && isLat(N)) ? o.tutuq : c;
        i++; continue;
      }
      if (!isLat(c)) { out += c; i++; continue; }
      if (L === 'o' && isApos(N)) { out += up ? 'Ö' : 'ö'; i += 2; continue; }
      if (L === 'g' && isApos(N)) { out += up ? 'Ğ' : 'ğ'; i += 2; continue; }
      if (L === 's' && NL === 'h') { out += up ? 'Ş' : 'ş'; i += 2; continue; }
      if (L === 's' && isApos(N) && latLower(N2) === 'h') { out += c; i += 2; continue; }
      if (L === 'c' && NL === 'h') { out += up ? 'Ç' : 'ç'; i += 2; continue; }
      if (L === 'ō' || L === 'õ') { out += up ? 'Ö' : 'ö'; i++; continue; }
      out += c; i++;
    }
    return out;
  }

  // ---------------------------------------------------------------- Latin 2026 → Latin 1995
  function newToLat(text, o) {
    o = opts(o);
    var out = '';
    var n = text.length, i = 0;
    while (i < n) {
      var c = text.charAt(i), L = latLower(c), up = isLatUpper(c);
      var N = i + 1 < n ? text.charAt(i + 1) : '', NL = latLower(N);
      if (isApos(c)) {
        var pc = i > 0 ? text.charAt(i - 1) : '';
        out += (isLat(pc) && isLat(N)) ? o.tutuq : c;
        i++; continue;
      }
      if (!isLat(c)) { out += c; i++; continue; }
      if (L === 'ö' || L === 'ō' || L === 'õ') { out += (up ? 'O' : 'o') + o.okina; i++; continue; }
      if (L === 'ğ') { out += (up ? 'G' : 'g') + o.okina; i++; continue; }
      if (L === 'ş') { out += caseOut(text, i, up, 'sh'); i++; continue; }
      if (L === 'ç') { out += caseOut(text, i, up, 'ch'); i++; continue; }
      if (L === 's' && NL === 'h') { out += c + o.tutuq; i++; continue; } // Ishoq → Isʼhoq
      out += c; i++;
    }
    return out;
  }

  // ---------------------------------------------------------------- detection
  function detect(text) {
    var cyr = 0, lat = 0, nw = 0, dig = 0;
    var n = text.length;
    for (var i = 0; i < n; i++) {
      var c = text.charAt(i);
      if (isCyr(c)) { cyr++; continue; }
      if (isLat(c)) {
        lat++;
        var L = latLower(c);
        if (L === 'ö' || L === 'ğ' || L === 'ş' || L === 'ç' || L === 'ō' || L === 'õ') nw++;
        var N = i + 1 < n ? text.charAt(i + 1) : '', NL = latLower(N);
        if ((L === 's' || L === 'c') && NL === 'h') dig++;
        if ((L === 'o' || L === 'g') && isApos(N)) dig++;
      }
    }
    if (cyr > lat) return 'cyr';
    if (nw > 0 && nw >= dig) return 'new';
    return 'lat';
  }

  // ---------------------------------------------------------------- URL / e-mail protection
  var SKIP_RE = /(https?:\/\/|www\.)\S+|\S+@\S+\.\S+|@\w+/g;
  function withSkips(text, fn) {
    var out = '', last = 0, m;
    SKIP_RE.lastIndex = 0;
    while ((m = SKIP_RE.exec(text)) !== null) {
      out += fn(text.slice(last, m.index)) + m[0];
      last = m.index + m[0].length;
    }
    return out + fn(text.slice(last));
  }

  // ---------------------------------------------------------------- public API
  function convert(text, from, to, o) {
    text = String(text == null ? '' : text);
    o = opts(o);
    if (from === 'auto') from = detect(text);
    if (from === to) return text;
    var fn;
    if (from === 'cyr' && (to === 'lat' || to === 'new')) fn = function (s) { return cyrToLatin(s, to, o); };
    else if ((from === 'lat' || from === 'new') && to === 'cyr') fn = function (s) { return latinToCyr(s, from, o); };
    else if (from === 'lat' && to === 'new') fn = function (s) { return latToNew(s, o); };
    else if (from === 'new' && to === 'lat') fn = function (s) { return newToLat(s, o); };
    else throw new Error('UzTranslit: unknown direction ' + from + ' -> ' + to);
    return o.skipUrls ? withSkips(text, fn) : fn(text);
  }

  return {
    VERSION: VERSION,
    OKINA: OKINA,
    TUTUQ: TUTUQ,
    SCRIPTS: ['cyr', 'lat', 'new'],
    convert: convert,
    detect: detect,
    cyrToLat: function (t, o) { return convert(t, 'cyr', 'lat', o); },
    cyrToNew: function (t, o) { return convert(t, 'cyr', 'new', o); },
    latToCyr: function (t, o) { return convert(t, 'lat', 'cyr', o); },
    newToCyr: function (t, o) { return convert(t, 'new', 'cyr', o); },
    latToNew: function (t, o) { return convert(t, 'lat', 'new', o); },
    newToLat: function (t, o) { return convert(t, 'new', 'lat', o); },
    addDictionary: addDictionary,
    defaults: DEFAULTS
  };
});
