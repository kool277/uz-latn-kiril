// UzTranslit — C++/Qt port of spec/SPEC.md v1.0.0 (see uztranslit.hpp).
// Every function below mirrors the function of the same name in core/js/uztranslit.js; the comments name the
// reference behaviour wherever C++ needs a different spelling of it.
#include "uztranslit.hpp"

#include <algorithm>
#include <array>
#include <cstdint>
#include <stdexcept>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace uztranslit {
namespace {

// ---------------------------------------------------------------- character classes (SPEC §3)
// The same strings as the reference implementation.
constexpr std::u16string_view CYR_LOWER = u"абвгдеёжзийклмнопрстуфхцчшщъыьэюяўқғҳ";
constexpr std::u16string_view CYR_UPPER = u"АБВГДЕЁЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯЎҚҒҲ";
constexpr std::u16string_view LAT_LOWER = u"abcdefghijklmnopqrstuvwxyzöğşçōõ";
constexpr std::u16string_view LAT_UPPER = u"ABCDEFGHIJKLMNOPQRSTUVWXYZÖĞŞÇŌÕ";
constexpr std::u16string_view APOS = u"'ʻʼ‘’`´"; // ' ʻ ʼ ‘ ’ ` ´
constexpr std::u16string_view CYR_VOWELS = u"аеёиоуэюяўы";
constexpr std::u16string_view LAT_VOWELS = u"aeiouöōõ";

enum : std::uint8_t {
    F_CYR = 1,
    F_CYR_UP = 2,
    F_LAT = 4,
    F_LAT_UP = 8,
    F_APOS = 16,
    F_CYR_VOWEL = 32, // set on both cases: the reference tests cyrLower(c)
    F_LAT_VOWEL = 64, // set on both cases: the reference tests latLower(c)
    F_SPACE = 128,    // JavaScript RegExp \s, for the URL / e-mail tokeniser (SPEC §5.6)
};

constexpr int CASE_N = 0x500; // every letter of the four alphabets is below U+0500

struct Tables
{
    std::array<std::uint8_t, 65536> flags{};
    std::array<char16_t, CASE_N> lower{};
    std::array<char16_t, CASE_N> upper{};
};

void fillTables(Tables &t)
{
    const auto mark = [&t](std::u16string_view set, std::uint8_t flag) {
        for (char16_t c : set)
            t.flags[c] |= flag;
    };
    mark(CYR_LOWER, F_CYR);
    mark(CYR_UPPER, F_CYR | F_CYR_UP);
    mark(LAT_LOWER, F_LAT);
    mark(LAT_UPPER, F_LAT | F_LAT_UP);
    mark(APOS, F_APOS);
    mark(CYR_VOWELS, F_CYR_VOWEL);
    mark(LAT_VOWELS, F_LAT_VOWEL);
    for (char16_t v : CYR_VOWELS)
        t.flags[CYR_UPPER[CYR_LOWER.find(v)]] |= F_CYR_VOWEL;
    for (char16_t v : LAT_VOWELS)
        t.flags[LAT_UPPER[LAT_LOWER.find(v)]] |= F_LAT_VOWEL;
    // RegExp \s: [\t\n\v\f\r \u00a0\u1680\u2000-\u200a\u2028\u2029\u202f\u205f\u3000\ufeff]
    for (char16_t c = 0x09; c <= 0x0D; ++c)
        t.flags[c] |= F_SPACE;
    for (char16_t c = 0x2000; c <= 0x200A; ++c)
        t.flags[c] |= F_SPACE;
    for (char16_t c : {char16_t(0x20), char16_t(0xA0), char16_t(0x1680), char16_t(0x2028), char16_t(0x2029),
                       char16_t(0x202F), char16_t(0x205F), char16_t(0x3000), char16_t(0xFEFF)})
        t.flags[c] |= F_SPACE;
    for (int c = 0; c < CASE_N; ++c) {
        t.lower[c] = char16_t(c);
        t.upper[c] = char16_t(c);
    }
    for (std::size_t k = 0; k < CYR_LOWER.size(); ++k) {
        t.lower[CYR_UPPER[k]] = CYR_LOWER[k];
        t.upper[CYR_LOWER[k]] = CYR_UPPER[k];
    }
    for (std::size_t k = 0; k < LAT_LOWER.size(); ++k) {
        t.lower[LAT_UPPER[k]] = LAT_LOWER[k];
        t.upper[LAT_LOWER[k]] = LAT_UPPER[k];
    }
}

const Tables &tables()
{
    static const Tables *const t = [] {
        static Tables storage;
        fillTables(storage);
        return &storage;
    }();
    return *t;
}

inline std::uint8_t fl(QChar c)
{
    return tables().flags[c.unicode()];
}

// ---------------------------------------------------------------- tables (reference C2L / L2C)
QStringView c2l(char16_t L)
{
    switch (L) {
    case u'а': return u"a";
    case u'б': return u"b";
    case u'в': return u"v";
    case u'г': return u"g";
    case u'д': return u"d";
    case u'ж': return u"j";
    case u'з': return u"z";
    case u'и': return u"i";
    case u'й': return u"y";
    case u'к': return u"k";
    case u'л': return u"l";
    case u'м': return u"m";
    case u'н': return u"n";
    case u'о': return u"o";
    case u'п': return u"p";
    case u'р': return u"r";
    case u'т': return u"t";
    case u'у': return u"u";
    case u'ф': return u"f";
    case u'х': return u"x";
    case u'қ': return u"q";
    case u'ҳ': return u"h";
    case u'э': return u"e";
    case u'ы': return u"i";
    case u'ё': return u"yo";
    case u'ю': return u"yu";
    case u'я': return u"ya";
    default: return QStringView(); // undefined
    }
}

char16_t l2c(char16_t L)
{
    switch (L) {
    case u'a': return u'а';
    case u'b': return u'б';
    case u'd': return u'д';
    case u'f': return u'ф';
    case u'g': return u'г';
    case u'h': return u'ҳ';
    case u'i': return u'и';
    case u'j': return u'ж';
    case u'k': return u'к';
    case u'l': return u'л';
    case u'm': return u'м';
    case u'n': return u'н';
    case u'o': return u'о';
    case u'p': return u'п';
    case u'q': return u'қ';
    case u'r': return u'р';
    case u's': return u'с';
    case u't': return u'т';
    case u'u': return u'у';
    case u'v': return u'в';
    case u'x': return u'х';
    case u'y': return u'й';
    case u'z': return u'з';
    case u'c': return u'ц';
    case u'w': return u'в';
    case u'ö': return u'ў';
    case u'ō': return u'ў';
    case u'õ': return u'ў';
    case u'ğ': return u'ғ';
    case u'ş': return u'ш';
    case u'ç': return u'ч';
    default: return 0; // undefined
    }
}

// ---------------------------------------------------------------- dictionary (SPEC §6)
// Latin → Cyrillic stems. Keys: lowercase, ASCII apostrophe.
constexpr std::u16string_view DICT_SRC =
    u"obyekt объект|subyekt субъект|adyutant адъютант|inyeksiya инъекция|konyunktura конъюнктура|"
    u"kompyuter компьютер|intervyu интервью|premyera премьера|batalyon батальон|bulyon бульон|medalyon медальон|"
    u"shampinyon шампиньон|kanyon каньон|senyor сеньор|tatyana татьяна|ilya илья|nyuton ньютон|"
    u"yod йод|yoga йога|yogurt йогурт|york йорк|yota йота|"
    u"sirk цирк|sement цемент|senzura цензура|sentner центнер|sentr центр|sex цех|sikl цикл|silindr цилиндр|"
    u"sisterna цистерна|sitata цитата|sitrus цитрус|sellofan целлофан|sellyuloza целлюлоза|selsiy цельсий|"
    u"seremoniya церемония|sivilizatsiya цивилизация|sianid цианид|sink цинк|sirkul циркуль|sokol цоколь|sunami цунами|sitadel цитадель|"
    u"leksiya лекция|aksiya акция|funksiya функция|seksiya секция|fraksiya фракция|reaksiya реакция|sanksiya санкция|"
    u"konstruksiya конструкция|produksiya продукция|redaksiya редакция|kolleksiya коллекция|infeksiya инфекция|"
    u"proporsiya пропорция|porsiya порция|konferensiya конференция|litsenziya лицензия|litsey лицей|ofitser офицер|"
    u"protsent процент|protsess процесс|protsedura процедура|konsert концерт|konsepsiya концепция|konsentratsiya концентрация|"
    u"konsern концерн|potensial потенциал|differensial дифференциал|sotsial социал|sotsiologiya социология|spetsial специал|spetsifik специфик|"
    u"kvarts кварц|shprits шприц|plats плац|blits блиц";

struct DictEntry
{
    QString key;
    QString value;
};

struct Dictionary
{
    std::vector<DictEntry> entries;                // sorted by (first letter, length descending)
    std::array<std::pair<int, int>, 26> buckets{}; // [begin, end) per first letter a–z
};

const Dictionary &dictionary()
{
    static const Dictionary d = [] {
        Dictionary dict;
        std::size_t pos = 0;
        while (pos < DICT_SRC.size()) {
            std::size_t end = DICT_SRC.find(u'|', pos);
            if (end == std::u16string_view::npos)
                end = DICT_SRC.size();
            const std::u16string_view item = DICT_SRC.substr(pos, end - pos);
            const std::size_t sp = item.find(u' ');
            dict.entries.push_back({QString::fromUtf16(item.data(), qsizetype(sp)),
                                    QString::fromUtf16(item.data() + sp + 1, qsizetype(item.size() - sp - 1))});
            pos = end + 1;
        }
        // the first prefix hit in a bucket is the longest key (the reference sorts all keys longest first; only
        // keys with the word's first letter can be its prefix, and two keys of one length cannot both be)
        std::stable_sort(dict.entries.begin(), dict.entries.end(), [](const DictEntry &a, const DictEntry &b) {
            if (a.key.front() != b.key.front())
                return a.key.front() < b.key.front();
            return a.key.size() > b.key.size();
        });
        for (auto &b : dict.buckets)
            b = {0, 0};
        for (int k = 0; k < int(dict.entries.size()); ++k) {
            const int f = dict.entries[std::size_t(k)].key.front().unicode() - u'a';
            if (f < 0 || f >= 26)
                continue;
            auto &b = dict.buckets[std::size_t(f)];
            if (b.second == 0)
                b.first = k;
            b.second = k + 1;
        }
        return dict;
    }();
    return d;
}

// longest dictionary key that is a prefix of the normalised word, or nullptr
const DictEntry *dictLookup(const QString &key)
{
    if (key.isEmpty())
        return nullptr;
    const int f = key.front().unicode() - u'a';
    if (f < 0 || f >= 26)
        return nullptr;
    const Dictionary &d = dictionary();
    const auto [begin, end] = d.buckets[std::size_t(f)];
    for (int k = begin; k < end; ++k) {
        const DictEntry &e = d.entries[std::size_t(k)];
        if (key.startsWith(e.key))
            return &e;
    }
    return nullptr;
}

// ---------------------------------------------------------------- small helpers
inline QChar charAt(QStringView text, qsizetype i) // text.charAt(i), or "no character"
{
    return i >= 0 && i < text.size() ? text[i] : QChar();
}

inline QChar upperChar(QChar c) // latUpper(cyrUpper(c))
{
    return detail::latUpper(detail::cyrUpper(c));
}

QString upperStr(QStringView s)
{
    QString o;
    o.reserve(s.size());
    for (QChar ch : s)
        o += upperChar(ch);
    return o;
}

QString upperFirst(QStringView s)
{
    if (s.isEmpty())
        return QString();
    QString o;
    o.reserve(s.size());
    o += upperChar(s.front());
    o += s.sliced(1);
    return o;
}

// "ts" + rest: `rest = text.substr(i + 2, 3).toLowerCase()` in the reference. Only the ASCII letters I Y A O N
// lower to i y a o n (İ lowers to "i" + U+0307, which can never continue "iya"/"ion"), so ASCII lowering is exact.
inline char16_t asciiLower(QChar c)
{
    const char16_t u = c.unicode();
    return u >= u'A' && u <= u'Z' ? char16_t(u + 0x20) : u;
}

// normKey of one source character: how many key code units it produces
inline qsizetype normLen(QChar c)
{
    const char16_t L = detail::latLower(c).unicode();
    return L == u'ö' || L == u'ō' || L == u'õ' || L == u'ğ' || L == u'ş' || L == u'ç' ? 2 : 1;
}

// URL prefixes of SPEC §5.6: "http://", "https://", "www." (case-sensitive, like the reference RegExp)
qsizetype urlPrefix(QStringView t, qsizetype p)
{
    const qsizetype n = t.size();
    if (p + 4 <= n && t[p] == u'w' && t[p + 1] == u'w' && t[p + 2] == u'w' && t[p + 3] == u'.')
        return 4;
    if (p + 7 <= n && t[p] == u'h' && t[p + 1] == u't' && t[p + 2] == u't' && t[p + 3] == u'p') {
        qsizetype q = p + 4;
        if (t[q] == u's')
            ++q;
        if (q + 3 <= n && t[q] == u':' && t[q + 1] == u'/' && t[q + 2] == u'/')
            return q + 3 - p;
    }
    return 0;
}

} // namespace

