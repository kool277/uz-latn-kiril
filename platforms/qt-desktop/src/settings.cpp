#include "settings.hpp"

#include <QSettings>

namespace uzt {

namespace {

uztranslit::Script readScript(const QSettings &s, const char *key, uztranslit::Script fallback, bool allowAuto)
{
    uztranslit::Script script;
    if (!uztranslit::scriptFromId(s.value(QLatin1String(key)).toString(), &script))
        return fallback;
    if (script == uztranslit::Script::Auto && !allowAuto)
        return fallback;
    return script;
}

} // namespace

uztranslit::Options AppSettings::options() const
{
    uztranslit::Options o = asciiApostrophe ? uztranslit::Options::ascii() : uztranslit::Options();
    o.dictionary = dictionary;
    o.dropHardSignAfterO = dropHardSignAfterO;
    o.tsFinal = tsFinal;
    o.skipUrls = skipUrls;
    return o;
}

AppSettings AppSettings::load()
{
    const QSettings s;
    AppSettings a;
    a.source = readScript(s, "direction/source", uztranslit::Script::Auto, true);
    a.target = readScript(s, "direction/target", uztranslit::Script::New, false);
    a.asciiApostrophe = s.value(QStringLiteral("options/asciiApostrophe"), false).toBool();
    a.dictionary = s.value(QStringLiteral("options/dictionary"), true).toBool();
    a.dropHardSignAfterO = s.value(QStringLiteral("options/dropHardSignAfterO"), true).toBool();
    a.tsFinal = s.value(QStringLiteral("options/tsFinal"), true).toBool();
    a.skipUrls = s.value(QStringLiteral("options/skipUrls"), true).toBool();
    a.keepInTray = s.value(QStringLiteral("ui/keepInTray"), false).toBool();
    a.language = s.value(QStringLiteral("ui/language")).toString();
    a.lastDirectory = s.value(QStringLiteral("ui/lastDirectory")).toString();
    a.geometry = s.value(QStringLiteral("ui/geometry")).toByteArray();
    a.splitterState = s.value(QStringLiteral("ui/splitter")).toByteArray();
    return a;
}

void AppSettings::save() const
{
    QSettings s;
    s.setValue(QStringLiteral("direction/source"), uztranslit::scriptId(source));
    s.setValue(QStringLiteral("direction/target"), uztranslit::scriptId(target));
    s.setValue(QStringLiteral("options/asciiApostrophe"), asciiApostrophe);
    s.setValue(QStringLiteral("options/dictionary"), dictionary);
    s.setValue(QStringLiteral("options/dropHardSignAfterO"), dropHardSignAfterO);
    s.setValue(QStringLiteral("options/tsFinal"), tsFinal);
    s.setValue(QStringLiteral("options/skipUrls"), skipUrls);
    s.setValue(QStringLiteral("ui/keepInTray"), keepInTray);
    s.setValue(QStringLiteral("ui/language"), language);
    s.setValue(QStringLiteral("ui/lastDirectory"), lastDirectory);
    s.setValue(QStringLiteral("ui/geometry"), geometry);
    s.setValue(QStringLiteral("ui/splitter"), splitterState);
}

} // namespace uzt
