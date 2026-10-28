# UzTranslit — Uzbek script conversion specification (v1.3.0)

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
    ь : out = (lower(N) == о) ? "y" : ""                  # батальон → batalyon; компьютер → kompyuter, альбом → albom
    ё : "yo"   ю : "yu"
    я : out = monthTa(text, i) ? "a" : "ya"               # сентябрь → sentabr, октябрь → oktabr

    ш : target==new ? "ş" : "sh"      щ : same as ш
    ч : target==new ? "ç" : "ch"
    ў : target==new ? "ö" : "o"+okina
    ғ : target==new ? "ğ" : "g"+okina
    с : (target==lat and lower(N) == ҳ) ? "s"+tutuq : "s"    # Исҳоқ → Isʼhoq ; new: Ishoq
    else: simple table (а a, б b, в v, г g, д d, ж j, з z, и i, й y, к k, л l, м m, н n, о o, п p, р r, т t, у u, ф f, х x, қ q, ҳ h, э e, ы i)
  append upperOut(c, i, out)

monthTa(text, i):   # the Latin spelling of these two months has a, not ya
  the word (maximal run of letters) holding i starts with сентябр or октябр (any case) and i is the я in it
```

### 5.2 Latin → Cyrillic (`source` = `lat` or `new`)

Word pre-pass (if `dictionary`): split into maximal runs of `isLat || isApos`; for each run compute `key = normalise(run)` (lowercase; every apostrophe → `'`; ö/ō/õ→`o'`, ğ→`g'`, ş→`sh`, ç→`ch`). Find the **longest** dictionary key that is a prefix of `key`. If found: emit the dictionary value with the run's casing (ALL CAPS if the run has ≥2 letters and all are uppercase; Title if the first letter is uppercase), then convert the remainder of the run with the scanner below, passing the stem's last Latin letter as `prevContext`.
A value that ends in ь loses that ь when the remainder starts with a letter (a suffix follows), as Cyrillic spelling does: iyul → июль but iyuldagi → июлдаги, rol → роль but roli → роли; a ь inside the stem stays (filmlar → фильмлар).

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
     if not prevIsLetter and not (i>0 and isApos(text[i-1])): emit ц; i += 2; continue   # tsirk, Tsoy (no Uzbek word starts with ts; oʻtsa keeps тс)
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

Russian loans and the ўъ words, where the rules are lossy: the dictionary brings back the Cyrillic spelling (ц, ь, ъ, ё/йо). Keys are matched as **prefixes of a word** (so suffixes convert normally: kompyuterlar → компьютерлар). Keep keys that are full base words to avoid false prefixes (never add `sent` — it would hit `sentabr`). The longest
matching key wins, so a word that a shorter key would catch wrongly gets a key of its own with its rule spelling
(`sirka` vinegar, not цирк; `sinkop…`, not цинк). `yod` (ёд, memory: yodgorlik, yodda) and `yota` (yotadi) are
common Uzbek words, so йод and йота are not in the list. `tools/mine_dictionary.py` finds such cases in a parallel corpus.