// ---------------------------------------------------------------- character classes
namespace detail {

bool isCyr(QChar c) { return (fl(c) & F_CYR) != 0; }
bool isCyrUpper(QChar c) { return (fl(c) & F_CYR_UP) != 0; }
bool isCyrVowel(QChar c) { return (fl(c) & F_CYR_VOWEL) != 0; }
bool isLat(QChar c) { return (fl(c) & F_LAT) != 0; }
bool isLatUpper(QChar c) { return (fl(c) & F_LAT_UP) != 0; }
bool isLatVowel(QChar c) { return (fl(c) & F_LAT_VOWEL) != 0; }
bool isApos(QChar c) { return (fl(c) & F_APOS) != 0; }
bool isLetter(QChar c) { return (fl(c) & (F_CYR | F_LAT)) != 0; }
bool isUpperLetter(QChar c) { return (fl(c) & (F_CYR_UP | F_LAT_UP)) != 0; }
bool isJsSpace(QChar c) { return (fl(c) & F_SPACE) != 0; }

bool isJsWordChar(QChar c)
{
    const char16_t u = c.unicode();
    return (u >= u'0' && u <= u'9') || (u >= u'A' && u <= u'Z') || (u >= u'a' && u <= u'z') || u == u'_';
}

QChar cyrLower(QChar c) { return isCyrUpper(c) ? QChar(tables().lower[c.unicode()]) : c; }
QChar cyrUpper(QChar c) { return (fl(c) & (F_CYR | F_CYR_UP)) == F_CYR ? QChar(tables().upper[c.unicode()]) : c; }
QChar latLower(QChar c) { return isLatUpper(c) ? QChar(tables().lower[c.unicode()]) : c; }
QChar latUpper(QChar c) { return (fl(c) & (F_LAT | F_LAT_UP)) == F_LAT ? QChar(tables().upper[c.unicode()]) : c; }

// ---------------------------------------------------------------- casing rule (SPEC §4)
bool nextLetterIsUpper(QStringView text, qsizetype i)
{
    const qsizetype n = text.size();
    qsizetype j = i + 1;
    if (j < n && isApos(text[j]))
        ++j;
    if (j < n && isLetter(text[j]))
        return isUpperLetter(text[j]);
    qsizetype k = i - 1;
    if (k >= 0 && isApos(text[k]))
        --k;
    if (k >= 0 && isLetter(text[k]))
        return isUpperLetter(text[k]);
    return false;
}

void caseOut(QStringView text, qsizetype i, bool srcUpper, QStringView out, QString &dst)
{
    if (!srcUpper || out.isEmpty()) {
        dst += out;
        return;
    }
    if (out.size() == 1) {
        dst += upperChar(out.front());
        return;
    }
    if (nextLetterIsUpper(text, i)) {
        for (QChar ch : out)
            dst += upperChar(ch);
    } else {
        dst += upperChar(out.front());
        dst += out.sliced(1);
    }
}

// ---------------------------------------------------------------- Cyrillic → Latin (SPEC §5.1)
QString cyrToLatin(QStringView text, Script target, const Options &o)
{
    const bool isNew = target == Script::New;
    const QString oOkina = QStringLiteral("o") + o.okina;
    const QString gOkina = QStringLiteral("g") + o.okina;
    const QString sTutuq = QStringLiteral("s") + o.tutuq;
    QString out;
    out.reserve(text.size() + text.size() / 4);
    const qsizetype n = text.size();
    for (qsizetype i = 0; i < n; ++i) {
        const QChar c = text[i];
        if (!isCyr(c)) {
            out += c;
            continue;
        }
        const char16_t L = cyrLower(c).unicode();
        const bool up = isCyrUpper(c);
        const QChar P = charAt(text, i - 1);
        const QChar N = charAt(text, i + 1);
        QStringView r;
        switch (L) {
        case u'е': {
            const char16_t pl = cyrLower(P).unicode();
            r = (!isCyr(P) || isCyrVowel(P) || pl == u'ъ' || pl == u'ь') ? QStringView(u"ye") : QStringView(u"e");
            break;
        }
        case u'ц':
            r = isCyrVowel(P) ? QStringView(u"ts") : QStringView(u"s");
            break;
        case u'ъ': {
            const char16_t nl = cyrLower(N).unicode();
            if (nl == u'е' || nl == u'ё' || nl == u'ю' || nl == u'я')
                r = QStringView(u"");
            else if (cyrLower(P) == u'ў' && o.dropHardSignAfterO)
                r = QStringView(u"");
            else
                r = o.tutuq;
            break;
        }
        case u'ь':
            r = QStringView(u"");
            break;
        case u'ш':
        case u'щ':
            r = isNew ? QStringView(u"ş") : QStringView(u"sh");
            break;
        case u'ч':
            r = isNew ? QStringView(u"ç") : QStringView(u"ch");
            break;
        case u'ў':
            r = isNew ? QStringView(u"ö") : QStringView(oOkina);
            break;
        case u'ғ':
            r = isNew ? QStringView(u"ğ") : QStringView(gOkina);
            break;
        case u'с': // с(+ҳ): Исҳоқ → Isʼhoq; new: Ishoq
            r = (!isNew && cyrLower(N) == u'ҳ') ? QStringView(sTutuq) : QStringView(u"s");
            break;
        default:
            r = c2l(L);
            if (r.isNull())
                r = QStringView(&c, 1);
        }
        caseOut(text, i, up, r, out);
    }
    return out;
}

// ---------------------------------------------------------------- Latin → Cyrillic (SPEC §5.2)
QString latinToCyrScan(QStringView text, Script source, const Options &o, QChar prevCtx)
{
    const bool isNew = source == Script::New;
    QString out;
    out.reserve(text.size());
    const qsizetype n = text.size();
    const auto prevChar = [&](qsizetype idx) { return idx > 0 ? text[idx - 1] : prevCtx; };
    qsizetype i = 0;
    while (i < n) {
        const QChar c = text[i];
        if (isApos(c)) {
            const QChar pc = prevChar(i);
            const QChar nc = charAt(text, i + 1);
            if (isLat(pc) && isLat(nc))
                out += isLatUpper(pc) ? u'Ъ' : u'ъ'; // maʼno → маъно
            else if (isLat(pc) && c == TUTUQ)
                out += isLatUpper(pc) ? u'Ъ' : u'ъ'; // explicit word-final tutuq
            else
                out += c; // quotes stay quotes
            ++i;
            continue;
        }
        if (!isLat(c)) {
            out += c;
            ++i;
            continue;
        }
        const char16_t L = latLower(c).unicode();
        const bool up = isLatUpper(c);
        const QChar N = charAt(text, i + 1);
        const QChar N2 = charAt(text, i + 2);
        const char16_t NL = latLower(N).unicode();
        const QChar P = prevChar(i);
        const bool prevIsLetter = isLat(P);
        const bool prevIsVowelOrApos = isLatVowel(P) || isApos(P);
        const auto put = [&](char16_t lower, char16_t upper) { out += QChar(up ? upper : lower); };

        if (L == u'o' && isApos(N)) { put(u'ў', u'Ў'); i += 2; continue; }
        if (L == u'g' && isApos(N)) { put(u'ғ', u'Ғ'); i += 2; continue; }
        if (L == u's') {
            if (NL == u'h' && !isNew) { put(u'ш', u'Ш'); i += 2; continue; }
            if (isApos(N) && latLower(N2) == u'h') { put(u'с', u'С'); i += 2; continue; }
        }
        if (L == u'c' && NL == u'h') { put(u'ч', u'Ч'); i += 2; continue; }
        if (L == u'y' && (NL == u'o' || NL == u'u' || NL == u'a' || NL == u'e')) {
            if (NL == u'o' && isApos(N2)) { put(u'й', u'Й'); i += 1; continue; } // yoʻl → йўл
            if (NL == u'e') {
                if (!prevIsLetter || prevIsVowelOrApos) {
                    put(u'е', u'Е');
                } else {
                    put(u'ь', u'Ь');
                    put(u'е', u'Е');
                }
            } else if (NL == u'o') {
                put(u'ё', u'Ё');
            } else if (NL == u'u') {
                put(u'ю', u'Ю');
            } else {
                put(u'я', u'Я');
            }
            i += 2;
            continue;
        }
        if (L == u'e') {
            if (!prevIsLetter || prevIsVowelOrApos)
                put(u'э', u'Э');
            else
                put(u'е', u'Е');
            ++i;
            continue;
        }
        if (L == u't' && NL == u's') {
            const char16_t r0 = asciiLower(charAt(text, i + 2));
            const char16_t r1 = asciiLower(charAt(text, i + 3));
            const char16_t r2 = asciiLower(charAt(text, i + 4));
            if (r0 == u'i' && ((r1 == u'y' && r2 == u'a') || (r1 == u'o' && r2 == u'n'))) { // militsiya, ratsion
                put(u'ц', u'Ц');
                i += 2;
                continue;
            }
            const bool wordEnds = i + 2 >= n || !isLat(text[i + 2]);
            if (o.tsFinal && wordEnds && isLatVowel(P)) { // abzats
                put(u'ц', u'Ц');
                i += 2;
                continue;
            }
            // otherwise fall through: native oʻtsa, ketsa, aytsin keep т+с
        }
        const char16_t r = l2c(L);
        if (r == 0) {
            out += c;
            ++i;
            continue;
        }
        out += up ? cyrUpper(QChar(r)) : QChar(r);
        ++i;
    }
    return out;
}

QString normKey(QStringView word)
{
    QString o;
    o.reserve(word.size() + 4);
    for (QChar ch : word) {
        const QChar c = latLower(ch);
        const char16_t u = c.unicode();
        if (isApos(c))
            o += u'\'';
        else if (u == u'ö' || u == u'ō' || u == u'õ')
            o += QStringView(u"o'");
        else if (u == u'ğ')
            o += QStringView(u"g'");
        else if (u == u'ş')
            o += QStringView(u"sh");
        else if (u == u'ç')
            o += QStringView(u"ch");
        else
            o += c;
    }
    return o;
}

QString convertWordWithDict(QStringView word, Script source, const Options &o)
{
    const DictEntry *hit = dictLookup(normKey(word));
    if (!hit)
        return latinToCyrScan(word, source, o, QChar());
    // how many source characters does the stem cover? (normKey may expand ö→o', ş→sh …)
    qsizetype consumed = 0;
    qsizetype built = 0;
    while (built < hit->key.size() && consumed < word.size()) {
        built += normLen(word[consumed]);
        ++consumed;
    }
    const QStringView stemSrc = word.first(consumed);
    const QStringView rest = word.sliced(consumed);
    // casing
    int letters = 0;
    int uppers = 0;
    bool firstUpper = false;
    for (QChar ch : stemSrc) {
        if (isLat(ch)) {
            ++letters;
            if (isLatUpper(ch)) {
                ++uppers;
                if (letters == 1)
                    firstUpper = true;
            }
        }
    }
    QString cyrStem;
    if (letters >= 2 && uppers == letters)
        cyrStem = upperStr(hit->value);
    else if (firstUpper)
        cyrStem = upperFirst(hit->value);
    else
        cyrStem = hit->value;
    return cyrStem + latinToCyrScan(rest, source, o, stemSrc.back());
}

QString latinToCyr(QStringView text, Script source, const Options &o)
{
    if (!o.dictionary)
        return latinToCyrScan(text, source, o, QChar());
    QString out;
    out.reserve(text.size());
    const qsizetype n = text.size();
    qsizetype i = 0;
    while (i < n) {
        const QChar c = text[i];
        if (!isLat(c) && !isApos(c)) {
            out += c;
            ++i;
            continue;
        }
        qsizetype j = i;
        while (j < n && (isLat(text[j]) || isApos(text[j])))
            ++j;
        out += convertWordWithDict(text.sliced(i, j - i), source, o);
        i = j;
    }
    return out;
}

// ---------------------------------------------------------------- Latin 1995 → Latin 2026 (SPEC §5.3)
QString latToNew(QStringView text, const Options &o)
{
    QString out;
    out.reserve(text.size());
    const qsizetype n = text.size();
    qsizetype i = 0;
    while (i < n) {
        const QChar c = text[i];
        const char16_t L = latLower(c).unicode();
        const bool up = isLatUpper(c);
        const QChar N = charAt(text, i + 1);
        const char16_t NL = latLower(N).unicode();
        const QChar N2 = charAt(text, i + 2);
        if (isApos(c)) {
            const QChar pc = charAt(text, i - 1);
            if (isLat(pc) && isLat(N))
                out += o.tutuq;
            else
                out += c;
            ++i;
            continue;
        }
        if (!isLat(c)) { out += c; ++i; continue; }
        if (L == u'o' && isApos(N)) { out += up ? u'Ö' : u'ö'; i += 2; continue; }
        if (L == u'g' && isApos(N)) { out += up ? u'Ğ' : u'ğ'; i += 2; continue; }
        if (L == u's' && NL == u'h') { out += up ? u'Ş' : u'ş'; i += 2; continue; }
        if (L == u's' && isApos(N) && latLower(N2) == u'h') { out += c; i += 2; continue; } // Isʼhoq → Ishoq
        if (L == u'c' && NL == u'h') { out += up ? u'Ç' : u'ç'; i += 2; continue; }
        if (L == u'ō' || L == u'õ') { out += up ? u'Ö' : u'ö'; ++i; continue; }
        out += c;
        ++i;
    }
    return out;
}

// ---------------------------------------------------------------- Latin 2026 → Latin 1995 (SPEC §5.4)
QString newToLat(QStringView text, const Options &o)
{
    QString out;
    out.reserve(text.size() + text.size() / 4);
    const qsizetype n = text.size();
    qsizetype i = 0;
    while (i < n) {
        const QChar c = text[i];
        const char16_t L = latLower(c).unicode();
        const bool up = isLatUpper(c);
        const QChar N = charAt(text, i + 1);
        const char16_t NL = latLower(N).unicode();
        if (isApos(c)) {
            const QChar pc = charAt(text, i - 1);
            if (isLat(pc) && isLat(N))
                out += o.tutuq;
            else
                out += c;
            ++i;
            continue;
        }
        if (!isLat(c)) { out += c; ++i; continue; }
        if (L == u'ö' || L == u'ō' || L == u'õ') { out += up ? u'O' : u'o'; out += o.okina; ++i; continue; }
        if (L == u'ğ') { out += up ? u'G' : u'g'; out += o.okina; ++i; continue; }
        if (L == u'ş') { caseOut(text, i, up, u"sh", out); ++i; continue; }
        if (L == u'ç') { caseOut(text, i, up, u"ch", out); ++i; continue; }
        if (L == u's' && NL == u'h') { out += c; out += o.tutuq; ++i; continue; } // Ishoq → Isʼhoq
        out += c;
        ++i;
    }
    return out;
}

// ---------------------------------------------------------------- URL / e-mail protection (SPEC §5.6)
// Equivalent to the reference /(https?:\/\/|www\.)\S+|\S+@\S+\.\S+|@\w+/g with JavaScript's \s and \w, scanned by
// index like core/wasm (QRegularExpression's \s and \w are Unicode classes and would differ): at each position
// the alternatives are tried in order, the text between tokens is converted, the tokens are copied unchanged.
QString withSkips(QStringView text, const std::function<QString(QStringView)> &fn)
{
    QString out;
    out.reserve(text.size() + text.size() / 4);
    const qsizetype n = text.size();
    qsizetype last = 0;
    qsizetype p = 0;
    qsizetype runEnd = -1;
    qsizetype runAt = -1;
    while (p < n) {
        const QChar c = text[p];
        if (isJsSpace(c)) {
            ++p;
            continue;
        }
        if (p >= runEnd) {
            // a new run of non-space characters: \S+@\S+\.\S+ matches from p to the run end
            // iff some '@' at x >= p+1 is followed by a '.' at y >= x+2 with y <= runEnd-2
            runEnd = p;
            while (runEnd < n && !isJsSpace(text[runEnd]))
                ++runEnd;
            qsizetype dot = -1;
            for (qsizetype k = runEnd - 2; k >= p; --k) {
                if (text[k] == u'.') {
                    dot = k;
                    break;
                }
            }
            runAt = -1;
            for (qsizetype k = dot - 2; k >= p; --k) {
                if (text[k] == u'@') {
                    runAt = k;
                    break;
                }
            }
        }
        qsizetype mEnd = -1;
        const qsizetype pre = urlPrefix(text, p);
        if (pre > 0 && p + pre < runEnd) {
            mEnd = runEnd; // (https?:\/\/|www\.)\S+
        } else if (runAt >= p + 1) {
            mEnd = runEnd; // \S+@\S+\.\S+
        } else if (c == u'@' && p + 1 < n && isJsWordChar(text[p + 1])) {
            mEnd = p + 2; // @\w+
            while (mEnd < n && isJsWordChar(text[mEnd]))
                ++mEnd;
        }
        if (mEnd < 0) {
            ++p;
            continue;
        }
        out += fn(text.sliced(last, p - last));
        out += text.sliced(p, mEnd - p);
        last = mEnd;
        p = mEnd;
    }
    out += fn(text.sliced(last));
    return out;
}

} // namespace detail

