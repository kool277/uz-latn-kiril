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
    "yod йод|yoga йога|yogurt йогурт|york йорк|yota йота|"
    "sirk цирк|sement цемент|senzura цензура|sentner центнер|sentr центр|sex цех|sikl цикл|silindr цилиндр|"
    "sisterna цистерна|sitata цитата|sitrus цитрус|sellofan целлофан|sellyuloza целлюлоза|selsiy цельсий|"
    "seremoniya церемония|sivilizatsiya цивилизация|sianid цианид|sink цинк|sirkul циркуль|sokol цоколь|sunami цунами|sitadel цитадель|"
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



# ---------------------------------------------------------------------------------------------
#  LibreOffice UNO glue (appended after the core by tools/build_oxt.py -> uztranslit_lo.py)
#  Menu: Tools > UzTranslit > ...   (Writer, Calc, Impress, Draw). Selection first, else whole document.
#  Each paragraph is converted as one string, so a word split across differently formatted portions keeps its
#  context, and the result is split back over the portions, which keep their formatting. "Auto" detects the
#  script once per run. UZT_QUIET=1 in soffice's environment: no message boxes (unattended runs, tests).
# ---------------------------------------------------------------------------------------------
import os  # noqa: E402

import uno  # noqa: E402
from com.sun.star.awt.MessageBoxType import INFOBOX, WARNINGBOX, QUERYBOX  # noqa: E402
from com.sun.star.awt.MessageBoxButtons import BUTTONS_OK, BUTTONS_YES_NO  # noqa: E402

CELL_STRING = 4  # com.sun.star.sheet.CellFlags.STRING
_OBJECT = "\ufffc"
# portions that are invisible marks (may sit inside a word); every other non-text portion is a boundary
_INVISIBLE = {"Bookmark", "ReferenceMark", "DocumentIndexMark", "Redline", "SoftPageBreak", "InContentMetadata",
              "AnnotationEnd", "ContentControl"}


# Writer text positions are live: they move with edits (one that sits exactly where text is inserted moves past it),
# and Writer text is rewritten front to back. The text of cells and shapes (EditEngine) is addressed by plain
# indices, which go stale when earlier text changes length: it is rewritten back to front. Set per run by _run().
_writer_text = [True]


def _quiet():
    return os.environ.get("UZT_QUIET") == "1"


def _msg(doc, text, kind=INFOBOX, buttons=BUTTONS_OK):
    if _quiet():
        return 0
    try:
        ctx = uno.getComponentContext()
        tk = ctx.ServiceManager.createInstanceWithContext("com.sun.star.awt.Toolkit", ctx)
        win = doc.CurrentController.Frame.ContainerWindow
        box = tk.createMessageBox(win, kind, buttons, "UzTranslit", text)
        return box.execute()
    except Exception:
        return 0


# the options of the current run: /uz.jaybi.UzTranslit/Settings (UzTranslit.xcs in the extension), read by _run()
_options = [None]
SETTING_KEYS = ("Ascii", "Dictionary", "KeepHardSignAfterO", "TsFinal", "SkipUrls")


def _conv(s, f, t):
    return convert(s, f, t, _options[0])


def _config(update=False):
    ctx = uno.getComponentContext()
    cp = ctx.ServiceManager.createInstanceWithContext("com.sun.star.configuration.ConfigurationProvider", ctx)
    arg = uno.createUnoStruct("com.sun.star.beans.PropertyValue")
    arg.Name, arg.Value = "nodepath", "/uz.jaybi.UzTranslit/Settings"
    kind = "ConfigurationUpdateAccess" if update else "ConfigurationAccess"
    return cp.createInstanceWithArguments("com.sun.star.configuration." + kind, (arg,))


def _load_settings():
    """The saved settings as engine options (the defaults when they cannot be read)."""
    try:
        c = _config()
        o = {"dictionary": bool(c.Dictionary), "dropHardSignAfterO": not c.KeepHardSignAfterO,
             "tsFinal": bool(c.TsFinal), "skipUrls": bool(c.SkipUrls)}
        if c.Ascii:
            o["okina"] = o["tutuq"] = "'"
        _options[0] = o
    except Exception:
        _options[0] = None
    return _options[0]


def _resolve(f, sample):
    """'auto' becomes the script of the text this run converts: one decision for the whole run."""
    return detect(sample[:200000]) if f == "auto" else f


