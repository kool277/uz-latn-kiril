# UzTranslit — Uzbek script conversion specification (v1.0.0)

Single source of truth for every port (JS, Python, VBA, LibreOffice Basic, Kotlin, Swift, C++/Qt).
A port is **conformant** when it passes every entry in `fixtures.json` (`cases`, `roundtrips`, `detect`) with default options.

## 1. Scripts

| id    | Name                           | Letters |
|-------|--------------------------------|---------|
| `cyr` | Uzbek Cyrillic (1940)          | А Б В Г Д Е Ё Ж З И Й К Л М Н О П Р С Т У Ф Х Ц Ч Ш Ъ Ь Э Ю Я Ў Қ Ғ Ҳ (+ Щ Ы in loanwords) |
| `lat` | Uzbek Latin 1995               | A B D E F G H I J K L M N O P Q R S T U V X Y Z Oʻ Gʻ Sh Ch Ng + ʼ |
| `new` | Uzbek Latin 2026 (OʻRQ-1184, signed 2026-10-21, in force 6 months after publication) | A B Ç D E F G Ğ H I J K L M N O Ö P Q R S Ş T U V X Y Z + ʼ |

2026 changes: **Oʻ→Ö, Gʻ→Ğ, Sh→Ş, Ch→Ç**; `ng` is no longer listed as a letter (still spelled `n`+`g`); tutuq belgisi `ʼ` (U+02BC) is kept (maʼno, sheʼr).
Legacy draft glyphs `Ō ō` (2021) and `Õ õ` (2019) are accepted on **input** as Ö/ö; they are never produced.

Code points that matter:

| char | code | role |
|---|---|---|
| ʻ | U+02BB | okina — the official mark in Oʻ/Gʻ (output of `lat`) |
| ʼ | U+02BC | tutuq belgisi (output of `lat` and `new`) |
| ' ‘ ’ ` ´ | U+0027 U+2018 U+2019 U+0060 U+00B4 | accepted on input as either mark |
| Ў ў Қ қ Ғ ғ Ҳ ҳ Ё ё | U+040E/045E U+049A/049B U+0492/0493 U+04B2/04B3 U+0401/0451 | Uzbek-specific Cyrillic |
| Ö ö Ğ ğ Ş ş Ç ç | U+00D6/00F6 U+011E/011F U+015E/015F U+00C7/00E7 | 2026 letters |

## 2. Public API (identical in every port)

```
convert(text, from, to, options) -> string     from,to ∈ {cyr, lat, new}; from == to returns text unchanged
detect(text) -> "cyr" | "lat" | "new"
cyrToLat(text, opts)   cyrToNew(text, opts)
latToCyr(text, opts)   newToCyr(text, opts)
latToNew(text, opts)   newToLat(text, opts)
```

Options (all optional):

| option | default | meaning |
|---|---|---|
| `okina` | `"ʻ"` | mark used in Oʻ/Gʻ output (`"'"` for ASCII) |
| `tutuq` | `"ʼ"` | mark used for ъ / tutuq output (`"'"` for ASCII) |
| `dropHardSignAfterO` | `true` | Cyrillic ўъ → oʻ / ö (мўъжиза → moʻjiza, möjiza) |
| `tsFinal` | `true` | Latin word-final `ts` after a vowel → ц (abzats → абзац) |
| `dictionary` | `true` | apply the stem dictionary (§6) in Latin → Cyrillic |
| `skipUrls` | `true` (JS/Python/web only) | leave URLs, e-mails, @handles unchanged |

## 3. Character classes

