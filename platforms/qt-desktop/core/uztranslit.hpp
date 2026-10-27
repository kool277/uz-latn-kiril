// UzTranslit — C++/Qt port of spec/SPEC.md v1.0.0.
//
// A faithful port of SPEC §5 with the helper names of the reference core/js/uztranslit.js (isCyr, isLat, isApos,
// nextLetterIsUpper, caseOut, cyrToLatin, latinToCyrScan, convertWordWithDict, latToNew, newToLat, detect).
// Text is iterated in UTF-16 code units (QChar), exactly like JavaScript strings; every letter that matters is in
// the BMP. Only Qt Core is needed. MIT License.
#pragma once

#include <QString>
#include <QStringView>

#include <functional>

namespace uztranslit {

inline constexpr char VERSION[] = "1.1.0";
inline constexpr char16_t OKINA = u'ʻ'; // okina, used in Oʻ Gʻ
inline constexpr char16_t TUTUQ = u'ʼ'; // tutuq belgisi

enum class Script { Cyr, Lat, New, Auto };

// "cyr", "lat", "new", "auto"
QString scriptId(Script script);
// Parses "cyr" / "lat" / "new" / "auto"; returns false for anything else.
bool scriptFromId(QStringView id, Script *script);

// SPEC §2 options; the defaults are the spec defaults.
struct Options
{
    QString okina = QString(QChar(OKINA)); // mark in Oʻ/Gʻ output ("'" for ASCII); 0 or 1 characters in every UI
    QString tutuq = QString(QChar(TUTUQ)); // mark for ъ / tutuq output ("'" for ASCII)
    bool dropHardSignAfterO = true;        // ўъ → oʻ / ö
    bool tsFinal = true;                   // Latin word-final ts after a vowel → ц
    bool dictionary = true;                // SPEC §6 stems in Latin → Cyrillic
    bool skipUrls = true;                  // leave URLs, e-mails and @handles unchanged (SPEC §5.6)

    static Options ascii(); // okina and tutuq both "'"
};

// convert(text, from, to, options): from may be Script::Auto (detected); from == to returns the text unchanged.
// Throws std::invalid_argument when `to` is Script::Auto.
QString convert(QStringView text, Script from, Script to, const Options &options = Options());
// The same with script ids, like the reference API; throws std::invalid_argument for an unknown id or direction.
QString convert(QStringView text, QStringView from, QStringView to, const Options &options = Options());

// SPEC §5.5: Script::Cyr, Script::Lat or Script::New (Lat for empty or letterless text).
Script detect(QStringView text);

QString cyrToLat(QStringView text, const Options &options = Options());
QString cyrToNew(QStringView text, const Options &options = Options());
QString latToCyr(QStringView text, const Options &options = Options());
QString newToCyr(QStringView text, const Options &options = Options());
QString latToNew(QStringView text, const Options &options = Options());
QString newToLat(QStringView text, const Options &options = Options());

// SPEC §5 building blocks, exposed for tests and for callers that tokenise text themselves.
// "No character" (before the start, after the end of the text) is QChar(): U+0000 is in no character class,
// so every check below treats it exactly like the reference treats "".
namespace detail {

bool isCyr(QChar c);
bool isCyrUpper(QChar c);
bool isCyrVowel(QChar c);
bool isLat(QChar c);
bool isLatUpper(QChar c);
bool isLatVowel(QChar c);
bool isApos(QChar c);
bool isLetter(QChar c);
bool isUpperLetter(QChar c);
bool isJsSpace(QChar c);    // JavaScript RegExp \s
bool isJsWordChar(QChar c); // JavaScript RegExp \w: [A-Za-z0-9_]
QChar cyrLower(QChar c);
QChar cyrUpper(QChar c);
QChar latLower(QChar c);
QChar latUpper(QChar c);

// SPEC §4
bool nextLetterIsUpper(QStringView text, qsizetype i);
// Appends `out` with the casing of the source letter text[i] to `dst`.
void caseOut(QStringView text, qsizetype i, bool srcUpper, QStringView out, QString &dst);

// SPEC §5.1 (target Lat or New)
QString cyrToLatin(QStringView text, Script target, const Options &o);
// SPEC §5.2 scanner; prevCtx is the character before `text` (QChar() for none)
QString latinToCyrScan(QStringView text, Script source, const Options &o, QChar prevCtx = QChar());
// SPEC §5.2 with the dictionary pre-pass when o.dictionary is set
QString latinToCyr(QStringView text, Script source, const Options &o);
QString convertWordWithDict(QStringView word, Script source, const Options &o);
QString normKey(QStringView word);
// SPEC §5.3 / §5.4
QString latToNew(QStringView text, const Options &o);
QString newToLat(QStringView text, const Options &o);
// SPEC §5.6: fn converts the text between the URL / e-mail / @handle tokens, the tokens are copied unchanged.
QString withSkips(QStringView text, const std::function<QString(QStringView)> &fn);

} // namespace detail
} // namespace uztranslit
