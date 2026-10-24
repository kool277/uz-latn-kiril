#!/usr/bin/env python3
"""
uztranslit v1.0.0 — Uzbek script converter (Python port of spec/SPEC.md)
Cyrillic (1940) <-> Latin 1995 <-> Latin 2026 (O'RQ-1184: Oʻ→Ö, Gʻ→Ğ, Sh→Ş, Ch→Ç)

    from uztranslit import convert, detect
    convert("Toshkent shahri", "lat", "cyr")      -> "Тошкент шаҳри"
    convert("Toshkent shahri", "lat", "new")      -> "Toşkent şahri"
    convert("Салом", "cyr", "lat")                -> "Salom"

CLI:  python3 uztranslit.py --from auto --to new [file.txt]   (stdin if no file)
Zero dependencies; Python 3.6+ (also runs inside LibreOffice's bundled Python). MIT License.
"""
import re
import sys

VERSION = "1.0.0"
OKINA = "ʻ"   # ʻ  in Oʻ Gʻ
TUTUQ = "ʼ"   # ʼ  tutuq belgisi

CYR_LOWER = "абвгдеёжзийклмнопрстуфхцчшщъыьэюяўқғҳ"
CYR_UPPER = "АБВГДЕЁЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯЎҚҒҲ"
LAT_LOWER = "abcdefghijklmnopqrstuvwxyzöğşçōõ"
LAT_UPPER = "ABCDEFGHIJKLMNOPQRSTUVWXYZÖĞŞÇŌÕ"
APOS = "'ʻʼ‘’`´"
CYR_VOWELS = "аеёиоуэюяўы"
LAT_VOWELS = "aeiouöōõ"

_cyr_lower_map = dict(zip(CYR_UPPER, CYR_LOWER))
_cyr_upper_map = dict(zip(CYR_LOWER, CYR_UPPER))
_lat_lower_map = dict(zip(LAT_UPPER, LAT_LOWER))
_lat_upper_map = dict(zip(LAT_LOWER, LAT_UPPER))


def is_cyr(c): return bool(c) and (c in CYR_LOWER or c in CYR_UPPER)
def is_cyr_upper(c): return bool(c) and c in CYR_UPPER
def cyr_lower(c): return _cyr_lower_map.get(c, c)
def cyr_upper(c): return _cyr_upper_map.get(c, c)
def is_cyr_vowel(c): return bool(c) and cyr_lower(c) in CYR_VOWELS
def is_lat(c): return bool(c) and (c in LAT_LOWER or c in LAT_UPPER)
def is_lat_upper(c): return bool(c) and c in LAT_UPPER
def lat_lower(c): return _lat_lower_map.get(c, c)
def lat_upper(c): return _lat_upper_map.get(c, c)
def is_lat_vowel(c): return bool(c) and lat_lower(c) in LAT_VOWELS
def is_apos(c): return bool(c) and c in APOS
def is_letter(c): return is_cyr(c) or is_lat(c)
def is_upper_letter(c): return is_cyr_upper(c) or is_lat_upper(c)
def upper_str(s): return "".join(lat_upper(cyr_upper(ch)) for ch in s)
def upper_first(s): return (lat_upper(cyr_upper(s[0])) + s[1:]) if s else s


def _next_letter_is_upper(text, i):
    j = i + 1
    if j < len(text) and is_apos(text[j]):
        j += 1
    if j < len(text) and is_letter(text[j]):
        return is_upper_letter(text[j])
    k = i - 1
    if k >= 0 and is_apos(text[k]):
        k -= 1
    if k >= 0 and is_letter(text[k]):
        return is_upper_letter(text[k])
    return False


def _case_out(text, i, src_upper, out):
    if not src_upper or not out:
        return out
    if len(out) == 1:
        return upper_str(out)
    return upper_str(out) if _next_letter_is_upper(text, i) else upper_first(out)


DEFAULTS = {
    "okina": OKINA,
    "tutuq": TUTUQ,
    "dropHardSignAfterO": True,
    "tsFinal": True,
    "dictionary": True,
    "skipUrls": True,
}


def _opts(o):
    r = dict(DEFAULTS)
    if o:
        for k, v in o.items():
            if k in r and v is not None:
                r[k] = v
    return r


