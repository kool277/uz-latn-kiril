#include "language.hpp"

#include <QLibraryInfo>
#include <QLocale>
#include <QPointer>
#include <QTranslator>

namespace uzt {

namespace {

QPointer<QTranslator> g_app;
QPointer<QTranslator> g_qt;
QString g_current = QStringLiteral("en");

void removeTranslators()
{
    for (QPointer<QTranslator> *t : {&g_app, &g_qt}) {
        if (*t) {
            QCoreApplication::removeTranslator(*t);
            delete t->data();
        }
    }
}

} // namespace

QStringList Language::ids()
{
    return {QStringLiteral("uz"), QStringLiteral("ru"), QStringLiteral("en")};
}

QString Language::nativeName(const QString &id)
{
    if (id == u"uz")
        return QStringLiteral("Oʻzbekcha");
    if (id == u"ru")
        return QStringLiteral("Русский");
    return QStringLiteral("English");
}

QString Language::systemDefault()
{
    const QStringList ui = QLocale::system().uiLanguages();
    const QString first = ui.isEmpty() ? QString() : ui.front();
    if (first == u"ru" || first.startsWith(u"ru-") || first.startsWith(u"ru_"))
        return QStringLiteral("ru");
    return QStringLiteral("uz");
}

QString Language::resolve(const QString &saved)
{
    return ids().contains(saved) ? saved : systemDefault();
}

bool Language::apply(const QString &id)
{
    removeTranslators();
    g_current = ids().contains(id) ? id : QStringLiteral("en");
    bool ok = true;
    if (g_current == u"uz") {
        QLocale::setDefault(QLocale(QLocale::Uzbek, QLocale::LatinScript, QLocale::Uzbekistan));
    } else if (g_current == u"ru") {
        QLocale::setDefault(QLocale(QLocale::Russian, QLocale::Russia));
    } else {
        QLocale::setDefault(QLocale(QLocale::English, QLocale::UnitedStates));
        return true;
    }
    // Qt's own strings (standard dialogs) where Qt ships them; the app's .ts files also cover the context menus
    // and dialog buttons, so the interface is complete without them.
    auto *qt = new QTranslator(QCoreApplication::instance());
    if (qt->load(QStringLiteral("qtbase_%1").arg(g_current), QLibraryInfo::path(QLibraryInfo::TranslationsPath))) {
        QCoreApplication::installTranslator(qt);
        g_qt = qt;
    } else {
        delete qt;
    }
    // installed last, so it is searched first
    auto *app = new QTranslator(QCoreApplication::instance());
    if (app->load(QStringLiteral(":/i18n/uztranslit_%1.qm").arg(g_current))) {
        QCoreApplication::installTranslator(app);
        g_app = app;
    } else {
        delete app;
        ok = false;
    }
    return ok;
}

QString Language::current()
{
    return g_current;
}

QString ScriptNames::button(uztranslit::Script script)
{
    switch (script) {
    case uztranslit::Script::Auto: return tr("Auto", "script button");
    case uztranslit::Script::Cyr: return tr("Cyrillic", "script button");
    case uztranslit::Script::Lat: return tr("Latin 1995", "script button");
    case uztranslit::Script::New: return tr("Latin 2026", "script button");
    }
    return QString();
}

QString ScriptNames::inSentence(uztranslit::Script script)
{
    switch (script) {
    case uztranslit::Script::Auto: return tr("automatic", "script name inside a sentence");
    case uztranslit::Script::Cyr: return tr("Cyrillic", "script name inside a sentence");
    case uztranslit::Script::Lat: return tr("Latin 1995", "script name inside a sentence");
    case uztranslit::Script::New: return tr("Latin 2026", "script name inside a sentence");
    }
    return QString();
}

} // namespace uzt
