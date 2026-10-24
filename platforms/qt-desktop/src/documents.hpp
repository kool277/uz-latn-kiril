// Format-aware conversion of whole documents: only the text a reader sees is converted; markup, code, keys and
// timings stay byte-identical.
//   plain text, CSV  the whole text
//   Markdown         everything except front matter, code blocks/spans, link targets, autolinks and HTML tags
//   SubRip (.srt)    cue text only (not numbers or timings), tags like <i> and {\an8} stay
//   JSON             string values only (never keys); escapes are decoded first and written back the same way
//   HTML             text nodes only (no script/style/code, no translate="no"), tags and attributes untouched;
//                    XHTML that is well-formed XML goes through the XML path
//   XML              QXmlStreamReader → QXmlStreamWriter, converting character data outside script/style/CDATA;
//                    a document that is not well-formed XML falls back to the HTML-style rewrite
// For Script::Auto the source script is detected from the convertible text, not from the markup.
#pragma once

#include "uztranslit.hpp"

#include <QCoreApplication>
#include <QString>
#include <QStringList>

namespace uzt {

enum class DocumentFormat { PlainText, Markdown, Subtitles, Json, Html, Xml };

struct DocumentResult
{
    QString text;                                         // the converted document
    uztranslit::Script from = uztranslit::Script::Lat;    // the source script that was used (detected for Auto)
    bool changed = false;
    QString warning;                                      // set when a fallback was used
};

class Documents
{
    Q_DECLARE_TR_FUNCTIONS(Documents)

public:
    // by file suffix; unknown suffixes are plain text
    static DocumentFormat formatForFileName(const QString &fileName);
    // the suffixes the batch dialog offers: txt md csv srt html json xml
    static QStringList batchSuffixes();

    static bool convert(DocumentFormat format, const QString &text, uztranslit::Script from, uztranslit::Script to,
                        const uztranslit::Options &options, DocumentResult *result, QString *error = nullptr);
};

} // namespace uzt