C2L = {
    "а": "a", "б": "b", "в": "v", "г": "g", "д": "d", "ж": "j", "з": "z", "и": "i", "й": "y", "к": "k",
    "л": "l", "м": "m", "н": "n", "о": "o", "п": "p", "р": "r", "т": "t", "у": "u", "ф": "f", "х": "x",
    "қ": "q", "ҳ": "h", "э": "e", "ы": "i", "ё": "yo", "ю": "yu", "я": "ya",
}
L2C = {
    "a": "а", "b": "б", "d": "д", "f": "ф", "g": "г", "h": "ҳ", "i": "и", "j": "ж", "k": "к", "l": "л",
    "m": "м", "n": "н", "o": "о", "p": "п", "q": "қ", "r": "р", "s": "с", "t": "т", "u": "у", "v": "в",
    "x": "х", "y": "й", "z": "з", "c": "ц", "w": "в",
    "ö": "ў", "ō": "ў", "õ": "ў", "ğ": "ғ", "ş": "ш", "ç": "ч",
}

_DICT_SRC = (
    "obyekt объект|subyekt субъект|adyutant адъютант|inyeksiya инъекция|konyunktura конъюнктура|"
    "kompyuter компьютер|intervyu интервью|premyera премьера|batalyon батальон|bulyon бульон|medalyon медальон|"
    "shampinyon шампиньон|kanyon каньон|senyor сеньор|tatyana татьяна|ilya илья|nyuton ньютон|"
    "yoga йога|yogurt йогурт|york йорк|"
    "sirk цирк|sement цемент|senzura цензура|sentner центнер|sentr центр|sex цех|sikl цикл|silindr цилиндр|"
    "sisterna цистерна|sitata цитата|sitrus цитрус|sellofan целлофан|sellyuloza целлюлоза|selsiy цельсий|"
    "seremoniya церемония|sivilizatsiya цивилизация|sianid цианид|sink цинк|sirkul циркуль|sokol цоколь|sunami цунами|sitadel цитадель|sirka сирка|sinkop синкоп|sinkret синкрет|sinklinal синклинал|"
    "leksiya лекция|aksiya акция|funksiya функция|seksiya секция|fraksiya фракция|reaksiya реакция|sanksiya санкция|"
    "konstruksiya конструкция|produksiya продукция|redaksiya редакция|kolleksiya коллекция|infeksiya инфекция|"
    "proporsiya пропорция|porsiya порция|konferensiya конференция|litsenziya лицензия|litsey лицей|ofitser офицер|"
    "protsent процент|protsess процесс|protsedura процедура|konsert концерт|konsepsiya концепция|konsentratsiya концентрация|"
    "konsern концерн|potensial потенциал|differensial дифференциал|sotsial социал|sotsiologiya социология|spetsial специал|spetsifik специфик|"
    "kvarts кварц|shprits шприц|plats плац|blits блиц"
)
DICT = {}
for _p in _DICT_SRC.split("|"):
    _k, _v = _p.split(" ")
    DICT[_k] = _v
DICT_KEYS = sorted(DICT, key=len, reverse=True)


def add_dictionary(entries):
    """Extend the Latin→Cyrillic stem dictionary: {"latinStem": "cyrillicStem"}"""
    global DICT_KEYS
    for k, v in entries.items():
        DICT[norm_key(k)] = v
    DICT_KEYS = sorted(DICT, key=len, reverse=True)


def norm_key(word):
    o = []
    for ch in word:
        c = lat_lower(ch)
        if is_apos(c):
            o.append("'")
        elif c in "öōõ":
            o.append("o'")
        elif c == "ğ":
            o.append("g'")
        elif c == "ş":
            o.append("sh")
        elif c == "ç":
            o.append("ch")
        else:
            o.append(c)
    return "".join(o)