def _xtext(xt, f, t):
    """Every paragraph of an XText (and the text tables inside Writer text)."""
    cnt = 0
    if xt is None:
        return 0
    en = xt.createEnumeration()
    while en.hasMoreElements():
        el = en.nextElement()
        if el.supportsService("com.sun.star.text.TextTable"):
            for name in el.getCellNames():
                cnt += _xtext(el.getCellByName(name), f, t)
        elif el.supportsService("com.sun.star.text.Paragraph"):
            cnt += _paragraph(el, f, t)
    return cnt


_SPACE = re.compile("[" + _JS_SPACE + "]")


def _split(texts, f, t):
    """Converts "".join(texts) as one string and splits the result back over the pieces (None when nothing changes):
    a word half bold, half plain still converts as one word, and the joined pieces are always exactly the conversion
    of the whole. A cut lands where the conversion of the text before it ends. No rule looks across whitespace, so
    only the part of the word up to the cut is converted again, and a paragraph of thousands of portions stays
    linear. Where a rule looks across a cut inside a word, a letter may move to the next piece."""
    src = "".join(texts)
    if f == "auto":
        f = detect(src)
    out = _conv(src, f, t)
    if out == src:
        return None
    pieces, prev, b, safe, safe_len = [], 0, 0, 0, 0
    for i, s in enumerate(texts):
        b += len(s)
        if i == len(texts) - 1:
            cur = len(out)
        else:
            w = b  # last whitespace before the cut, if after the last one known
            while w > safe and not _SPACE.match(src, w - 1):
                w -= 1
            if w > safe:
                safe_len += len(_conv(src[safe:w], f, t))
                safe = w
            cur = min(safe_len + (len(_conv(src[safe:b], f, t)) if b > safe else 0), len(out))
        cur = max(cur, prev)
        pieces.append(out[prev:cur])
        prev = cur
    return pieces


def _paragraph(par, f, t):
    portions, texts, cnt = [], [], 0
    pe = par.createEnumeration()
    while pe.hasMoreElements():
        por = pe.nextElement()
        try:
            kind = por.TextPortionType
        except Exception:
            kind = ""  # text of cells and shapes has no portion types
        if kind in ("Text", ""):
            portions.append(por)
            texts.append(por.getString())
        else:
            portions.append(None)
            texts.append("" if kind in _INVISIBLE or kind == "Annotation" else _OBJECT)
            if kind == "Annotation":
                cnt += _annotation(por, f, t)
    pieces = _split(texts, f, t) if portions else None
    if pieces is None:
        return cnt
    items = list(zip(portions, texts, pieces))
    for por, s, new in (items if _writer_text[0] else reversed(items)):
        if por is not None and new != s:
            _replace_portion(por, new)
            cnt += 1
    return cnt


def _annotation(por, f, t):
    """A Writer comment: its text is converted, its author and date are not."""
    try:
        fld = por.TextField
        s = fld.Content
        if s:
            conv = _conv(s, f, t)
            if conv != s:
                fld.Content = conv
                return 1
    except Exception:
        pass
    return 0


def _replace_portion(por, conv):
    """The new text goes where it takes the portion's own attributes, then the old text goes: no attribute is copied,
    which keeps every one of them and is 10x faster than saving and restoring them. Writer: text added where a portion
    ends takes the neighbour's attributes, so the new text goes in after the first character and the old characters
    around it are removed; a hyperlink does not grow over text added at its end, so a link gets its address back if it
    lost it. Cells and shapes: text added at the end of a portion takes its attributes, and the portion's old range
    still holds the old text."""
    xt = por.getText()
    if not _writer_text[0]:
        xt.insertString(xt.createTextCursorByRange(por.getEnd()), conv, False)
        xt.createTextCursorByRange(por).setString("")
        return
    try:
        link = (por.HyperLinkURL, por.HyperLinkTarget, por.HyperLinkName)
    except Exception:
        link = ("", "", "")
    cur = xt.createTextCursorByRange(por.getStart())
    cur.goRight(1, False)
    xt.insertString(cur, conv, False)  # the cursor moves on past the new text
    cur.gotoRange(por.getEnd(), True)
    cur.setString("")  # the old text after the new
    cur = xt.createTextCursorByRange(por.getStart())
    cur.goRight(1, True)
    cur.setString("")  # the old first character
    if link[0]:
        cur = xt.createTextCursorByRange(por)
        if cur.HyperLinkURL != link[0]:
            cur.HyperLinkURL, cur.HyperLinkTarget, cur.HyperLinkName = link


