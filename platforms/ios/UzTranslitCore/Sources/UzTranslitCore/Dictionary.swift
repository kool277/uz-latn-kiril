// SPEC §6: Latin → Cyrillic stem dictionary. Keys are lowercase with the ASCII apostrophe and match as prefixes of a
// word, longest key first. Same list as DICT_SRC in core/js/uztranslit.js.

let DICT_SRC = "obyekt объект|subyekt субъект|adyutant адъютант|inyeksiya инъекция|konyunktura конъюнктура|" +
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
    "kvarts кварц|shprits шприц|plats плац|blits блиц|" +
    "stansiya станция|instansiya инстанция|distansiya дистанция|kvitansiya квитанция|korrupsiya коррупция|" +
    "inspeksiya инспекция|direksiya дирекция|instruksiya инструкция|rekonstruksiya реконструкция|" +
    "korreksiya коррекция|induksiya индукция|tranzaksiya транзакция|funksional функционал|aksent акцент|" +
    "aksiz акциз|auksion аукцион|fransiya франция|fransuz француз|shveytsariya швейцария|yanvar январь|" +
    "fevral февраль|aprel апрель|iyun июнь|iyul июль|sentabr сентябрь|sentyabr сентябрь|oktabr октябрь|" +
    "oktyabr октябрь|noyabr ноябрь|dekabr декабрь|albom альбом|palto пальто|film фильм|rol роль|" +
    "avtomobil автомобиль|spektakl спектакль|medal медаль|model модель|mebel мебель|portfel портфель|" +
    "stil стиль|tekstil текстиль|rubl рубль|dizel дизель|kalendar календарь|slovar словарь|bukvar букварь|" +
    "sekretar секретарь|ansambl ансамбль|parallel параллель|festival фестиваль|pedal педаль|detal деталь|" +
    "panel панель|kabel кабель|otel отель|motel мотель|shinel шинель|kafel кафель|tabel табель|" +
    "shtempel штемпель|vertikal вертикаль|gorizontal горизонталь|diagonal диагональ|magistral магистраль|" +
    "spiral спираль|gospital госпиталь|dvigatel двигатель|asfalt асфальт|vals вальс|volt вольт|pult пульт|" +
    "kult культ|tyulpan тюльпан|shampun шампунь|kreml кремль|alpinist альпинист|alpinizm альпинизм|" +
    "konsult консульт|rezultat результат|fakultet факультет|fakultativ факультатив|kalkulyator калькулятор|" +
    "kalkulyatsiya калькуляция|pavilyon павильон|pochtalyon почтальон|kompanyon компаньон|rayon район|" +
    "mayor майор|mayonez майонез|mo'jiza мўъжиза|mo'tabar мўътабар|mo'tadil мўътадил|mo'jaz мўъжаз|" +
    "kontrol контроль|parol пароль|profil профиль|konsol консоль|patrul патруль|alkogol алкоголь|" +
    "ventil вентиль|akvarel акварель|karusel карусель|vermishel вермишель|royal рояль|fonar фонарь|" +
    "inventar инвентарь|byulleten бюллетень|kartofel картофель|fasol фасоль|dirijabl дирижабль|" +
    "folklor фольклор|palma пальма|almanax альманах|volfram вольфрам|kobalt кобальт|bolshevik большевик|" +
    "kulminatsiya кульминация|multfilm мультфильм|multi мульти|bilyard бильярд|kalyan кальян|" +
    "ssenariy сценарий|aksioner акционер|ofitsiant официант|ofitsial официал|patsient пациент|" +
    "patsiyent пациент|meditsina медицина|vaksina вакцина|kansler канцлер|kanselyariya канцелярия|" +
    "glitserin глицерин|konsentrat концентрат|farmatsevt фармацевт|intsident инцидент|provinsiya провинция|" +
    "kompetensiya компетенция|tendensiya тенденция|rezidensiya резиденция|konkurensiya конкуренция|" +
    "prinsip принцип|dotsent доцент|sotsiolog социолог|assotsiatsiya ассоциация|retsept рецепт|" +
    "retsenziya рецензия|retsenzent рецензент|polsha польша|dezinfeksiya дезинфекция|podyezd подъезд|" +
    "syezd съезд|obyom объём|" +
    "alyans альянс|apelsin апельсин|artel артель|aerozol аэрозоль|binokl бинокль|bulvar бульвар|" +
    "buldozer бульдозер|vestibyul вестибюль|gantel гантель|grifel грифель|impuls импульс|insult инсульт|" +
    "kalsiy кальций|kanifol канифоль|karamel карамель|kartel картель|kokteyl коктейль|korabl корабль|" +
    "lager лагерь|konslager концлагерь|menshevik меньшевик|modul модуль|molbert мольберт|nikel никель|" +
    "nobel нобель|pelmen пельмень|porshen поршень|rels рельс|skalpel скальпель|sterjen стержень|" +
    "sudya судья|tunnel туннель|tyulen тюлень|ultra ультра|ultimatum ультиматум|feldsher фельдшер|" +
    "feldmarshal фельдмаршал|filtr фильтр|fotoalbom фотоальбом|kinofilm кинофильм|videofilm видеофильм|" +
    "xolodilnik холодильник|shnitsel шницель|shpatel шпатель|shtepsel штепсель|gilyotina гильотина|" +
    "avtomagistral автомагистраль|podyom подъём|natalya наталья|igor игорь|lyubov любовь|sofya софья|" +
    "solovyov соловьёв|muravyov муравьёв|lukyanov лукьянов|kasyanov касьянов|yemelyanov емельянов|" +
    "vitse вице|meriya мэрия|konvensiya конвенция|intervensiya интервенция|shveysariya швейцария|" +
    "mototsikl мотоцикл|genotsid геноцид|suitsid суицид|pestitsid пестицид|gerbitsid гербицид|" +
    "insektitsid инсектицид|fungitsid фунгицид|natsist нацист|neonatsist неонацист|natsizm нацизм|" +
    "radiostansiya радиостанция|elektrostansiya электростанция|gidroelektrostansiya гидроэлектростанция|" +
    "avtostansiya автостанция|yurisprudensiya юриспруденция|kontratsepsiya контрацепция|" +
    "epitsentr эпицентр|karser карцер|insident инцидент|pretsedent прецедент|dissiplina дисциплина|" +
    "konsorsium консорциум|korrupsion коррупцион|matritsa матрица|prezumpsiya презумпция|pritsep прицеп|" +
    "proteksionizm протекционизм|publitsist публицист|reaksion реакцион|spetsnaz спецназ|" +
    "defitsit дефицит|koeffitsiyent коэффициент|koeffitsient коэффициент|mikrorayon микрорайон|" +
    "videokonferensiya видеоконференция|korrespondensiya корреспонденция|intelligensiya интеллигенция|" +
    "inersiya инерция|deduksiya дедукция|abstraksiya абстракция|attraksion аттракцион|seleksiya селекция|" +
    "proyeksiya проекция|distansion дистанцион|konsept концепт|metsenat меценат|retsidiv рецидив|" +
    "abzas абзац|gersog герцог|ritsar рицарь|senariy сценарий|siferblat циферблат|sitoplazma цитоплазма|" +
    "sitolog цитолог|seziy цезий|sistit цистит|pitsa пицца|pitseriya пиццерия|sotsium социум|" +
    "initsiat инициат|detsibel децибел|yelsin ельцин|sho'ba шўъба|mo'tamad мўътамад|no'mon нўъмон|" +
    "meyor меъёр|toyota тойота|atset ацет|publitsistik публицистик|klassitsizm классицизм|" +
    "neoklassitsizm неоклассицизм|katolitsizm католицизм|agnostitsizm агностицизм|eritrotsit эритроцит|" +
    "leykotsit лейкоцит|limfotsit лимфоцит|fagotsit фагоцит|antitsiklon антициклон|frantsuz француз|" +
    "konfutsiy конфуций|munitsipal муниципал|mitseliy мицелий|biotsenoz биоценоз|" +
    "biogeotsenoz биогеоценоз|pliotsen плиоцен|paleotsen палеоцен|eotsen эоцен|oligotsen олигоцен|" +
    "miotsen миоцен|nitsshe ницше|monatsit монацит|pretsessiya прецессия|mikroprotsessor микропроцессор|" +
    "kaltsiy кальций|kaltsit кальцит|sitsiliya сицилия|penitsillin пенициллин|streptomitsin стрептомицин|" +
    "motsart моцарт|triglitserid триглицерид|nitroglitserin нитроглицерин|retsessiv рецессив|" +
    "potentsial потенциал|dissotsiatsiya диссоциация|detsimetr дециметр|geotsentrik геоцентрик|" +
    "geliotsentrik гелиоцентрик|akaritsid акарицид|bakteritsid бактерицид|silitsid силицид|" +
    "kontseptsiya концепция|printsip принцип|atstek ацтек|cherepitsa черепица|aristotel аристотель|" +
    "gastrol гастроль|emuls эмульс|delta дельта|galvan гальван"

