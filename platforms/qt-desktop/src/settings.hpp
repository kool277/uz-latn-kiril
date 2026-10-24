// Preferences remembered between runs (QSettings): direction, apostrophe style, rules, interface language.
#pragma once

#include "uztranslit.hpp"

#include <QByteArray>
#include <QString>

namespace uzt {

struct AppSettings
{
    uztranslit::Script source = uztranslit::Script::Auto;
    uztranslit::Script target = uztranslit::Script::New; // the default target
    bool asciiApostrophe = false;                         // ' instead of ʻ and ʼ
    bool dictionary = true;
    bool dropHardSignAfterO = true;
    bool tsFinal = true;
    bool skipUrls = true;
    bool keepInTray = false;  // closing the window keeps the tray icon (clipboard actions) running
    QString language;         // "uz", "ru", "en"; empty: Russian for a Russian system, else Uzbek
    QString lastDirectory;
    QByteArray geometry;
    QByteArray splitterState;

    uztranslit::Options options() const;

    static AppSettings load();
    void save() const;
};

} // namespace uzt