# ----------------------------------------------------------------- Cyrillic -> Latin
def _cyr_to_latin(text, target, o):
    is_new = target == "new"
    out = []
    n = len(text)
    for i, c in enumerate(text):
        if not is_cyr(c):
            out.append(c)
            continue
        L = cyr_lower(c)
        up = is_cyr_upper(c)
        P = text[i - 1] if i > 0 else ""
        N = text[i + 1] if i + 1 < n else ""
        if L == "е":
            r = "ye" if (not is_cyr(P) or is_cyr_vowel(P) or cyr_lower(P) in "ъь") else "e"
        elif L == "ц":
            r = "ts" if is_cyr_vowel(P) else "s"
        elif L == "ъ":
            nl = cyr_lower(N)
            if nl and nl in "еёюя":
                r = ""
            elif cyr_lower(P) == "ў" and o["dropHardSignAfterO"]:
                r = ""
            else:
                r = o["tutuq"]
        elif L == "ь":
            r = ""
        elif L in "шщ":
            r = "ş" if is_new else "sh"
        elif L == "ч":
            r = "ç" if is_new else "ch"
        elif L == "ў":
            r = "ö" if is_new else "o" + o["okina"]
        elif L == "ғ":
            r = "ğ" if is_new else "g" + o["okina"]
        elif L == "с":
            r = "s" + o["tutuq"] if (not is_new and cyr_lower(N) == "ҳ") else "s"
        else:
            r = C2L.get(L, c)
        out.append(_case_out(text, i, up, r))
    return "".join(out)


# ----------------------------------------------------------------- Latin -> Cyrillic
def _latin_to_cyr_scan(text, source, o, prev_ctx=""):
    is_new = source == "new"
    out = []
    n = len(text)
    i = 0

    def prev_char(idx):
        return text[idx - 1] if idx > 0 else prev_ctx

    while i < n:
        c = text[i]
        if is_apos(c):
            pc = prev_char(i)
            nc = text[i + 1] if i + 1 < n else ""
            if is_lat(pc) and is_lat(nc):
                out.append("Ъ" if is_lat_upper(pc) else "ъ")
            elif is_lat(pc) and c == TUTUQ:
                out.append("Ъ" if is_lat_upper(pc) else "ъ")
            else:
                out.append(c)
            i += 1
            continue
        if not is_lat(c):
            out.append(c)
            i += 1
            continue
        L = lat_lower(c)
        up = is_lat_upper(c)
        N = text[i + 1] if i + 1 < n else ""
        N2 = text[i + 2] if i + 2 < n else ""
        NL = lat_lower(N)
        P = prev_char(i)
        prev_is_letter = is_lat(P)
        prev_is_vowel_or_apos = is_lat_vowel(P) or is_apos(P)

        if L == "o" and is_apos(N):
            out.append("Ў" if up else "ў"); i += 2; continue
        if L == "g" and is_apos(N):
            out.append("Ғ" if up else "ғ"); i += 2; continue
        if L == "s":
            if NL == "h" and not is_new:
                out.append("Ш" if up else "ш"); i += 2; continue
            if is_apos(N) and lat_lower(N2) == "h":
                out.append("С" if up else "с"); i += 2; continue
        if L == "c" and NL == "h":
            out.append("Ч" if up else "ч"); i += 2; continue
        if L == "y" and NL in ("o", "u", "a", "e"):
            if NL == "o" and is_apos(N2):
                out.append("Й" if up else "й"); i += 1; continue
            if NL == "e":
                if not prev_is_letter or prev_is_vowel_or_apos:
                    out.append("Е" if up else "е")
                else:
                    out.append(("Ь" if up else "ь") + ("Е" if up else "е"))
            elif NL == "o":
                out.append("Ё" if up else "ё")
            elif NL == "u":
                out.append("Ю" if up else "ю")
            else:
                out.append("Я" if up else "я")
            i += 2; continue
        if L == "e":
            if not prev_is_letter or prev_is_vowel_or_apos:
                out.append("Э" if up else "э")
            else:
                out.append("Е" if up else "е")
            i += 1; continue
        if L == "t" and NL == "s":
            rest = text[i + 2:i + 5].lower()
            if rest.startswith("iya") or rest.startswith("ion"):
                out.append("Ц" if up else "ц"); i += 2; continue
            word_ends = (i + 2 >= n) or not is_lat(text[i + 2])
            if o["tsFinal"] and word_ends and is_lat_vowel(P):
                out.append("Ц" if up else "ц"); i += 2; continue
        r = L2C.get(L)
        if r is None:
            out.append(c)
        else:
            out.append(cyr_upper(r) if up else r)
        i += 1
    return "".join(out)


