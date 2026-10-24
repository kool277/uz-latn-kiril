// Conformance runner: spec/fixtures.json (cases, roundtrips, detect, optional) against the C++ port.
// The JSON file is copied into the build tree by CMake and compiled into a Qt resource; no case is written here.
#include "uztranslit.hpp"

#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QtTest>

using namespace uztranslit;

namespace {

QString show(const QString &s) // JSON-quoted, so invisible characters show up as escapes in failure messages
{
    QString o = QStringLiteral("\"");
    for (QChar c : s) {
        const char16_t u = c.unicode();
        if (u == u'"' || u == u'\\')
            o += u'\\', o += c;
        else if (u < 0x20 || (u >= 0x7F && u <= 0xA0) || u == 0xAD || (u >= 0x2000 && u <= 0x200F)
                 || (u >= 0x2028 && u <= 0x202F) || u == 0x205F || u == 0x3000 || u == 0xFEFF)
            o += QStringLiteral("\\u%1").arg(uint(u), 4, 16, QLatin1Char('0'));
        else
            o += c;
    }
    return o + u'"';
}

} // namespace

class TestFixtures : public QObject
{
    Q_OBJECT

    QJsonObject m_fixtures;
    int m_passed = 0;
    int m_failed = 0;

    // counts one check; returns false (and prints the details) on a mismatch
    bool check(const QString &id, const QString &got, const QString &want, const QString &extra = QString())
    {
        if (got == want) {
            ++m_passed;
            return true;
        }
        ++m_failed;
        qWarning().noquote() << QStringLiteral("FAIL %1 %2\n   want %3\n   got  %4").arg(id, extra, show(want), show(got));
        return false;
    }

    QJsonArray group(const char *name)
    {
        const QJsonArray a = m_fixtures.value(QLatin1String(name)).toArray();
        if (a.isEmpty())
            qWarning("fixtures.json has no \"%s\" entries", name);
        return a;
    }

private slots:
    void initTestCase()
    {
        QFile f(QStringLiteral(":/spec/fixtures.json"));
        QVERIFY2(f.open(QIODevice::ReadOnly), "the spec/fixtures.json resource is missing");
        QJsonParseError err;
        const QJsonDocument doc = QJsonDocument::fromJson(f.readAll(), &err);
        QVERIFY2(err.error == QJsonParseError::NoError, qPrintable(err.errorString()));
        m_fixtures = doc.object();
        QVERIFY(!m_fixtures.isEmpty());
    }

    void cases()
    {
        const QJsonArray all = group("cases");
        QVERIFY(!all.isEmpty());
        int failed = 0;
        for (const QJsonValue &v : all) {
            const QJsonObject c = v.toObject();
            const QString from = c[u"from"].toString(), to = c[u"to"].toString(), in = c[u"in"].toString();
            if (!check(c[u"id"].toString(), convert(in, from, to), c[u"out"].toString(),
                       QStringLiteral("%1->%2 %3").arg(from, to, show(in))))
                ++failed;
        }
        QCOMPARE(failed, 0);
    }

    void roundtrips()
    {
        const QJsonArray all = group("roundtrips");
        QVERIFY(!all.isEmpty());
        int failed = 0;
        for (const QJsonValue &v : all) {
            const QJsonObject r = v.toObject();
            const QString from = r[u"from"].toString(), via = r[u"via"].toString(), in = r[u"in"].toString();
            const QString there = convert(in, from, via);
            if (!check(r[u"id"].toString(), convert(there, via, from), in,
                       QStringLiteral("%1->%2->%1 via %3").arg(from, via, show(there))))
                ++failed;
        }
        QCOMPARE(failed, 0);
    }

    void detection()
    {
        const QJsonArray all = group("detect");
        QVERIFY(!all.isEmpty());
        int failed = 0;
        for (const QJsonValue &v : all) {
            const QJsonObject d = v.toObject();
            const QString in = d[u"in"].toString();
            if (!check(QStringLiteral("detect ") + show(in), scriptId(detect(in)), d[u"expect"].toString()))
                ++failed;
        }
        QCOMPARE(failed, 0);
    }

    void optional()
    {
        const QJsonArray all = group("optional");
        QVERIFY(!all.isEmpty());
        int failed = 0;
        for (const QJsonValue &v : all) {
            const QJsonObject o = v.toObject();
            const QString feature = o[u"feature"].toString();
            Options options; // as the reference runner: { okina: "'", tutuq: "'" } or { skipUrls: true }
            if (feature == u"asciiApostrophe")
                options = Options::ascii();
            else
                options.skipUrls = true;
            if (!check(QStringLiteral("optional/") + feature,
                       convert(o[u"in"].toString(), o[u"from"].toString(), o[u"to"].toString(), options),
                       o[u"out"].toString()))
                ++failed;
        }
        QCOMPARE(failed, 0);
    }

    void cleanupTestCase()
    {
        qInfo().noquote() << QStringLiteral("%1 passed, %2 failed (C++/Qt port v%3, spec/fixtures.json v%4)")
                                 .arg(m_passed)
                                 .arg(m_failed)
                                 .arg(QLatin1String(VERSION), m_fixtures[u"version"].toString());
    }
};

QTEST_GUILESS_MAIN(TestFixtures)
#include "tst_fixtures.moc"