struct DictEntry: Sendable {
    let key: [UInt16]
    let value: [UInt16]
}

/// The dictionary indexed by the first letter of the key (a–z); each bucket is sorted longest key first, so the
/// first key that is a prefix of a word is the longest one (two keys of the same length cannot both be prefixes).
struct StemDictionary: Sendable {
    let buckets: [[DictEntry]]

    init(_ source: String) {
        var buckets = [[DictEntry]](repeating: [], count: 26)
        for pair in source.split(separator: "|") {
            let kv = pair.split(separator: " ")
            let entry = DictEntry(key: Array(kv[0].utf16), value: Array(kv[1].utf16))
            let f = Int(entry.key[0]) - 0x61
            buckets[f].append(entry)
        }
        // stable sort, longest first
        self.buckets = buckets.map { bucket in
            bucket.enumerated()
                .sorted { $0.element.key.count != $1.element.key.count ? $0.element.key.count > $1.element.key.count : $0.offset < $1.offset }
                .map(\.element)
        }
    }

    /// The longest entry whose key is a prefix of `key` (a normalised word, see normKey).
    func lookup(_ key: [UInt16]) -> DictEntry? {
        guard let first = key.first else { return nil }
        let f = Int(first) - 0x61
        guard f >= 0 && f < 26 else { return nil }
        for entry in buckets[f] where entry.key.count <= key.count {
            if key.starts(with: entry.key) { return entry }
        }
        return nil
    }
}

let DICT = StemDictionary(DICT_SRC)