def _convert_word_with_dict(word, source, o):
    key = norm_key(word)
    hit = None
    for dk in DICT_KEYS:
        if key.startswith(dk):
            hit = dk
            break
    if hit is None:
        return _latin_to_cyr_scan(word, source, o, "")
    consumed, built = 0, ""
    while len(built) < len(hit) and consumed < len(word):
        built += norm_key(word[consumed])
        consumed += 1
    stem_src, rest = word[:consumed], word[consumed:]
    value = DICT[hit]
    letters = [ch for ch in stem_src if is_lat(ch)]
    uppers = [ch for ch in letters if is_lat_upper(ch)]
    if len(letters) >= 2 and len(uppers) == len(letters):
        cyr_stem = upper_str(value)
    elif letters and is_lat_upper(letters[0]):
        cyr_stem = upper_first(value)
    else:
        cyr_stem = value
    return cyr_stem + _latin_to_cyr_scan(rest, source, o, stem_src[-1] if stem_src else "")


def _latin_to_cyr(text, source, o):
    if not o["dictionary"]:
        return _latin_to_cyr_scan(text, source, o, "")
    out = []
    n = len(text)
    i = 0
    while i < n:
        c = text[i]
        if not is_lat(c) and not is_apos(c):
            out.append(c); i += 1; continue
        j = i
        while j < n and (is_lat(text[j]) or is_apos(text[j])):
            j += 1
        out.append(_convert_word_with_dict(text[i:j], source, o))
        i = j
    return "".join(out)


# ----------------------------------------------------------------- Latin 1995 -> Latin 2026
def _lat_to_new(text, o):
    out = []
    n = len(text)
    i = 0
    while i < n:
        c = text[i]
        L = lat_lower(c)
        up = is_lat_upper(c)
        N = text[i + 1] if i + 1 < n else ""
        NL = lat_lower(N)
        N2 = text[i + 2] if i + 2 < n else ""
        if is_apos(c):
            pc = text[i - 1] if i > 0 else ""
            out.append(o["tutuq"] if (is_lat(pc) and is_lat(N)) else c)
            i += 1; continue
        if not is_lat(c):
            out.append(c); i += 1; continue
        if L == "o" and is_apos(N):
            out.append("Ö" if up else "ö"); i += 2; continue
        if L == "g" and is_apos(N):
            out.append("Ğ" if up else "ğ"); i += 2; continue
        if L == "s" and NL == "h":
            out.append("Ş" if up else "ş"); i += 2; continue
        if L == "s" and is_apos(N) and lat_lower(N2) == "h":
            out.append(c); i += 2; continue
        if L == "c" and NL == "h":
            out.append("Ç" if up else "ç"); i += 2; continue
        if L in "ōõ":
            out.append("Ö" if up else "ö"); i += 1; continue
        out.append(c)
        i += 1
    return "".join(out)


# ----------------------------------------------------------------- Latin 2026 -> Latin 1995
def _new_to_lat(text, o):
    out = []
    n = len(text)
    i = 0
    while i < n:
        c = text[i]
        L = lat_lower(c)
        up = is_lat_upper(c)
        N = text[i + 1] if i + 1 < n else ""
        NL = lat_lower(N)
        if is_apos(c):
            pc = text[i - 1] if i > 0 else ""
            out.append(o["tutuq"] if (is_lat(pc) and is_lat(N)) else c)
            i += 1; continue
        if not is_lat(c):
            out.append(c); i += 1; continue
        if L in "öōõ":
            out.append(("O" if up else "o") + o["okina"]); i += 1; continue
        if L == "ğ":
            out.append(("G" if up else "g") + o["okina"]); i += 1; continue
        if L == "ş":
            out.append(_case_out(text, i, up, "sh")); i += 1; continue
        if L == "ç":
            out.append(_case_out(text, i, up, "ch")); i += 1; continue
        if L == "s" and NL == "h":
            out.append(c + o["tutuq"]); i += 1; continue
        out.append(c)
        i += 1
    return "".join(out)