def _writer(doc, f, t):
    cnt = 0
    ranges = []
    try:
        sel = doc.CurrentController.getSelection()
        if sel is not None and sel.supportsService("com.sun.star.text.TextRanges"):
            ranges = [sel.getByIndex(i) for i in range(sel.getCount()) if sel.getByIndex(i).getString()]
    except Exception:
        pass
    if ranges:
        f = _resolve(f, "\n".join(r.getString() for r in ranges))
        for rng in ranges:
            cnt += _xtext(rng.getText().createTextCursorByRange(rng), f, t)
        return cnt, f
    f = _resolve(f, doc.getText().getString())
    cnt += _xtext(doc.getText(), f, t)
    for getter in ("getTextFrames", "getFootnotes", "getEndnotes"):
        try:
            coll = getattr(doc, getter)()
            for i in range(coll.getCount()):
                cnt += _xtext(coll.getByIndex(i), f, t)
        except Exception:
            pass
    try:
        styles = doc.getStyleFamilies().getByName("PageStyles")
        for i in range(styles.getCount()):
            ps = styles.getByIndex(i)
            if ps.HeaderIsOn:
                cnt += _xtext(ps.HeaderText, f, t)
                if not ps.HeaderIsShared:
                    cnt += _xtext(ps.HeaderTextLeft, f, t)
                if not ps.FirstIsShared:
                    cnt += _xtext(ps.HeaderTextFirst, f, t)
            if ps.FooterIsOn:
                cnt += _xtext(ps.FooterText, f, t)
                if not ps.FooterIsShared:
                    cnt += _xtext(ps.FooterTextLeft, f, t)
                if not ps.FirstIsShared:
                    cnt += _xtext(ps.FooterTextFirst, f, t)
    except Exception:
        pass
    return cnt, f


def _text_cells(rng):
    en = rng.queryContentCells(CELL_STRING).getCells().createEnumeration()
    while en.hasMoreElements():
        yield en.nextElement()


def _cell_range(rng, f, t):
    cnt = 0
    for c in _text_cells(rng):
        cnt += _xtext(c, f, t)  # paragraph by paragraph: rich text in a cell keeps its formatting
    return cnt + _comments(rng, f, t)


def _comments(rng, f, t):
    """Cell comments inside the range (their authors are not touched)."""
    cnt = 0
    try:
        a_ = rng.getRangeAddress()
        anns = rng.getSpreadsheet().getAnnotations()
        for i in range(anns.getCount()):
            a = anns.getByIndex(i)
            p = a.getPosition()
            if a_.StartColumn <= p.Column <= a_.EndColumn and a_.StartRow <= p.Row <= a_.EndRow:
                s = a.getString()
                conv = _conv(s, f, t)
                if conv != s:
                    a.setString(conv)
                    cnt += 1
    except Exception:
        pass
    return cnt


def _calc(doc, f, t):
    sel = doc.CurrentSelection
    targets = []
    if sel.supportsService("com.sun.star.sheet.SheetCellRanges"):
        targets = [sel.getByIndex(i) for i in range(sel.getCount())]
    elif sel.supportsService("com.sun.star.sheet.SheetCellRange"):
        targets = [sel]
        single = sel.getRows().getCount() == 1 and sel.getColumns().getCount() == 1
        if single and _msg(doc, "Convert the whole sheet? (No = only the selected cell)", QUERYBOX, BUTTONS_YES_NO) == 2:
            cur = doc.CurrentController.getActiveSheet().createCursor()
            cur.gotoStartOfUsedArea(False)
            cur.gotoEndOfUsedArea(True)
            targets = [cur]
    sample = []
    for rng in targets:
        for c in _text_cells(rng):
            sample.append(c.getString())
            if sum(map(len, sample)) > 200000:
                break
    f = _resolve(f, "\n".join(sample))
    return sum(_cell_range(rng, f, t) for rng in targets), f


def _shapes_text(container):
    out = []
    for i in range(container.getCount()):
        shp = container.getByIndex(i)
        if shp.supportsService("com.sun.star.drawing.GroupShape"):
            out.append(_shapes_text(shp))
        elif shp.supportsService("com.sun.star.drawing.Text"):
            out.append(shp.getString())
    return "\n".join(out)