// ---------------------------------------------------------------- detection (SPEC §5.5)
Script detect(QStringView text)
{
    using namespace detail;
    int cyr = 0;
    int lat = 0;
    int nw = 0;
    int dig = 0;
    const qsizetype n = text.size();
    for (qsizetype i = 0; i < n; ++i) {
        const QChar c = text[i];
        if (isCyr(c)) {
            ++cyr;
            continue;
        }
        if (!isLat(c))
            continue;
        ++lat;
        const char16_t L = latLower(c).unicode();
        if (L == u'ö' || L == u'ğ' || L == u'ş' || L == u'ç' || L == u'ō' || L == u'õ')
            ++nw;
        const QChar N = charAt(text, i + 1);
        const char16_t NL = latLower(N).unicode();
        if ((L == u's' || L == u'c') && NL == u'h')
            ++dig;
        if ((L == u'o' || L == u'g') && isApos(N))
            ++dig;
    }
    if (cyr > lat)
        return Script::Cyr;
    if (nw > 0 && nw >= dig)
        return Script::New;
    return Script::Lat;
}

// ---------------------------------------------------------------- public API
Options Options::ascii()
{
    Options o;
    o.okina = QStringLiteral("'");
    o.tutuq = QStringLiteral("'");
    return o;
}

QString scriptId(Script script)
{
    switch (script) {
    case Script::Cyr: return QStringLiteral("cyr");
    case Script::Lat: return QStringLiteral("lat");
    case Script::New: return QStringLiteral("new");
    case Script::Auto: break;
    }
    return QStringLiteral("auto");
}