* `isCyr(c)` — c is one of the 35+2 Cyrillic letters above, either case.
* `isLat(c)` — c is A–Z, a–z, or Ö ö Ğ ğ Ş ş Ç ç Ō ō Õ õ.
* `isApos(c)` — c ∈ { ' ʻ ʼ ‘ ’ ` ´ }.
* `cyrVowel` = { а е ё и о у э ю я ў ы }, `latVowel` = { a e i o u ö ō õ } (case-insensitive).
* A **letter** is `isCyr(c) || isLat(c)`; everything else (digits, punctuation, spaces, apostrophes) is a boundary.

## 4. Casing rule (used wherever one source letter yields several output letters)

```
upperOut(src, i, out):
  if src is lowercase: return out
  if len(out) == 1:    return upper(out)
  allCaps = nextLetterIsUpper(text, i)       # next letter (skipping one apostrophe) is uppercase,
                                             # or, if there is no next letter, the previous letter is uppercase
  return allCaps ? upper(out) : upperFirst(out)
```
Examples: ШАҲАР→SHAHAR, Шаҳар→Shahar, Ш→Sh, ТАЙЁР→TAYYOR, Ё→Yo, ЕР→YER, Ер→Yer, ŞAHAR→SHAHAR, Şahar→Shahar.

## 5. Algorithms

All scanners walk the string left to right with an index `i`, look at `prev = text[i-1]` and `next = text[i+1]` (and `text[i+2]` where stated), and append to an output buffer. Characters outside the relevant class are copied unchanged.

### 5.1 Cyrillic → Latin (`target` = `lat` or `new`)

```
for each char c at i:
  if not isCyr(c): copy; continue
  L = lower(c); P = prev char (or none); N = next char (or none)
  switch L:
    е : out = (P is none or not isCyr(P) or cyrVowel(P) or P ∈ {ъ ь}) ? "ye" : "e"
    ц : out = (P is cyr vowel) ? "ts" : "s"
    ъ : if N ∈ {е ё ю я}: out = ""                      # objekt → obyekt
        elif lower(P) == ў and dropHardSignAfterO: out = ""   # мўъжиза → moʻjiza
        else out = tutuq
    ь : out = ""                                          # компьютер → kompyuter, альбом → albom
    ё : "yo"   ю : "yu"   я : "ya"
    ш : target==new ? "ş" : "sh"      щ : same as ш
    ч : target==new ? "ç" : "ch"
    ў : target==new ? "ö" : "o"+okina
    ғ : target==new ? "ğ" : "g"+okina
    с : (target==lat and lower(N) == ҳ) ? "s"+tutuq : "s"    # Исҳоқ → Isʼhoq ; new: Ishoq
    else: simple table (а a, б b, в v, г g, д d, ж j, з z, и i, й y, к k, л l, м m, н n, о o, п p, р r, т t, у u, ф f, х x, қ q, ҳ h, э e, ы i)
  append upperOut(c, i, out)
```

### 5.2 Latin → Cyrillic (`source` = `lat` or `new`)

Word pre-pass (if `dictionary`): split into maximal runs of `isLat || isApos`; for each run compute `key = normalise(run)` (lowercase; every apostrophe → `'`; ö/ō/õ→`o'`, ğ→`g'`, ş→`sh`, ç→`ch`). Find the **longest** dictionary key that is a prefix of `key`. If found: emit the dictionary value with the run's casing (ALL CAPS if the run has ≥2 letters and all are uppercase; Title if the first letter is uppercase), then convert the remainder of the run with the scanner below, passing the stem's last Latin letter as `prevContext`.

Scanner:
```
i = 0
while i < n:
  c = text[i]
  if isApos(c):
     prevL = i>0 and isLat(text[i-1]);  nextL = i+1<n and isLat(text[i+1])
     if prevL and nextL: out ъ (Ъ if text[i-1] is uppercase)       # maʼno → маъно
     elif prevL and c == U+02BC: out ъ                               # explicit word-final tutuq
     else copy c                                                     # quotes stay quotes
     i += 1; continue
  if not isLat(c): copy; i += 1; continue
  L = lower(c); up = isUpper(c); N = text[i+1] (or none); N2 = text[i+2] (or none)
  # letter + apostrophe
  if L == o and isApos(N): emit ў; i += 2; continue
  if L == g and isApos(N): emit ғ; i += 2; continue
  # 2026 letters and legacy drafts
  if L ∈ {ö ō õ}: ў   ğ: ғ   ş: ш   ç: ч     → emit; i += 1; continue
  # s / sh / sʼh
  if L == s:
     if lower(N) == h and source == lat: emit ш; i += 2; continue       # 1995: sh = ш
     if isApos(N) and lower(N2) == h:    emit с; i += 2; continue       # Isʼhoq: drop separator, h→ҳ next
     # source == new: plain s; the following h becomes ҳ (Ishoq → Исҳоқ)
  if L == c and lower(N) == h: emit ч; i += 2; continue                 # tolerated in both sources
  # y + vowel
  if L == y and lower(N) ∈ {o u a e}:
     V = lower(N)
     if V == o and isApos(N2): emit й; i += 1; continue                 # yoʻl → йўл
     prevIsLetter = i>0 and isLat(text[i-1])          (use prevContext when i == 0)
     prevIsVowelOrApos = i>0 and (latVowel(text[i-1]) or isApos(text[i-1]))
     if V == e:
        if not prevIsLetter or prevIsVowelOrApos: emit е          # Yer, Aliyev, Xoʻjayev
        else: emit ь then е                                       # pyesa → пьеса (dictionary gives ъ: obyekt)
     else: emit ё / ю / я                                         # quyosh, menyu, Fyodor, soya
     i += 2; continue
  # e
  if L == e: emit (not prevIsLetter or prevIsVowelOrApos) ? э : е     # Ekologiya, poema / Toshkent
  # ts
  if L == t and lower(N) == s:
     rest = lower(text[i+2 : i+5])
     if rest startswith "iya" or "ion": emit ц; i += 2; continue     # militsiya, ratsion
     if tsFinal and (i+2 == n or not isLat(text[i+2])) and i>0 and latVowel(text[i-1]): emit ц; i += 2; continue   # abzats
     # otherwise fall through: native oʻtsa, ketsa, aytsin keep т+с
  simple table: a а, b б, d д, f ф, g г, h ҳ, i и, j ж, k к, l л, m м, n н, o о, p п, q қ, r р, s с, t т, u у, v в, x х, y й, z з, c ц, w в
  emit with case of c; i += 1
```

### 5.3 Latin 1995 → Latin 2026

```
  o + apostrophe → ö     g + apostrophe → ğ     s + h → ş     c + h → ç     (case from the first letter;
                                                                            "SH"/"Sh"/"sh" → Ş/Ş/ş)
  s + apostrophe + h → s (the separator is no longer needed: Isʼhoq → Ishoq)
  apostrophe between two letters → tutuq (U+02BC), other apostrophes copied unchanged
  ō ō õ → ö (legacy drafts)   everything else copied
```

### 5.4 Latin 2026 → Latin 1995

```
  ö ō õ → o+okina    ğ → g+okina    ş → "sh" (casing rule §4: ŞAHAR→SHAHAR, Şahar→Shahar, Ş→Sh)    ç → "ch"
  s + h (both plain letters, i.e. genuine s followed by h) → s + tutuq + h   (Ishoq → Isʼhoq)
  apostrophe between two letters → tutuq (U+02BC)
```

### 5.5 Detection

Count `cyr` letters, Latin letters, 2026-specific letters (ö ğ ş ç ō õ, either case) and 1995 digraph hits (`sh`, `ch`, `o'`, `g'` with any apostrophe, case-insensitive).
`cyr` if cyrCount > latCount; else `new` if newCount > 0 and newCount ≥ digraphCount; else `lat` (also for empty / letterless input).

### 5.6 URL / e-mail protection (JS, Python, web)

Before converting, tokenise with `(https?://|www\.)\S+|\S+@\S+\.\S+|@\w+` and pass those tokens through unchanged.

## 6. Dictionary (Latin → Cyrillic stems, lowercase keys with ASCII `'`)

Russian loans where the rules are lossy. Keys are matched as **prefixes of a word** (so suffixes convert normally: kompyuterlar → компьютерлар). Keep keys that are full base words to avoid false prefixes (never add `sent` — it would hit `sentabr`).

```
obyekt объект · subyekt субъект · adyutant адъютант · inyeksiya инъекция · konyunktura конъюнктура
kompyuter компьютер · intervyu интервью · premyera премьера · batalyon батальон · bulyon бульон
medalyon медальон · shampinyon шампиньон · kanyon каньон · senyor сеньор · tatyana татьяна · ilya илья · nyuton ньютон
yod йод · yoga йога · yogurt йогурт · york йорк · yota йота
sirk цирк · sement цемент · senzura цензура · sentner центнер · sentr центр · sex цех · sikl цикл · silindr цилиндр
sisterna цистерна · sitata цитата · sitrus цитрус · sellofan целлофан · sellyuloza целлюлоза · selsiy цельсий
seremoniya церемония · sivilizatsiya цивилизация · sianid цианид · sink цинк · sirkul циркуль · sokol цоколь · sunami цунами · sitadel цитадель
leksiya лекция · aksiya акция · funksiya функция · seksiya секция · fraksiya фракция · reaksiya реакция · sanksiya санкция
konstruksiya конструкция · produksiya продукция · redaksiya редакция · kolleksiya коллекция · infeksiya инфекция
proporsiya пропорция · porsiya порция · konferensiya конференция · litsenziya лицензия · litsey лицей · ofitser офицер
protsent процент · protsess процесс · protsedura процедура · konsert концерт · konsepsiya концепция · konsentratsiya концентрация
konsern концерн · potensial потенциал · differensial дифференциал · sotsial социал · sotsiologiya социология · spetsial специал · spetsifik специфик
kvarts кварц · shprits шприц · plats плац · blits блиц
```
Ports may extend the list; `fixtures.json` only relies on the entries marked "dictionary" in its notes.

## 7. Known lossy conversions (documented, not bugs)

* Cyrillic ь not before е/ё/ю/я is dropped (альбом → albom → албом).
* Cyrillic ъ before iotated vowels is dropped (объект ↔ obyekt needs the dictionary to come back).
* Cyrillic йо/йу/йа sequences (йод, Майами) become yo/yu/ya and read back as ё/ю/я unless in the dictionary.
* Cyrillic ц → s/ts needs the dictionary to come back to ц in most words.
* 2026 orthography rules (imlo qoidalari) are not yet published; the treatment of ўъ (möjiza) is configurable.