def _shapes(container, f, t):
    cnt = 0
    for i in range(container.getCount()):
        shp = container.getByIndex(i)
        if shp.supportsService("com.sun.star.drawing.GroupShape"):
            cnt += _shapes(shp, f, t)
        elif shp.supportsService("com.sun.star.drawing.TableShape"):
            model = shp.Model
            for r in range(model.RowCount):
                for c in range(model.ColumnCount):
                    cnt += _xtext(model.getCellByPosition(c, r), f, t)
        elif shp.supportsService("com.sun.star.drawing.Text"):
            cnt += _xtext(shp, f, t)
    return cnt


def _draw(doc, f, t):
    cnt = 0
    pages = doc.getDrawPages()
    f = _resolve(f, "\n".join(_shapes_text(pages.getByIndex(i)) for i in range(pages.getCount())))
    for i in range(pages.getCount()):
        pg = pages.getByIndex(i)
        cnt += _shapes(pg, f, t)
        try:
            np = pg.getNotesPage()
            if np is not None:
                cnt += _shapes(np, f, t)
        except Exception:
            pass
    return cnt, f


def _run(f, t):
    doc = XSCRIPTCONTEXT.getDocument()  # noqa: F821 (provided by the LibreOffice script context)
    if doc is None:
        return
    if doc.supportsService("com.sun.star.text.TextDocument"):
        kind, fn = "writer", _writer
    elif doc.supportsService("com.sun.star.sheet.SpreadsheetDocument"):
        kind, fn = "calc", _calc
    elif doc.supportsService("com.sun.star.drawing.DrawingDocument") or doc.supportsService("com.sun.star.presentation.PresentationDocument"):
        kind, fn = "draw", _draw
    else:
        _msg(doc, "Unsupported document type", WARNINGBOX)
        return
    _writer_text[0] = kind == "writer"
    _load_settings()
    # one undo step for the whole run, and no layout after every change (that alone makes long paragraphs 30x
    # slower); tracked changes would keep every old word next to its conversion, formulas need not recalculate per cell
    um = doc.getUndoManager()
    um.enterUndoContext("UzTranslit")
    doc.lockControllers()
    rec_was = doc.RecordChanges if kind == "writer" else None
    calc_was = doc.isAutomaticCalculationEnabled() if kind == "calc" else None
    try:
        if kind == "writer":
            doc.RecordChanges = False
        if kind == "calc":
            doc.enableAutomaticCalculation(False)
        cnt, f = fn(doc, f, t)
    finally:
        if kind == "writer":
            doc.RecordChanges = rec_was
        if kind == "calc":
            doc.enableAutomaticCalculation(calc_was)
        doc.unlockControllers()
        um.leaveUndoContext()
    _msg(doc, "%d fragment(s) converted (%s -> %s)" % (cnt, f, t))


def cyr_to_lat(*a): _run("cyr", "lat")
def cyr_to_new(*a): _run("cyr", "new")
def lat_to_cyr(*a): _run("lat", "cyr")
def new_to_cyr(*a): _run("new", "cyr")
def lat_to_new(*a): _run("lat", "new")
def new_to_lat(*a): _run("new", "lat")
def auto_to_new(*a): _run("auto", "new")
def auto_to_lat(*a): _run("auto", "lat")
def auto_to_cyr(*a): _run("auto", "cyr")


_TEXTS = {
    "title": {"en": "UzTranslit settings", "uz": "UzTranslit sozlamalari", "ru": "Настройки UzTranslit"},
    "Ascii": {"en": "Plain apostrophe (') instead of ʻ and ʼ", "uz": "Oddiy apostrof (') — ʻ va ʼ oʻrniga",
              "ru": "Простой апостроф (') вместо ʻ и ʼ"},
    "Dictionary": {"en": "Loanword dictionary (obyekt → объект, kompyuter → компьютер)",
                   "uz": "Oʻzlashma soʻzlar lugʻati (obyekt → объект, kompyuter → компьютер)",
                   "ru": "Словарь заимствований (obyekt → объект, kompyuter → компьютер)"},
    "KeepHardSignAfterO": {"en": "Keep ъ after ў as ʼ (мўъжиза → moʻʼjiza)", "uz": "ў dan keyingi ъ ʼ boʻlib qolsin (мўъжиза → moʻʼjiza)",
                           "ru": "Сохранять ъ после ў как ʼ (мўъжиза → moʻʼjiza)"},
    "TsFinal": {"en": "Word-final ts becomes ц (Latin to Cyrillic)", "uz": "Soʻz oxiridagi ts → ц (lotindan kirillga)",
                "ru": "ts в конце слова → ц (из латиницы в кириллицу)"},
    "SkipUrls": {"en": "Leave web addresses and e-mail addresses as they are", "uz": "Sayt va e-pochta manzillari oʻzgarmasin",
                 "ru": "Не менять адреса сайтов и электронной почты"},
    "ok": {"en": "OK", "uz": "OK", "ru": "OK"},
    "cancel": {"en": "Cancel", "uz": "Bekor qilish", "ru": "Отмена"},
}