```
obyekt объект · subyekt субъект · adyutant адъютант · inyeksiya инъекция · konyunktura конъюнктура
kompyuter компьютер · intervyu интервью · premyera премьера · batalyon батальон · bulyon бульон
medalyon медальон · shampinyon шампиньон · kanyon каньон · senyor сеньор · tatyana татьяна · ilya илья · nyuton ньютон
yoga йога · yogurt йогурт · york йорк
sirk цирк · sement цемент · senzura цензура · sentner центнер · sentr центр · sex цех · sikl цикл · silindr цилиндр
sisterna цистерна · sitata цитата · sitrus цитрус · sellofan целлофан · sellyuloza целлюлоза · selsiy цельсий
seremoniya церемония · sivilizatsiya цивилизация · sianid цианид · sink цинк · sirkul циркуль · sokol цоколь · sunami цунами · sitadel цитадель
sirka сирка · sinkop синкоп · sinkret синкрет · sinklinal синклинал
leksiya лекция · aksiya акция · funksiya функция · seksiya секция · fraksiya фракция · reaksiya реакция · sanksiya санкция
konstruksiya конструкция · produksiya продукция · redaksiya редакция · kolleksiya коллекция · infeksiya инфекция
proporsiya пропорция · porsiya порция · konferensiya конференция · litsenziya лицензия · litsey лицей · ofitser офицер
protsent процент · protsess процесс · protsedura процедура · konsert концерт · konsepsiya концепция · konsentratsiya концентрация
konsern концерн · potensial потенциал · differensial дифференциал · sotsial социал · sotsiologiya социология · spetsial специал · spetsifik специфик
kvarts кварц · shprits шприц · plats плац · blits блиц
stansiya станция · instansiya инстанция · distansiya дистанция · kvitansiya квитанция · korrupsiya коррупция · inspeksiya инспекция
direksiya дирекция · instruksiya инструкция · rekonstruksiya реконструкция · korreksiya коррекция · induksiya индукция
tranzaksiya транзакция · funksional функционал · aksent акцент · aksiz акциз · auksion аукцион
fransiya франция · fransuz француз · shveytsariya швейцария
yanvar январь · fevral февраль · aprel апрель · iyun июнь · iyul июль · sentabr сентябрь · sentyabr сентябрь
oktabr октябрь · oktyabr октябрь · noyabr ноябрь · dekabr декабрь
albom альбом · palto пальто · film фильм · rol роль · avtomobil автомобиль · spektakl спектакль · medal медаль · model модель
mebel мебель · portfel портфель · stil стиль · tekstil текстиль · rubl рубль · dizel дизель · kalendar календарь · slovar словарь
bukvar букварь · sekretar секретарь · ansambl ансамбль · parallel параллель · festival фестиваль · pedal педаль · detal деталь
panel панель · kabel кабель · otel отель · motel мотель · shinel шинель · kafel кафель · tabel табель · shtempel штемпель
vertikal вертикаль · gorizontal горизонталь · diagonal диагональ · magistral магистраль · spiral спираль · gospital госпиталь
dvigatel двигатель · asfalt асфальт · vals вальс · volt вольт · pult пульт · kult культ · tyulpan тюльпан · shampun шампунь
kreml кремль · alpinist альпинист · alpinizm альпинизм · konsult консульт · rezultat результат · fakultet факультет
fakultativ факультатив · kalkulyator калькулятор · kalkulyatsiya калькуляция
pavilyon павильон · pochtalyon почтальон · kompanyon компаньон · rayon район · mayor майор · mayonez майонез
mo'jiza мўъжиза · mo'tabar мўътабар · mo'tadil мўътадил · mo'jaz мўъжаз
kontrol контроль · parol пароль · profil профиль · konsol консоль · patrul патруль · alkogol алкоголь · 
ventil вентиль · akvarel акварель · karusel карусель · vermishel вермишель · royal рояль · fonar фонарь · 
inventar инвентарь · byulleten бюллетень · kartofel картофель · fasol фасоль · dirijabl дирижабль · 
folklor фольклор · palma пальма · almanax альманах · volfram вольфрам · kobalt кобальт · bolshevik большевик · 
kulminatsiya кульминация · multfilm мультфильм · multi мульти · bilyard бильярд · kalyan кальян · ssenariy сценарий · 
aksioner акционер · ofitsiant официант · ofitsial официал · patsient пациент · patsiyent пациент · 
meditsina медицина · vaksina вакцина · kansler канцлер · kanselyariya канцелярия · glitserin глицерин · 
konsentrat концентрат · farmatsevt фармацевт · intsident инцидент · provinsiya провинция · kompetensiya компетенция · 
tendensiya тенденция · rezidensiya резиденция · konkurensiya конкуренция · prinsip принцип · dotsent доцент · 
sotsiolog социолог · assotsiatsiya ассоциация · retsept рецепт · retsenziya рецензия · retsenzent рецензент · 
polsha польша · dezinfeksiya дезинфекция · podyezd подъезд · syezd съезд · obyom объём · 
alyans альянс · apelsin апельсин · artel артель · aerozol аэрозоль · binokl бинокль · bulvar бульвар · 
buldozer бульдозер · vestibyul вестибюль · gantel гантель · grifel грифель · impuls импульс · 
insult инсульт · kalsiy кальций · kanifol канифоль · karamel карамель · kartel картель · kokteyl коктейль · 
korabl корабль · lager лагерь · konslager концлагерь · menshevik меньшевик · modul модуль · 
molbert мольберт · nikel никель · nobel нобель · pelmen пельмень · porshen поршень · rels рельс · 
skalpel скальпель · sterjen стержень · sudya судья · tunnel туннель · tyulen тюлень · ultra ультра · 
ultimatum ультиматум · feldsher фельдшер · feldmarshal фельдмаршал · filtr фильтр · fotoalbom фотоальбом · 
kinofilm кинофильм · videofilm видеофильм · xolodilnik холодильник · shnitsel шницель · shpatel шпатель · 
shtepsel штепсель · gilyotina гильотина · avtomagistral автомагистраль · podyom подъём · natalya наталья · 
igor игорь · lyubov любовь · sofya софья · solovyov соловьёв · muravyov муравьёв · lukyanov лукьянов · 
kasyanov касьянов · yemelyanov емельянов · vitse вице · meriya мэрия · konvensiya конвенция · 
intervensiya интервенция · shveysariya швейцария · mototsikl мотоцикл · genotsid геноцид · suitsid суицид · 
pestitsid пестицид · gerbitsid гербицид · insektitsid инсектицид · fungitsid фунгицид · natsist нацист · 
neonatsist неонацист · natsizm нацизм · radiostansiya радиостанция · elektrostansiya электростанция · 
gidroelektrostansiya гидроэлектростанция · avtostansiya автостанция · yurisprudensiya юриспруденция · 
kontratsepsiya контрацепция · epitsentr эпицентр · karser карцер · insident инцидент · pretsedent прецедент · 
dissiplina дисциплина · konsorsium консорциум · korrupsion коррупцион · matritsa матрица · 
prezumpsiya презумпция · pritsep прицеп · proteksionizm протекционизм · publitsist публицист · 
reaksion реакцион · spetsnaz спецназ · defitsit дефицит · koeffitsiyent коэффициент · 
koeffitsient коэффициент · mikrorayon микрорайон · videokonferensiya видеоконференция · 
korrespondensiya корреспонденция · intelligensiya интеллигенция · inersiya инерция · deduksiya дедукция · 
abstraksiya абстракция · attraksion аттракцион · seleksiya селекция · proyeksiya проекция · 
distansion дистанцион · konsept концепт · metsenat меценат · retsidiv рецидив · abzas абзац · gersog герцог · 
ritsar рицарь · senariy сценарий · siferblat циферблат · sitoplazma цитоплазма · sitolog цитолог · 
seziy цезий · sistit цистит · pitsa пицца · pitseriya пиццерия · sotsium социум · initsiat инициат · 
detsibel децибел · yelsin ельцин · sho'ba шўъба · mo'tamad мўътамад · no'mon нўъмон · meyor меъёр · 
toyota тойота · atset ацет · publitsistik публицистик · klassitsizm классицизм · 
neoklassitsizm неоклассицизм · katolitsizm католицизм · agnostitsizm агностицизм · eritrotsit эритроцит · 
leykotsit лейкоцит · limfotsit лимфоцит · fagotsit фагоцит · antitsiklon антициклон · frantsuz француз · 
konfutsiy конфуций · munitsipal муниципал · mitseliy мицелий · biotsenoz биоценоз · 
biogeotsenoz биогеоценоз · pliotsen плиоцен · paleotsen палеоцен · eotsen эоцен · oligotsen олигоцен · 
miotsen миоцен · nitsshe ницше · monatsit монацит · pretsessiya прецессия · mikroprotsessor микропроцессор · 
kaltsiy кальций · kaltsit кальцит · sitsiliya сицилия · penitsillin пенициллин · streptomitsin стрептомицин · 
motsart моцарт · triglitserid триглицерид · nitroglitserin нитроглицерин · retsessiv рецессив · 
potentsial потенциал · dissotsiatsiya диссоциация · detsimetr дециметр · geotsentrik геоцентрик · 
geliotsentrik гелиоцентрик · akaritsid акарицид · bakteritsid бактерицид · silitsid силицид · 
kontseptsiya концепция · printsip принцип · atstek ацтек · cherepitsa черепица · aristotel аристотель · 
gastrol гастроль · emuls эмульс · delta дельта · galvan гальван
```
Ports may extend the list; `fixtures.json` only relies on the entries marked "dictionary" in its notes.

## 7. Known lossy conversions (documented, not bugs)

* Cyrillic ь not before е/ё/ю/я/о is dropped; it comes back only for dictionary stems (альбом → albom → альбом, but
  гриль → gril → грил).
* Cyrillic ъ before iotated vowels is dropped (объект ↔ obyekt needs the dictionary to come back).
* Cyrillic йо/йу/йа sequences (йод, Майами) become yo/yu/ya and read back as ё/ю/я unless in the dictionary.
* Cyrillic ц → s/ts needs the dictionary to come back to ц in most words (word-initial ts and ts before iya/ion,
  and word-final ts after a vowel, are rules).
* ўъ → oʻ / ö comes back as ўъ only for dictionary stems (мўъжиза).
* 2026 orthography rules (imlo qoidalari) are not yet published; the treatment of ўъ (möjiza) is configurable.
