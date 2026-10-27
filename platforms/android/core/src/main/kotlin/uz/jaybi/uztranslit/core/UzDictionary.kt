package uz.jaybi.uztranslit.core

/**
 * SPEC §6: Latin → Cyrillic stems for loanwords where the rules are lossy (Russian loans with ц, ъ, ь, йо).
 * Keys are lowercase with the ASCII apostrophe and are matched as prefixes of a word, so suffixes convert
 * normally (kompyuterlar → компьютерлар). Same entries, same order as SPEC §6 (DictionaryTest checks it).
 */
public object UzDictionary {
    public val entries: List<Pair<String, String>> = listOf(
        "obyekt" to "объект", "subyekt" to "субъект", "adyutant" to "адъютант", "inyeksiya" to "инъекция",
        "konyunktura" to "конъюнктура",
        "kompyuter" to "компьютер", "intervyu" to "интервью", "premyera" to "премьера", "batalyon" to "батальон",
        "bulyon" to "бульон", "medalyon" to "медальон", "shampinyon" to "шампиньон", "kanyon" to "каньон",
        "senyor" to "сеньор", "tatyana" to "татьяна", "ilya" to "илья", "nyuton" to "ньютон",
        "yoga" to "йога", "yogurt" to "йогурт", "york" to "йорк",
        "sirk" to "цирк", "sement" to "цемент", "senzura" to "цензура", "sentner" to "центнер", "sentr" to "центр",
        "sex" to "цех", "sikl" to "цикл", "silindr" to "цилиндр",
        "sisterna" to "цистерна", "sitata" to "цитата", "sitrus" to "цитрус", "sellofan" to "целлофан",
        "sellyuloza" to "целлюлоза", "selsiy" to "цельсий",
        "seremoniya" to "церемония", "sivilizatsiya" to "цивилизация", "sianid" to "цианид", "sink" to "цинк",
        "sirkul" to "циркуль", "sokol" to "цоколь", "sunami" to "цунами", "sitadel" to "цитадель",
        "sirka" to "сирка", "sinkop" to "синкоп", "sinkret" to "синкрет", "sinklinal" to "синклинал",
        "leksiya" to "лекция", "aksiya" to "акция", "funksiya" to "функция", "seksiya" to "секция",
        "fraksiya" to "фракция", "reaksiya" to "реакция", "sanksiya" to "санкция",
        "konstruksiya" to "конструкция", "produksiya" to "продукция", "redaksiya" to "редакция",
        "kolleksiya" to "коллекция", "infeksiya" to "инфекция",
        "proporsiya" to "пропорция", "porsiya" to "порция", "konferensiya" to "конференция",
        "litsenziya" to "лицензия", "litsey" to "лицей", "ofitser" to "офицер",
        "protsent" to "процент", "protsess" to "процесс", "protsedura" to "процедура", "konsert" to "концерт",
        "konsepsiya" to "концепция", "konsentratsiya" to "концентрация",
        "konsern" to "концерн", "potensial" to "потенциал", "differensial" to "дифференциал", "sotsial" to "социал",
        "sotsiologiya" to "социология", "spetsial" to "специал", "spetsifik" to "специфик",
        "kvarts" to "кварц", "shprits" to "шприц", "plats" to "плац", "blits" to "блиц",
        "stansiya" to "станция", "instansiya" to "инстанция", "distansiya" to "дистанция",
        "kvitansiya" to "квитанция", "korrupsiya" to "коррупция", "inspeksiya" to "инспекция",
        "direksiya" to "дирекция", "instruksiya" to "инструкция", "rekonstruksiya" to "реконструкция",
        "korreksiya" to "коррекция", "induksiya" to "индукция", "tranzaksiya" to "транзакция",
        "funksional" to "функционал", "aksent" to "акцент", "aksiz" to "акциз", "auksion" to "аукцион",
        "fransiya" to "франция", "fransuz" to "француз", "shveytsariya" to "швейцария", "yanvar" to "январь",
        "fevral" to "февраль", "aprel" to "апрель", "iyun" to "июнь", "iyul" to "июль", "sentabr" to "сентябрь",
        "sentyabr" to "сентябрь", "oktabr" to "октябрь", "oktyabr" to "октябрь", "noyabr" to "ноябрь",
        "dekabr" to "декабрь", "albom" to "альбом", "palto" to "пальто", "film" to "фильм", "rol" to "роль",
        "avtomobil" to "автомобиль", "spektakl" to "спектакль", "medal" to "медаль", "model" to "модель",
        "mebel" to "мебель", "portfel" to "портфель", "stil" to "стиль", "tekstil" to "текстиль", "rubl" to "рубль",
        "dizel" to "дизель", "kalendar" to "календарь", "slovar" to "словарь", "bukvar" to "букварь",
        "sekretar" to "секретарь", "ansambl" to "ансамбль", "parallel" to "параллель", "festival" to "фестиваль",
        "pedal" to "педаль", "detal" to "деталь", "panel" to "панель", "kabel" to "кабель", "otel" to "отель",
        "motel" to "мотель", "shinel" to "шинель", "kafel" to "кафель", "tabel" to "табель",
        "shtempel" to "штемпель", "vertikal" to "вертикаль", "gorizontal" to "горизонталь",
        "diagonal" to "диагональ", "magistral" to "магистраль", "spiral" to "спираль", "gospital" to "госпиталь",
        "dvigatel" to "двигатель", "asfalt" to "асфальт", "vals" to "вальс", "volt" to "вольт", "pult" to "пульт",
        "kult" to "культ", "tyulpan" to "тюльпан", "shampun" to "шампунь", "kreml" to "кремль",
        "alpinist" to "альпинист", "alpinizm" to "альпинизм", "konsult" to "консульт", "rezultat" to "результат",
        "fakultet" to "факультет", "fakultativ" to "факультатив", "kalkulyator" to "калькулятор",
        "kalkulyatsiya" to "калькуляция", "pavilyon" to "павильон", "pochtalyon" to "почтальон",
        "kompanyon" to "компаньон", "rayon" to "район", "mayor" to "майор", "mayonez" to "майонез",
        "mo'jiza" to "мўъжиза", "mo'tabar" to "мўътабар", "mo'tadil" to "мўътадил", "mo'jaz" to "мўъжаз",
    )

    private val values: Map<String, String> = entries.toMap()

    // Keys grouped by their first character, longest first: the first key of a group that is a prefix of a word's
    // key is the longest dictionary key that is (two different keys of the same length cannot both be prefixes).
    private val groups: Array<List<String>?> = arrayOfNulls<List<String>>(128).also { g ->
        for ((first, keys) in entries.map { it.first }.groupBy { it[0] }) {
            require(first.code < 128) { "dictionary keys are lowercase ASCII: $first" }
            g[first.code] = keys.sortedByDescending { it.length }
        }
    }

    /** The Cyrillic stem for a dictionary key, or null. */
    public operator fun get(key: String): String? = values[key]

    /** The longest dictionary key that is a prefix of the normalised word [key] (SPEC §5.2), or null. */
    internal fun longestPrefixOf(key: String): String? {
        if (key.isEmpty()) return null
        val first = key[0].code
        if (first >= 128) return null
        for (k in groups[first] ?: return null) if (key.startsWith(k)) return k
        return null
    }
}