bool scriptFromId(QStringView id, Script *script)
{
    Script s;
    if (id == u"cyr")
        s = Script::Cyr;
    else if (id == u"lat")
        s = Script::Lat;
    else if (id == u"new")
        s = Script::New;
    else if (id == u"auto")
        s = Script::Auto;
    else
        return false;
    if (script)
        *script = s;
    return true;
}

QString convert(QStringView text, Script from, Script to, const Options &o)
{
    if (to == Script::Auto)
        throw std::invalid_argument("UzTranslit: the target script cannot be auto");
    if (from == Script::Auto)
        from = detect(text);
    if (from == to)
        return text.toString();
    std::function<QString(QStringView)> fn;
    if (from == Script::Cyr && (to == Script::Lat || to == Script::New))
        fn = [to, &o](QStringView s) { return detail::cyrToLatin(s, to, o); };
    else if ((from == Script::Lat || from == Script::New) && to == Script::Cyr)
        fn = [from, &o](QStringView s) { return detail::latinToCyr(s, from, o); };
    else if (from == Script::Lat && to == Script::New)
        fn = [&o](QStringView s) { return detail::latToNew(s, o); };
    else if (from == Script::New && to == Script::Lat)
        fn = [&o](QStringView s) { return detail::newToLat(s, o); };
    else
        throw std::invalid_argument("UzTranslit: unknown direction");
    return o.skipUrls ? detail::withSkips(text, fn) : fn(text);
}