def _lang():
    try:
        ctx = uno.getComponentContext()
        cp = ctx.ServiceManager.createInstanceWithContext("com.sun.star.configuration.ConfigurationProvider", ctx)
        arg = uno.createUnoStruct("com.sun.star.beans.PropertyValue")
        arg.Name, arg.Value = "nodepath", "/org.openoffice.Setup/L10N"
        loc = cp.createInstanceWithArguments("com.sun.star.configuration.ConfigurationAccess", (arg,)).ooLocale.lower()
    except Exception:
        loc = ""
    return "uz" if loc.startswith("uz") else "ru" if loc.startswith("ru") else "en"


def settings_dialog(*a):
    """The settings dialog with the saved values, not shown yet (tests fill and save it without showing it)."""
    ctx = uno.getComponentContext()
    smgr, lang = ctx.ServiceManager, _lang()
    dm = smgr.createInstanceWithContext("com.sun.star.awt.UnoControlDialogModel", ctx)
    dm.Width, dm.Height, dm.Title = 250, 124, _TEXTS["title"][lang]
    for i, k in enumerate(SETTING_KEYS):
        c = dm.createInstance("com.sun.star.awt.UnoControlCheckBoxModel")
        c.PositionX, c.PositionY, c.Width, c.Height, c.Label = 8, 8 + i * 16, 234, 12, _TEXTS[k][lang]
        dm.insertByName(k, c)
    for name, x, kind in (("OK", 132, 1), ("Cancel", 190, 2)):
        c = dm.createInstance("com.sun.star.awt.UnoControlButtonModel")
        c.PositionX, c.PositionY, c.Width, c.Height = x, 102, 54, 15
        c.PushButtonType = kind  # com.sun.star.awt.PushButtonType OK / CANCEL
        c.Label = _TEXTS[name.lower()][lang]
        dm.insertByName(name, c)
    dlg = smgr.createInstanceWithContext("com.sun.star.awt.UnoControlDialog", ctx)
    dlg.setModel(dm)
    try:
        cfg = _config()
        for k in SETTING_KEYS:
            dlg.getControl(k).getModel().State = 1 if cfg.getByName(k) else 0
    except Exception:
        pass
    return dlg


def settings_save(dlg, *a):
    cfg = _config(update=True)
    for k in SETTING_KEYS:
        cfg.replaceByName(k, dlg.getControl(k).getModel().State == 1)
    cfg.commitChanges()
    _load_settings()


def settings(*a):
    """Tools ▸ UzTranslit ▸ Settings…"""
    ctx = uno.getComponentContext()
    dlg = settings_dialog()
    dlg.createPeer(ctx.ServiceManager.createInstanceWithContext("com.sun.star.awt.Toolkit", ctx), None)
    if dlg.execute() == 1:
        settings_save(dlg)
    dlg.dispose()


def self_test(*a):
    doc = XSCRIPTCONTEXT.getDocument()  # noqa: F821
    checks = [
        (convert("Toshkent shahri O'zbekiston", "lat", "new"), "Toşkent şahri Özbekiston"),
        (convert("Ўзбекистон Республикаси", "cyr", "lat"), "Oʻzbekiston Respublikasi"),
        (convert("Is'hoq obyekt", "lat", "cyr"), "Исҳоқ объект"),
        (convert("ŞAHAR Ishoq", "new", "lat"), "SHAHAR Isʼhoq"),
        (_split(["Ш", "АҲАР"], "cyr", "lat"), ["SH", "AHAR"]),
    ]
    bad = [w for g, w in checks if g != w]
    _msg(doc, "UzTranslit %s: %d/%d self-checks passed" % (VERSION, len(checks) - len(bad), len(checks)))


g_exportedScripts = (cyr_to_lat, cyr_to_new, lat_to_cyr, new_to_cyr, lat_to_new, new_to_lat,
                     auto_to_new, auto_to_lat, auto_to_cyr, self_test, settings, settings_dialog, settings_save)
