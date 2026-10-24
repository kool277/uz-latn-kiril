// The Qt Linguist files are complete and consistent: every message is translated (no unfinished, vanished or
// obsolete entries), placeholders and keyboard accelerators match the source, no invisible characters.
#include <QDir>
#include <QFile>
#include <QRegularExpression>
#include <QSet>
#include <QXmlStreamReader>
#include <QtTest>

#ifndef UZT_TS_DIR
#  error "UZT_TS_DIR must point to the translations directory"
#endif

namespace {

QSet<QString> placeholders(const QString &s)
{
    static const QRegularExpression re(QStringLiteral("%(?:\\d+|n)"));
    QSet<QString> out;
    for (auto it = re.globalMatch(s); it.hasNext();)
        out.insert(it.next().captured());
    return out;
}

bool hasAccelerator(QString s)
{
    s.replace(QStringLiteral("&&"), QString());
    return s.contains(u'&');
}

bool hasInvisible(const QString &s)
{
    for (QChar c : s) {
        const char16_t u = c.unicode();
        if ((u < 0x20 && u != u'\n') || (u >= 0x7F && u <= 0xA0) || u == 0xAD || (u >= 0x2000 && u <= 0x200F)
            || (u >= 0x2028 && u <= 0x202F) || u == 0x205F || u == 0x3000 || u == 0xFEFF)
            return true;
    }
    return false;
}

} // namespace

class TestTranslations : public QObject
{
    Q_OBJECT

private slots:
    void complete_data()
    {
        QTest::addColumn<QString>("path");
        const QDir dir(QStringLiteral(UZT_TS_DIR));
        const QStringList files = dir.entryList({QStringLiteral("*.ts")}, QDir::Files, QDir::Name);
        QVERIFY(files.contains(QStringLiteral("uztranslit_uz.ts")));
        QVERIFY(files.contains(QStringLiteral("uztranslit_ru.ts")));
        for (const QString &f : files)
            QTest::newRow(qPrintable(f)) << dir.filePath(f);
    }

    void complete()
    {
        QFETCH(QString, path);
        QFile f(path);
        QVERIFY(f.open(QIODevice::ReadOnly));
        QXmlStreamReader r(&f);
        QString context, source, translation, type;
        int messages = 0;
        QStringList problems;
        while (!r.atEnd()) {
            r.readNext();
            if (r.isStartElement()) {
                if (r.name() == u"name")
                    context = r.readElementText();
                else if (r.name() == u"message")
                    source.clear(), translation.clear(), type.clear();
                else if (r.name() == u"source")
                    source = r.readElementText();
                else if (r.name() == u"translation") {
                    type = r.attributes().value(QStringLiteral("type")).toString();
                    translation = r.readElementText();
                }
            } else if (r.isEndElement() && r.name() == u"message") {
                ++messages;
                const QString where = context + QStringLiteral(" / ") + source;
                if (!type.isEmpty())
                    problems << QStringLiteral("%1: type=\"%2\"").arg(where, type);
                if (translation.isEmpty())
                    problems << QStringLiteral("%1: no translation").arg(where);
                if (placeholders(source) != placeholders(translation))
                    problems << QStringLiteral("%1: placeholders differ in \"%2\"").arg(where, translation);
                if (hasAccelerator(source) != hasAccelerator(translation))
                    problems << QStringLiteral("%1: accelerator & differs in \"%2\"").arg(where, translation);
                if (hasInvisible(translation))
                    problems << QStringLiteral("%1: invisible character in the translation").arg(where);
            }
        }
        QVERIFY2(!r.hasError(), qPrintable(r.errorString()));
        for (const QString &p : problems)
            qWarning().noquote() << p;
        qInfo().noquote() << QStringLiteral("%1: %2 messages, %3 problems").arg(QFileInfo(path).fileName()).arg(messages).arg(problems.size());
        QVERIFY(messages > 0);
        QVERIFY(problems.isEmpty());
    }
};

QTEST_GUILESS_MAIN(TestTranslations)
#include "tst_translations.moc"