QString convert(QStringView text, QStringView from, QStringView to, const Options &o)
{
    // the reference order: auto is resolved first, then from == to returns the text, then the direction is checked
    QString source = from.toString();
    if (source == u"auto")
        source = scriptId(detect(text));
    if (source == to)
        return text.toString();
    Script f;
    Script t;
    if (!scriptFromId(source, &f) || f == Script::Auto || !scriptFromId(to, &t) || t == Script::Auto) {
        throw std::invalid_argument(("UzTranslit: unknown direction " + source + " -> " + to.toString())
                                        .toStdString());
    }
    return convert(text, f, t, o);
}

QString cyrToLat(QStringView t, const Options &o) { return convert(t, Script::Cyr, Script::Lat, o); }
QString cyrToNew(QStringView t, const Options &o) { return convert(t, Script::Cyr, Script::New, o); }
QString latToCyr(QStringView t, const Options &o) { return convert(t, Script::Lat, Script::Cyr, o); }
QString newToCyr(QStringView t, const Options &o) { return convert(t, Script::New, Script::Cyr, o); }
QString latToNew(QStringView t, const Options &o) { return convert(t, Script::Lat, Script::New, o); }
QString newToLat(QStringView t, const Options &o) { return convert(t, Script::New, Script::Lat, o); }

} // namespace uztranslit
