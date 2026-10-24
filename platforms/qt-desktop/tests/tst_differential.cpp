// Differential test: build/differential.json (written by `node tools/make_differential.mjs`) holds random texts
// converted by the reference core/js/uztranslit.js in every direction with random options, plus detections.
// CMake copies the file into the build tree and compiles it into a resource when it exists at configure time.
#include "uztranslit.hpp"

#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QtTest>

using namespace uztranslit;

namespace {

QString show(const QString &s)
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

Options optionsFrom(const QJsonObject &j)
{
    Options o;
    if (j.contains(u"okina"))
        o.okina = j[u"okina"].toString();
    if (j.contains(u"tutuq"))
        o.tutuq = j[u"tutuq"].toString();
    if (j.contains(u"dropHardSignAfterO"))
        o.dropHardSignAfterO = j[u"dropHardSignAfterO"].toBool();
    if (j.contains(u"tsFinal"))
        o.tsFinal = j[u"tsFinal"].toBool();
    if (j.contains(u"dictionary"))
        o.dictionary = j[u"dictionary"].toBool();
    if (j.contains(u"skipUrls"))
        o.skipUrls = j[u"skipUrls"].toBool();
    return o;
}

} // namespace

class TestDifferential : public QObject
{
    Q_OBJECT

    QJsonObject m_corpus;

private slots:
    void initTestCase()
    {
#ifndef UZT_HAVE_DIFFERENTIAL
        QSKIP("build/differential.json did not exist when CMake ran: run `node tools/make_differential.mjs` "
              "at the repository root, then configure again");
#else
        QFile f(QStringLiteral(":/differential/differential.json"));
        QVERIFY2(f.open(QIODevice::ReadOnly), "the differential.json resource is missing");
        QJsonParseError err;
        const QJsonDocument doc = QJsonDocument::fromJson(f.readAll(), &err);
        QVERIFY2(err.error == QJsonParseError::NoError, qPrintable(err.errorString()));
        m_corpus = doc.object();
        QVERIFY(!m_corpus[u"cases"].toArray().isEmpty());
        QVERIFY(!m_corpus[u"detect"].toArray().isEmpty());
#endif
    }

    void againstReference()
    {
        const QJsonArray cases = m_corpus[u"cases"].toArray();
        const QJsonArray detections = m_corpus[u"detect"].toArray();
        int passed = 0;
        int failed = 0;
        int convertPassed = 0;
        int detectPassed = 0;
        for (const QJsonValue &v : cases) {
            const QJsonObject c = v.toObject();
            const QString from = c[u"from"].toString(), to = c[u"to"].toString(), in = c[u"in"].toString();
            const QString want = c[u"out"].toString();
            const QJsonObject opts = c[u"options"].toObject();
            QString got;
            try {
                got = convert(in, from, to, optionsFrom(opts));
            } catch (const std::exception &e) {
                got = QStringLiteral("<exception: %1>").arg(QString::fromUtf8(e.what()));
            }
            if (got == want) {
                ++passed;
                ++convertPassed;
            } else if (++failed <= 10) {
                qWarning().noquote() << QStringLiteral("DIFF %1->%2 %3\n   in   %4\n   want %5\n   got  %6")
                                            .arg(from, to,
                                                 QString::fromUtf8(QJsonDocument(opts).toJson(QJsonDocument::Compact)),
                                                 show(in), show(want), show(got));
            }
        }
        for (const QJsonValue &v : detections) {
            const QJsonObject d = v.toObject();
            const QString got = scriptId(detect(d[u"in"].toString()));
            if (got == d[u"expect"].toString()) {
                ++passed;
                ++detectPassed;
            } else if (++failed <= 10) {
                qWarning().noquote() << QStringLiteral("DIFF detect %1: want %2 got %3")
                                            .arg(show(d[u"in"].toString()), d[u"expect"].toString(), got);
            }
        }
        qInfo().noquote() << QStringLiteral("%1 passed, %2 failed (differential vs %3, seed %4; conversions %5/%6, "
                                            "detections %7/%8)")
                                 .arg(passed)
                                 .arg(failed)
                                 .arg(m_corpus[u"reference"].toString(), m_corpus[u"seed"].toVariant().toString())
                                 .arg(convertPassed)
                                 .arg(cases.size())
                                 .arg(detectPassed)
                                 .arg(detections.size());
        QCOMPARE(failed, 0);
    }
};

QTEST_GUILESS_MAIN(TestDifferential)
#include "tst_differential.moc"