# ----------------------------------------------------------------- detection
def detect(text):
    cyr = lat = nw = dig = 0
    n = len(text)
    for i, c in enumerate(text):
        if is_cyr(c):
            cyr += 1
            continue
        if is_lat(c):
            lat += 1
            L = lat_lower(c)
            if L in "öğşçōõ":
                nw += 1
            N = text[i + 1] if i + 1 < n else ""
            NL = lat_lower(N)
            if L in "sc" and NL == "h":
                dig += 1
            if L in "og" and is_apos(N):
                dig += 1
    if cyr > lat:
        return "cyr"
    if nw > 0 and nw >= dig:
        return "new"
    return "lat"


# SPEC §5.6 is the JavaScript expression /(https?:\/\/|www\.)\S+|\S+@\S+\.\S+|@\w+/g with JavaScript's classes:
# \s is this fixed set and \w is ASCII only (Python's \s and \w would also take Cyrillic letters, ʻ, U+0085 …).
_JS_SPACE = "\t\n\x0b\x0c\r \u00a0\u1680\u2000-\u200a\u2028\u2029\u202f\u205f\u3000\ufeff"
_NS = "[^" + _JS_SPACE + "]"
_SKIP_RE = re.compile("(?:https?://|www\\.)%s+|%s+@%s+\\.%s+|@[A-Za-z0-9_]+" % (_NS, _NS, _NS, _NS))


def _with_skips(text, fn):
    out = []
    last = 0
    for m in _SKIP_RE.finditer(text):
        out.append(fn(text[last:m.start()]))
        out.append(m.group(0))
        last = m.end()
    out.append(fn(text[last:]))
    return "".join(out)


# ----------------------------------------------------------------- public API
def convert(text, src, dst, options=None):
    """Convert text between 'cyr', 'lat', 'new'. src may be 'auto'."""
    text = "" if text is None else str(text)
    o = _opts(options)
    if src == "auto":
        src = detect(text)
    if src == dst:
        return text
    if src == "cyr" and dst in ("lat", "new"):
        fn = lambda s: _cyr_to_latin(s, dst, o)
    elif src in ("lat", "new") and dst == "cyr":
        fn = lambda s: _latin_to_cyr(s, src, o)
    elif src == "lat" and dst == "new":
        fn = lambda s: _lat_to_new(s, o)
    elif src == "new" and dst == "lat":
        fn = lambda s: _new_to_lat(s, o)
    else:
        raise ValueError("uztranslit: unknown direction %s -> %s" % (src, dst))
    return _with_skips(text, fn) if o["skipUrls"] else fn(text)


def cyr_to_lat(t, o=None): return convert(t, "cyr", "lat", o)
def cyr_to_new(t, o=None): return convert(t, "cyr", "new", o)
def lat_to_cyr(t, o=None): return convert(t, "lat", "cyr", o)
def new_to_cyr(t, o=None): return convert(t, "new", "cyr", o)
def lat_to_new(t, o=None): return convert(t, "lat", "new", o)
def new_to_lat(t, o=None): return convert(t, "new", "lat", o)


def _main(argv):
    import argparse
    ap = argparse.ArgumentParser(description="Uzbek script converter (cyr / lat / new)")
    ap.add_argument("--from", dest="src", default="auto", choices=["auto", "cyr", "lat", "new"])
    ap.add_argument("--to", dest="dst", required=True, choices=["cyr", "lat", "new"])
    ap.add_argument("--ascii", action="store_true", help="use ' instead of ʻ/ʼ")
    ap.add_argument("-o", "--output", help="write result to file instead of stdout")
    ap.add_argument("file", nargs="?", help="input file (UTF-8); stdin if omitted")
    a = ap.parse_args(argv)
    data = open(a.file, encoding="utf-8").read() if a.file else sys.stdin.read()
    o = {"okina": "'", "tutuq": "'"} if a.ascii else None
    res = convert(data, a.src, a.dst, o)
    if a.output:
        with open(a.output, "w", encoding="utf-8") as f:
            f.write(res)
    else:
        sys.stdout.write(res)


if __name__ == "__main__":
    _main(sys.argv[1:])
