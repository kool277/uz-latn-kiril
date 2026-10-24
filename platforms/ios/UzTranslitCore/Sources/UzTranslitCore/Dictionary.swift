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
    "kvarts кварц|shprits шприц|plats плац|blits блиц"

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
