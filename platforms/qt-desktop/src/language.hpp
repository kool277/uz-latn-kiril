// Interface language (Qt Linguist translations compiled into the binary) and the names of the scripts.
#pragma once

#include "uztranslit.hpp"

#include <QCoreApplication>
#include <QString>
#include <QStringList>

namespace uzt {

class Language
{
    Q_DECLARE_TR_FUNCTIONS(Language)

public:
    static QStringList ids(); // "uz" (Latin 1995), "ru", "en" (the source language of the strings)
    static QString nativeName(const QString &id);
    // like the web app: Russian for a Russian-first system, otherwise Uzbek
    static QString systemDefault();
    static QString resolve(const QString &saved);
    // installs the translators for `id` (none for English) and sets the default QLocale; false if a .qm is missing
    static bool apply(const QString &id);
    static QString current();
};

class ScriptNames
{
    Q_DECLARE_TR_FUNCTIONS(ScriptNames)

public:
    static QString button(uztranslit::Script script);     // Avto / Кирилл / Lotin 1995 / Yangi lotin
    static QString inSentence(uztranslit::Script script); // kirill / lotin 1995 / yangi lotin
};

} // namespace uzt
