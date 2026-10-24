#include "documents.hpp"

#include <QFileInfo>
#include <QHash>
#include <QRegularExpression>
#include <QSet>
#include <QXmlStreamReader>
#include <QXmlStreamWriter>

#include <exception>
#include <functional>
#include <vector>

using uztranslit::Options;
using uztranslit::Script;

namespace uzt {
namespace {

// A range of the source document and the text it stands for (escapes decoded).
struct Segment
{
    qsizetype start = 0;
    qsizetype end = 0;
    QString text;
    bool unicodeEscapes = false; // JSON: the string spelled non-ASCII characters as \uXXXX
};

using Escape = std::function<QString(const QString &converted, const Segment &segment)>;

QString keepAsIs(const QString &s, const Segment &)
{
    return s;
}

Script resolveSource(const std::vector<Segment> &segments, Script from)
{
    if (from != Script::Auto)
        return from;
    QString all;
    for (const Segment &s : segments) {
        all += s.text;
        all += u'\n'; // no digraph across two segments
    }
    return uztranslit::detect(all);
}

// Converts every segment on its own and rewrites only the segments whose text changed.
void convertSegments(const QString &src, const std::vector<Segment> &segments, Script from, Script to,
                     const Options &o, const Escape &escape, DocumentResult *result)
{
    from = resolveSource(segments, from);
    result->from = from;
    QString out;
    qsizetype pos = 0;
    bool changed = false;
    for (const Segment &s : segments) {
        const QString converted = uztranslit::convert(s.text, from, to, o);
        if (converted == s.text)
            continue;
        if (!changed)
            out.reserve(src.size() + src.size() / 8);
        out += QStringView(src).sliced(pos, s.start - pos);
        out += escape(converted, s);
        pos = s.end;
        changed = true;
    }
    if (!changed) {
        result->text = src;
        result->changed = false;
        return;
    }
    out += QStringView(src).sliced(pos);
    result->text = out;
    result->changed = out != src;
}

QString asciiLowered(QStringView s)
{
    QString o;
    o.reserve(s.size());
    for (QChar c : s)
        o += (c >= u'A' && c <= u'Z') ? QChar(c.unicode() + 0x20) : c;
    return o;
}

// ---------------------------------------------------------------- lines and protected spans
struct Line
{
    qsizetype start;
    qsizetype end;
};

std::vector<Line> splitLines(const QString &s) // at \r\n, \n or \r
{
    std::vector<Line> out;
    const qsizetype n = s.size();
    qsizetype pos = 0;
    for (qsizetype i = 0; i < n; ++i) {
        const QChar c = s[i];
        if (c != u'\n' && c != u'\r')
            continue;
        out.push_back({pos, i});
        if (c == u'\r' && i + 1 < n && s[i + 1] == u'\n')
            ++i;
        pos = i + 1;
    }
    out.push_back({pos, n});
    return out;
}

// Adds src[start, end) as segments, leaving out the spans matched by `protect`.
void addWithProtected(std::vector<Segment> &segs, const QString &src, qsizetype start, qsizetype end,
                      const QRegularExpression &protect)
{
    const QStringView line = QStringView(src).sliced(start, end - start);
    qsizetype pos = 0;
    QRegularExpressionMatchIterator it = protect.globalMatchView(line);
    while (it.hasNext()) {
        const QRegularExpressionMatch m = it.next();
        if (m.capturedLength() == 0)
            continue;
        if (m.capturedStart() > pos)
            segs.push_back({start + pos, start + m.capturedStart(), line.sliced(pos, m.capturedStart() - pos).toString()});
        pos = m.capturedEnd();
    }
    if (pos < line.size())
        segs.push_back({start + pos, end, line.sliced(pos).toString()});
}

// ---------------------------------------------------------------- Markdown
std::vector<Segment> collectMarkdown(const QString &src)
{
    // inline code, link/image destinations, reference labels, footnotes, autolinks and raw HTML tags
    static const QRegularExpression inlineSpans(
        QStringLiteral("(`+)[\\s\\S]*?\\1|\\]\\([^)\\s]*(?:\\s+\"[^\"]*\")?\\)|\\]\\[[^\\]]*\\]|\\[\\^[^\\]]*\\]|<[A-Za-z/!][^>]*>|<(?:https?|mailto|ftp):[^>]*>"));
    static const QRegularExpression frontMatter(QStringLiteral("^(---|\\+\\+\\+)\\s*$"));
    static const QRegularExpression fenceRe(QStringLiteral("^ {0,3}(`{3,}|~{3,})"));
    static const QRegularExpression listItem(QStringLiteral("^ {0,3}([-*+]|\\d{1,9}[.)])\\s"));
    static const QRegularExpression indented(QStringLiteral("^( {4}|\\t)"));
    static const QRegularExpression leadingSpace(QStringLiteral("^\\s"));
    static const QRegularExpression linkDefinition(QStringLiteral("^ {0,3}\\[[^\\]]+\\]:\\s*\\S"));

    std::vector<Segment> segs;
    const std::vector<Line> all = splitLines(src);
    const auto lineText = [&](std::size_t k) { return QStringView(src).sliced(all[k].start, all[k].end - all[k].start); };
    std::size_t i = 0;
    if (frontMatter.matchView(lineText(0)).hasMatch()) { // YAML/TOML front matter
        const QString fence = lineText(0).trimmed().toString();
        for (i = 1; i < all.size() && lineText(i).trimmed() != fence; ++i) {
        }
        i = i < all.size() ? i + 1 : 0; // unclosed: not front matter
    }
    QString fence;
    bool prevBlank = true;
    bool prevCode = false;
    bool inList = false;
    for (; i < all.size(); ++i) {
        const QStringView line = lineText(i);
        const QRegularExpressionMatch fm = fenceRe.matchView(line);
        if (!fence.isEmpty()) {
            if (fm.hasMatch() && fm.captured(1).front() == fence.front() && fm.capturedLength(1) >= fence.size()
                && line.trimmed() == fm.capturedView(1))
                fence.clear();
            continue;
        }
        if (fm.hasMatch()) {
            fence = fm.captured(1);
            continue;
        }
        const bool blank = line.trimmed().isEmpty();
        if (listItem.matchView(line).hasMatch())
            inList = true;
        else if (!blank && !leadingSpace.matchView(line).hasMatch())
            inList = false;
        const bool indentedCode = indented.matchView(line).hasMatch() && !blank && !inList && (prevBlank || prevCode);
        prevCode = indentedCode || (prevCode && blank);
        prevBlank = blank;
        if (indentedCode || blank)
            continue;
        if (linkDefinition.matchView(line).hasMatch())
            continue;
        addWithProtected(segs, src, all[i].start, all[i].end, inlineSpans);
    }
    return segs;
}

// ---------------------------------------------------------------- SubRip subtitles
std::vector<Segment> collectSrt(const QString &src)
{
    static const QRegularExpression tags(QStringLiteral("<[^>]*>|\\{[^}]*\\}|&(?:[a-zA-Z]+|#\\d+);"));
    static const QRegularExpression cueNumber(QStringLiteral("^\\s*\\d+\\s*$"));
    std::vector<Segment> segs;
    bool inCue = false;
    for (const Line &l : splitLines(src)) {
        const QStringView line = QStringView(src).sliced(l.start, l.end - l.start);
        if (line.trimmed().isEmpty()) {
            inCue = false;
            continue;
        }
        if (line.contains(QStringView(u"-->")) || (!inCue && cueNumber.matchView(line).hasMatch()))
            continue; // timing, cue number
        inCue = true;
        addWithProtected(segs, src, l.start, l.end, tags);
    }
    return segs;
}

// ---------------------------------------------------------------- JSON (string values, never keys)
bool isHex4(QStringView s)
{
    if (s.size() != 4)
        return false;
    for (QChar h : s) {
        if (!((h >= u'0' && h <= u'9') || (h >= u'a' && h <= u'f') || (h >= u'A' && h <= u'F')))
            return false;
    }
    return true;
}

// raw.replace(/\\(?:u([0-9a-fA-F]{4})|(.))/g, …) of the web app
QString decodeJsonString(QStringView raw)
{
    QString out;
    out.reserve(raw.size());
    const qsizetype n = raw.size();
    for (qsizetype i = 0; i < n; ++i) {
        const QChar c = raw[i];
        if (c != u'\\' || i + 1 >= n) {
            out += c;
            continue;
        }
        const QChar e = raw[i + 1];
        if (e == u'u' && i + 6 <= n && isHex4(raw.sliced(i + 2, 4))) {
            out += QChar(char16_t(raw.sliced(i + 2, 4).toUShort(nullptr, 16)));
            i += 5;
            continue;
        }
        if (e == u'\n' || e == u'\r' || e == u'\u2028' || e == u'\u2029') { // `.` stops at line terminators
            out += c;
            continue;
        }
        switch (e.unicode()) {
        case u'b': out += u'\b'; break;
        case u'f': out += u'\f'; break;
        case u'n': out += u'\n'; break;
        case u'r': out += u'\r'; break;
        case u't': out += u'\t'; break;
        default: out += e;
        }
        ++i;
    }
    return out;
}

QString encodeJsonString(const QString &s, bool unicodeEscapes)
{
    QString out;
    out.reserve(s.size() + 8);
    for (QChar c : s) {
        const char16_t u = c.unicode();
        switch (u) {
        case u'"': out += QStringView(u"\\\""); continue;
        case u'\\': out += QStringView(u"\\\\"); continue;
        case u'\n': out += QStringView(u"\\n"); continue;
        case u'\r': out += QStringView(u"\\r"); continue;
        case u'\t': out += QStringView(u"\\t"); continue;
        case u'\b': out += QStringView(u"\\b"); continue;
        case u'\f': out += QStringView(u"\\f"); continue;
        default: break;
        }
        if (u < 0x20 || u == 0x2028 || u == 0x2029 || (unicodeEscapes && u > 0x7F))
            out += QStringLiteral("\\u%1").arg(uint(u), 4, 16, QLatin1Char('0'));
        else
            out += c;
    }
    return out;
}

std::vector<Segment> collectJson(const QString &src)
{
    static const QRegularExpression nonAsciiEscape(QStringLiteral("\\\\u(?:00[89a-fA-F]|0[1-9a-fA-F]|[1-9a-fA-F])"));
    std::vector<Segment> segs;
    const qsizetype n = src.size();
    for (qsizetype i = 0; i < n; ++i) {
        if (src[i] != u'"')
            continue;
        qsizetype j = i + 1;
        while (j < n && src[j] != u'"')
            j += src[j] == u'\\' ? 2 : 1;
        qsizetype k = j + 1;
        while (k < n && (src[k] == u' ' || src[k] == u'\t' || src[k] == u'\n' || src[k] == u'\r'))
            ++k;
        if ((k >= n || src[k] != u':') && j > i + 1 && j <= n) { // a value, not an object key
            const QStringView raw = QStringView(src).sliced(i + 1, qMin(j, n) - i - 1);
            Segment s{i + 1, qMin(j, n), decodeJsonString(raw)};
            s.unicodeEscapes = nonAsciiEscape.matchView(raw).hasMatch();
            segs.push_back(std::move(s));
        }
        i = j;
    }
    return segs;
}

// ---------------------------------------------------------------- HTML (tag-preserving text-node rewrite)
const QSet<QString> &rawTextElements()
{
    static const QSet<QString> s{QStringLiteral("script"), QStringLiteral("style"), QStringLiteral("xmp"),
                                 QStringLiteral("iframe"), QStringLiteral("noembed"), QStringLiteral("noframes"),
                                 QStringLiteral("plaintext")};
    return s;
}

const QSet<QString> &skippedElements()
{
    static const QSet<QString> s = [] {
        QSet<QString> r = rawTextElements();
        for (const char *name : {"template", "code", "kbd", "samp", "var", "svg", "math"})
            r.insert(QString::fromLatin1(name));
        return r;
    }();
    return s;
}

const QSet<QString> &voidElements()
{
    static const QSet<QString> s = [] {
        QSet<QString> r;
        for (const char *name : {"area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "param",
                                 "source", "track", "wbr"})
            r.insert(QString::fromLatin1(name));
        return r;
    }();
    return s;
}

const QSet<QString> &optionalEndElements()
{
    static const QSet<QString> s = [] {
        QSet<QString> r;
        for (const char *name : {"p", "li", "dt", "dd", "tr", "td", "th", "thead", "tbody", "tfoot", "option",
                                 "optgroup", "rb", "rt", "rtc", "rp", "colgroup", "caption"})
            r.insert(QString::fromLatin1(name));
        return r;
    }();
    return s;
}

// named character references that matter for Uzbek text; any other stays an opaque reference
const QHash<QString, char32_t> &htmlEntities()
{
    static const QHash<QString, char32_t> e{
        {QStringLiteral("nbsp"), 0xA0}, {QStringLiteral("amp"), 0x26}, {QStringLiteral("lt"), 0x3C},
        {QStringLiteral("gt"), 0x3E}, {QStringLiteral("quot"), 0x22}, {QStringLiteral("apos"), 0x27},
        {QStringLiteral("shy"), 0xAD}, {QStringLiteral("laquo"), 0xAB}, {QStringLiteral("raquo"), 0xBB},
        {QStringLiteral("lsquo"), 0x2018}, {QStringLiteral("rsquo"), 0x2019}, {QStringLiteral("sbquo"), 0x201A},
        {QStringLiteral("ldquo"), 0x201C}, {QStringLiteral("rdquo"), 0x201D}, {QStringLiteral("bdquo"), 0x201E},
        {QStringLiteral("prime"), 0x2032}, {QStringLiteral("Prime"), 0x2033}, {QStringLiteral("acute"), 0xB4},
        {QStringLiteral("grave"), 0x60}, {QStringLiteral("ndash"), 0x2013}, {QStringLiteral("mdash"), 0x2014},
        {QStringLiteral("hellip"), 0x2026}, {QStringLiteral("middot"), 0xB7}, {QStringLiteral("bull"), 0x2022},
        {QStringLiteral("deg"), 0xB0}, {QStringLiteral("copy"), 0xA9}, {QStringLiteral("reg"), 0xAE},
        {QStringLiteral("trade"), 0x2122}, {QStringLiteral("sect"), 0xA7}, {QStringLiteral("para"), 0xB6},
        {QStringLiteral("plusmn"), 0xB1}, {QStringLiteral("times"), 0xD7}, {QStringLiteral("divide"), 0xF7},
        {QStringLiteral("euro"), 0x20AC}, {QStringLiteral("ensp"), 0x2002}, {QStringLiteral("emsp"), 0x2003},
        {QStringLiteral("thinsp"), 0x2009}, {QStringLiteral("zwnj"), 0x200C}, {QStringLiteral("zwj"), 0x200D},
        {QStringLiteral("lrm"), 0x200E}, {QStringLiteral("rlm"), 0x200F}, {QStringLiteral("numero"), 0x2116},
        {QStringLiteral("minus"), 0x2212}, {QStringLiteral("larr"), 0x2190}, {QStringLiteral("rarr"), 0x2192},
        {QStringLiteral("Ouml"), 0xD6}, {QStringLiteral("ouml"), 0xF6}, {QStringLiteral("Ccedil"), 0xC7},
        {QStringLiteral("ccedil"), 0xE7}, {QStringLiteral("Otilde"), 0xD5}, {QStringLiteral("otilde"), 0xF5},
    };
    return e;
}

// Splits src[start, end) into decoded pieces; an unknown character reference ends a piece.
void textPieces(const QString &src, qsizetype start, qsizetype end, std::vector<Segment> &segs)
{
    static const QRegularExpression ref(
        QStringLiteral("^&(?:#[xX]([0-9a-fA-F]{1,6})|#([0-9]{1,7})|([A-Za-z][A-Za-z0-9]{1,31}));"));
    qsizetype pieceStart = start;
    QString decoded;
    const auto flush = [&](qsizetype to) {
        if (to > pieceStart)
            segs.push_back({pieceStart, to, decoded});
        decoded.clear();
    };
    qsizetype i = start;
    while (i < end) {
        const qsizetype amp = src.indexOf(u'&', i);
        if (amp < 0 || amp >= end) {
            decoded += QStringView(src).sliced(i, end - i);
            break;
        }
        decoded += QStringView(src).sliced(i, amp - i);
        const QRegularExpressionMatch m = ref.matchView(QStringView(src).sliced(amp, qMin(end, amp + 40) - amp));
        if (!m.hasMatch()) {
            decoded += u'&';
            i = amp + 1;
            continue;
        }
        char32_t cp = 0;
        bool known = false;
        if (m.hasCaptured(3)) {
            const auto it = htmlEntities().constFind(m.captured(3));
            if (it != htmlEntities().constEnd()) {
                cp = *it;
                known = true;
            }
        } else {
            bool ok = false;
            const uint v = m.hasCaptured(1) ? m.captured(1).toUInt(&ok, 16) : m.captured(2).toUInt(&ok, 10);
            if (ok && v > 0 && v <= 0x10FFFF && !(v >= 0xD800 && v <= 0xDFFF)) {
                cp = char32_t(v);
                known = true;
            }
        }
        if (!known) { // a reference we do not know: keep it, as a boundary
            flush(amp);
            pieceStart = amp + m.capturedLength();
        } else {
            decoded += QString::fromUcs4(&cp, 1);
        }
        i = amp + m.capturedLength();
    }
    flush(end);
}

// index of the `</name` that ends a raw-text element (ASCII case-insensitive), or the end of the document
qsizetype closingTag(const QString &src, const QString &name, qsizetype from)
{
    const QRegularExpression re(QStringLiteral("</") + QRegularExpression::escape(name) + QStringLiteral("[\\s>/]"),
                                QRegularExpression::CaseInsensitiveOption);
    const QRegularExpressionMatch m = re.match(src, from);
    return m.hasMatch() ? m.capturedStart() : src.size();
}

struct Attr
{
    QString name;
    QString value;
};

QList<Attr> parseAttrs(const QString &src, qsizetype from, qsizetype to)
{
    static const QRegularExpression attr(
        QStringLiteral("([^\\s\"'>/=]+)(?:\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)'|([^\\s>]+)))?"));
    QList<Attr> out;
    if (to <= from)
        return out;
    QRegularExpressionMatchIterator it = attr.globalMatchView(QStringView(src).sliced(from, to - from));
    while (it.hasNext()) {
        const QRegularExpressionMatch m = it.next();
        QString v;
        if (m.hasCaptured(2))
            v = m.captured(2);
        else if (m.hasCaptured(3))
            v = m.captured(3);
        else if (m.hasCaptured(4))
            v = m.captured(4);
        else
            continue;
        out.push_back({asciiLowered(m.capturedView(1)), v});
    }
    return out;
}

inline bool isAsciiLetter(QChar c)
{
    return (c >= u'A' && c <= u'Z') || (c >= u'a' && c <= u'z');
}

inline bool isHtmlSpace(QChar c)
{
    return c == u' ' || c == u'\t' || c == u'\n' || c == u'\r' || c == u'\f';
}

std::vector<Segment> collectHtml(const QString &src)
{
    static const QRegularExpression notranslateClass(QStringLiteral("(^|\\s)notranslate(\\s|$)"));
    std::vector<Segment> segs;
    QString skipName;
    int skipDepth = 0;
    const qsizetype n = src.size();
    const auto at = [&](qsizetype k) { return k >= 0 && k < n ? src[k] : QChar(); };
    qsizetype i = 0;
    while (i < n) {
        const qsizetype lt = src.indexOf(u'<', i);
        const qsizetype textEnd = lt < 0 ? n : lt;
        if (textEnd > i && skipDepth == 0)
            textPieces(src, i, textEnd, segs);
        if (lt < 0)
            break;
        i = lt;
        if (QStringView(src).sliced(lt).startsWith(u"<!--")) {
            const qsizetype e = src.indexOf(QStringView(u"-->"), lt + 4);
            i = e < 0 ? n : e + 3;
            continue;
        }
        if (QStringView(src).sliced(lt).startsWith(u"<![CDATA[")) {
            const qsizetype e = src.indexOf(QStringView(u"]]>"), lt + 9);
            i = e < 0 ? n : e + 3;
            continue;
        }
        const QChar c1 = at(lt + 1);
        if (c1 == u'!' || c1 == u'?') { // <!DOCTYPE …>, <?…>
            const qsizetype e = src.indexOf(u'>', lt + 2);
            i = e < 0 ? n : e + 1;
            continue;
        }
        const bool isEnd = c1 == u'/';
        const qsizetype nameStart = lt + (isEnd ? 2 : 1);
        if (!isAsciiLetter(at(nameStart))) { // "a < b": just text
            if (skipDepth == 0)
                textPieces(src, lt, lt + 1, segs);
            i = lt + 1;
            continue;
        }
        qsizetype j = nameStart;
        while (j < n && !isHtmlSpace(src[j]) && src[j] != u'/' && src[j] != u'>')
            ++j;
        const QString name = asciiLowered(QStringView(src).sliced(nameStart, j - nameStart));
        qsizetype k = j;
        QChar quote;
        for (; k < n; ++k) {
            const QChar d = src[k];
            if (!quote.isNull()) {
                if (d == quote)
                    quote = QChar();
            } else if (d == u'"' || d == u'\'') {
                quote = d;
            } else if (d == u'>') {
                break;
            }
        }
        const qsizetype tagEnd = k; // index of '>'
        i = k < n ? k + 1 : n;
        const bool selfClosing = at(k - 1) == u'/';

        if (isEnd) {
            if (skipDepth > 0 && name == skipName && --skipDepth == 0)
                skipName.clear();
            continue;
        }
        if (skipDepth > 0) {
            if (name == skipName && !selfClosing && !voidElements().contains(name))
                ++skipDepth;
            continue;
        }
        bool translateNo = false;
        for (const Attr &a : parseAttrs(src, j, selfClosing ? tagEnd - 1 : tagEnd)) {
            if (a.name == u"translate" && asciiLowered(a.value) == u"no")
                translateNo = true;
            if (a.name == u"class" && notranslateClass.match(a.value).hasMatch())
                translateNo = true;
        }
        const bool skip = skippedElements().contains(name)
                          || (translateNo && !optionalEndElements().contains(name) && !voidElements().contains(name));
        if (skip && !selfClosing && !voidElements().contains(name)) {
            skipName = name;
            skipDepth = 1;
            if (rawTextElements().contains(name)) // raw text runs to the matching end tag
                i = closingTag(src, name, i);
            continue;
        }
        if ((name == u"title" || name == u"textarea") && !selfClosing) { // escapable raw text: no tags inside
            const qsizetype e = closingTag(src, name, i);
            textPieces(src, i, e, segs);
            i = e;
        }
    }
    return segs;
}

QString escapeHtmlText(const QString &s, const Segment &)
{
    QString out;
    out.reserve(s.size() + 8);
    for (QChar c : s) {
        switch (c.unicode()) {
        case u'&': out += QStringView(u"&amp;"); break;
        case u'<': out += QStringView(u"&lt;"); break;
        case u'>': out += QStringView(u"&gt;"); break;
        case 0xA0: out += QStringView(u"&nbsp;"); break;
        default: out += c;
        }
    }
    return out;
}

// ---------------------------------------------------------------- XML (QXmlStreamReader → QXmlStreamWriter)
// Characters outside these elements are converted; inside, they are written back as they were (script and style
// even byte for byte, their content is copied from the source).
bool isRawXmlElement(QStringView localName)
{
    return localName == u"script" || localName == u"style";
}

bool isSkippedXmlElement(QStringView localName, bool xhtml)
{
    if (isRawXmlElement(localName))
        return true;
    if (!xhtml)
        return false;
    for (const char16_t *n : {u"template", u"code", u"kbd", u"samp", u"var", u"svg", u"math"})
        if (localName == QStringView(n))
            return true;
    return false;
}

QStringView localNameOf(QStringView qualifiedName)
{
    const qsizetype colon = qualifiedName.indexOf(u':');
    return colon < 0 ? qualifiedName : qualifiedName.sliced(colon + 1);
}

bool hasTranslateNo(const QXmlStreamAttributes &attrs)
{
    static const QRegularExpression notranslateClass(QStringLiteral("(^|\\s)notranslate(\\s|$)"));
    for (const QXmlStreamAttribute &a : attrs) {
        const QStringView name = a.qualifiedName();
        if (name == u"translate" && asciiLowered(a.value()) == u"no")
            return true;
        if (name == u"class" && notranslateClass.matchView(a.value()).hasMatch())
            return true;
    }
    return false;
}

// Pass 1: is it well-formed XML, is it XHTML, and the convertible text (for auto-detection).
bool scanXml(const QString &src, bool *xhtml, QString *text, QString *error)
{
    QXmlStreamReader r(src);
    r.setNamespaceProcessing(false);
    int skipDepth = 0;
    bool root = true;
    while (!r.atEnd()) {
        switch (r.readNext()) {
        case QXmlStreamReader::StartElement: {
            const QStringView local = localNameOf(r.qualifiedName());
            if (root) {
                *xhtml = local == u"html";
                root = false;
            }
            if (skipDepth > 0 || isSkippedXmlElement(local, *xhtml) || (*xhtml && hasTranslateNo(r.attributes())))
                ++skipDepth;
            break;
        }
        case QXmlStreamReader::EndElement:
            if (skipDepth > 0)
                --skipDepth;
            break;
        case QXmlStreamReader::Characters:
            if (skipDepth == 0 && !r.isCDATA() && !r.isWhitespace()) {
                *text += r.text();
                *text += u'\n';
            }
            break;
        default:
            break;
        }
    }
    if (r.hasError()) {
        *error = QStringLiteral("%1 (%2:%3)").arg(r.errorString()).arg(r.lineNumber()).arg(r.columnNumber());
        return false;
    }
    return true;
}

// Pass 2: rewrite the document. Markup is re-serialised by QXmlStreamWriter; what the stream API cannot describe
// is copied from the source: the XML declaration, whitespace outside the root element, script/style content.
bool rewriteXml(const QString &src, bool xhtml, Script from, Script to, const Options &o, QString *out, bool *changed,
                QString *error)
{
    QXmlStreamReader r(src);
    r.setNamespaceProcessing(false);
    QString result;
    result.reserve(src.size() + src.size() / 8);
    QXmlStreamWriter w(&result);
    int depth = 0;
    int skipDepth = 0;
    qsizetype lastEnd = 0; // end of the previous token outside the root element
    *changed = false;
    // whitespace between top-level tokens (the reader does not report it); characterOffset() is exact after
    // start tags, end tags, comments, processing instructions and the DTD (whose text() may include the whitespace)
    const auto copyTopLevelGap = [&] {
        const qsizetype end = qMin<qsizetype>(r.characterOffset(), src.size());
        qsizetype k = lastEnd;
        while (k < end && (src[k] == u' ' || src[k] == u'\t' || src[k] == u'\r' || src[k] == u'\n'))
            ++k;
        result += QStringView(src).sliced(lastEnd, k - lastEnd);
    };
    while (!r.atEnd()) {
        const QXmlStreamReader::TokenType token = r.readNext();
        switch (token) {
        case QXmlStreamReader::StartDocument:
            if (!r.documentVersion().isEmpty()) { // the XML declaration exactly as written
                const qsizetype declEnd = src.indexOf(QStringView(u"?>"));
                if (declEnd >= 0) {
                    lastEnd = declEnd + 2;
                    result += QStringView(src).first(lastEnd);
                }
            }
            break;
        case QXmlStreamReader::StartElement: {
            if (depth == 0)
                copyTopLevelGap();
            ++depth;
            const QString qname = r.qualifiedName().toString();
            const QStringView local = localNameOf(qname);
            w.writeStartElement(qname);
            w.writeAttributes(r.attributes()); // xmlns declarations are plain attributes without namespace processing
            const qsizetype contentStart = r.characterOffset();
            const bool emptyTag = contentStart >= 2 && QStringView(src).sliced(contentStart - 2, 2) == u"/>";
            if (emptyTag)
                break; // <x/>: the writer writes it the same way
            w.writeCharacters(QString()); // <x></x> stays <x></x>, never <x/> (which breaks XHTML read as HTML)
            if (isRawXmlElement(local)) {
                // copy the content byte for byte: the writer would escape " and > in a script
                int inner = 1;
                while (inner > 0 && !r.atEnd()) {
                    const QXmlStreamReader::TokenType t = r.readNext();
                    if (t == QXmlStreamReader::StartElement)
                        ++inner;
                    else if (t == QXmlStreamReader::EndElement)
                        --inner;
                }
                if (r.hasError())
                    break;
                const qsizetype endTag = src.lastIndexOf(QStringView(u"</"), r.characterOffset() - 1);
                if (endTag >= contentStart)
                    result += QStringView(src).sliced(contentStart, endTag - contentStart);
                w.writeEndElement();
                if (--depth == 0)
                    lastEnd = r.characterOffset();
                break;
            }
            if (skipDepth > 0 || isSkippedXmlElement(local, xhtml) || (xhtml && hasTranslateNo(r.attributes())))
                ++skipDepth;
            break;
        }
        case QXmlStreamReader::EndElement:
            if (skipDepth > 0)
                --skipDepth;
            w.writeEndElement();
            if (--depth == 0)
                lastEnd = r.characterOffset();
            break;
        case QXmlStreamReader::Characters:
            if (r.isCDATA()) {
                w.writeCDATA(r.text());
            } else if (skipDepth > 0 || r.isWhitespace()) {
                w.writeCharacters(r.text());
            } else {
                const QString converted = uztranslit::convert(r.text(), from, to, o);
                if (converted != r.text())
                    *changed = true;
                w.writeCharacters(converted);
            }
            break;
        case QXmlStreamReader::Comment:
        case QXmlStreamReader::DTD:
        case QXmlStreamReader::ProcessingInstruction:
            if (depth == 0) { // outside the root element: copied as written, with the whitespace before it
                const qsizetype end = qMin<qsizetype>(r.characterOffset(), src.size());
                result += QStringView(src).sliced(lastEnd, end - lastEnd);
                lastEnd = end;
            } else if (token == QXmlStreamReader::Comment) {
                w.writeComment(r.text());
            } else if (token == QXmlStreamReader::ProcessingInstruction) {
                w.writeProcessingInstruction(r.processingInstructionTarget(), r.processingInstructionData());
            }
            break;
        case QXmlStreamReader::EntityReference:
            w.writeEntityReference(r.name());
            break;
        case QXmlStreamReader::EndDocument: {
            const QStringView tail = QStringView(src).sliced(qMin(lastEnd, src.size()));
            if (tail.trimmed().isEmpty())
                result += tail;
            break;
        }
        case QXmlStreamReader::NoToken:
        case QXmlStreamReader::Invalid:
            break;
        }
    }
    if (r.hasError()) {
        *error = QStringLiteral("%1 (%2:%3)").arg(r.errorString()).arg(r.lineNumber()).arg(r.columnNumber());
        return false;
    }
    if (w.hasError()) {
        *error = QStringLiteral("QXmlStreamWriter error");
        return false;
    }
    // the reader reports every line end as \n (XML end-of-line handling): give a CRLF document its CRLFs back
    if (src.contains(QStringView(u"\r\n")) && !src.contains(QRegularExpression(QStringLiteral("(?<!\\r)\\n")))) {
        result.replace(QStringLiteral("\r\n"), QStringLiteral("\n"));
        result.replace(QLatin1Char('\n'), QStringLiteral("\r\n"));
    }
    *out = result;
    return true;
}

} // namespace

DocumentFormat Documents::formatForFileName(const QString &fileName)
{
    const QString suffix = QFileInfo(fileName).suffix().toLower();
    if (suffix == u"md" || suffix == u"markdown")
        return DocumentFormat::Markdown;
    if (suffix == u"srt")
        return DocumentFormat::Subtitles;
    if (suffix == u"json")
        return DocumentFormat::Json;
    if (suffix == u"html" || suffix == u"htm")
        return DocumentFormat::Html;
    if (suffix == u"xml" || suffix == u"xhtml")
        return DocumentFormat::Xml;
    return DocumentFormat::PlainText;
}

QStringList Documents::batchSuffixes()
{
    return {QStringLiteral("txt"), QStringLiteral("md"), QStringLiteral("csv"), QStringLiteral("srt"),
            QStringLiteral("html"), QStringLiteral("json"), QStringLiteral("xml")};
}

bool Documents::convert(DocumentFormat format, const QString &text, Script from, Script to, const Options &o,
                        DocumentResult *result, QString *error)
{
    DocumentResult r;
    try {
        switch (format) {
        case DocumentFormat::PlainText: {
            r.from = from == Script::Auto ? uztranslit::detect(text) : from;
            r.text = uztranslit::convert(text, r.from, to, o);
            r.changed = r.text != text;
            break;
        }
        case DocumentFormat::Markdown:
            convertSegments(text, collectMarkdown(text), from, to, o, keepAsIs, &r);
            break;
        case DocumentFormat::Subtitles:
            convertSegments(text, collectSrt(text), from, to, o, keepAsIs, &r);
            break;
        case DocumentFormat::Json:
            convertSegments(text, collectJson(text), from, to, o,
                            [](const QString &s, const Segment &seg) { return encodeJsonString(s, seg.unicodeEscapes); }, &r);
            break;
        case DocumentFormat::Html:
        case DocumentFormat::Xml: {
            bool xhtml = false;
            QString xmlText;
            QString xmlError;
            const bool wellFormed = scanXml(text, &xhtml, &xmlText, &xmlError);
            if (wellFormed && (format == DocumentFormat::Xml || xhtml)) {
                r.from = from == Script::Auto ? uztranslit::detect(xmlText) : from;
                if (r.from == to) {
                    r.text = text;
                    break;
                }
                QString out;
                bool changed = false;
                if (rewriteXml(text, xhtml, r.from, to, o, &out, &changed, &xmlError)) {
                    r.text = changed ? out : text;
                    r.changed = changed;
                    break;
                }
            }
            if (format == DocumentFormat::Xml)
                r.warning = tr("Not well-formed XML (%1): only the text between tags was converted.").arg(xmlError);
            convertSegments(text, collectHtml(text), from, to, o, escapeHtmlText, &r);
            break;
        }
        }
    } catch (const std::exception &e) {
        if (error)
            *error = QString::fromUtf8(e.what());
        return false;
    }
    if (result)
        *result = std::move(r);
    return true;
}

} // namespace uzt
