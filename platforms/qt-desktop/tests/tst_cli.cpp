// The command-line mode of the real uztranslit binary, run without any display: QT_QPA_PLATFORM names a platform
// plugin that does not exist and DISPLAY/WAYLAND_DISPLAY are removed, so creating a QGuiApplication would abort.
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QProcess>
#include <QTemporaryDir>
#include <QtTest>

#ifndef UZT_APP
#  error "UZT_APP (the path of the uztranslit binary) must be defined"
#endif

namespace {

struct Run
{
    int exitCode = -1;
    bool crashed = false;
    QByteArray out;
    QByteArray err;
};

Run run(const QStringList &args, const QByteArray &stdinData = QByteArray())
{
    QProcess p;
    QProcessEnvironment env = QProcessEnvironment::systemEnvironment();
    env.insert(QStringLiteral("QT_QPA_PLATFORM"), QStringLiteral("uzt-no-such-platform"));
    env.remove(QStringLiteral("DISPLAY"));
    env.remove(QStringLiteral("WAYLAND_DISPLAY"));
    p.setProcessEnvironment(env);
    p.start(QStringLiteral(UZT_APP), args);
    Run r;
    if (!p.waitForStarted(10000))
        return r;
    p.write(stdinData);
    p.closeWriteChannel();
    if (!p.waitForFinished(30000)) {
        p.kill();
        p.waitForFinished();
        return r;
    }
    r.exitCode = p.exitCode();
    r.crashed = p.exitStatus() != QProcess::NormalExit;
    r.out = p.readAllStandardOutput();
    r.err = p.readAllStandardError();
    return r;
}

QByteArray readAll(const QString &path)
{
    QFile f(path);
    return f.open(QIODevice::ReadOnly) ? f.readAll() : QByteArray("<missing>");
}

void writeAll(const QString &path, const QByteArray &bytes)
{
    QFile f(path);
    QVERIFY(f.open(QIODevice::WriteOnly));
    QCOMPARE(f.write(bytes), bytes.size());
}

QByteArray utf16le(const QString &s, bool bom)
{
    QByteArray b = bom ? QByteArray("\xFF\xFE", 2) : QByteArray();
    for (QChar c : s) {
        b += char(c.unicode() & 0xFF);
        b += char(c.unicode() >> 8);
    }
    return b;
}

} // namespace

class TestCli : public QObject
{
    Q_OBJECT

    QTemporaryDir m_tmp;

private slots:
    void initTestCase() { QVERIFY(m_tmp.isValid()); }

    void help()
    {
        const Run r = run({QStringLiteral("--help")});
        QCOMPARE(r.exitCode, 0);
        QVERIFY2(r.out.startsWith("usage: uztranslit"), r.out.constData());
        QVERIFY(r.out.contains("--from {auto,cyr,lat,new}"));
        QVERIFY(r.out.contains("-o OUTPUT, --output OUTPUT"));
        QCOMPARE(run({QStringLiteral("-h")}).exitCode, 0);
        const Run v = run({QStringLiteral("--version")});
        QCOMPARE(v.exitCode, 0);
        QVERIFY(v.out.startsWith("uztranslit 1."));
    }

    void stdinToStdout()
    {
        const Run r = run({QStringLiteral("--to"), QStringLiteral("new")}, QStringLiteral("O'zbekiston shahri\n").toUtf8());
        QCOMPARE(r.exitCode, 0);
        QCOMPARE(QString::fromUtf8(r.out), QStringLiteral("Özbekiston şahri\n"));
        QVERIFY2(!r.err.contains("uztranslit:"), r.err.constData());
        // "-" reads stdin too; --from given explicitly
        const Run c = run({QStringLiteral("--from"), QStringLiteral("cyr"), QStringLiteral("--to"), QStringLiteral("lat"),
                           QStringLiteral("-")},
                          QStringLiteral("Ўзбекистон Республикаси").toUtf8());
        QCOMPARE(c.exitCode, 0);
        QCOMPARE(QString::fromUtf8(c.out), QStringLiteral("Oʻzbekiston Respublikasi"));
    }

    void fileToOutput()
    {
        const QString in = m_tmp.filePath(QStringLiteral("in.txt"));
        const QString out = m_tmp.filePath(QStringLiteral("out.txt"));
        writeAll(in, QStringLiteral("Тошкент шаҳри,\r\nИсҳоқ.\r\n").toUtf8());
        const Run r = run({QStringLiteral("--from"), QStringLiteral("auto"), QStringLiteral("--to"), QStringLiteral("lat"), in,
                           QStringLiteral("-o"), out});
        QCOMPARE(r.exitCode, 0);
        QVERIFY(r.out.isEmpty());
        QCOMPARE(readAll(out), QStringLiteral("Toshkent shahri,\r\nIsʼhoq.\r\n").toUtf8()); // CRLF kept
        // --ascii, --opt=value, -oFILE and argparse-style abbreviations
        const QString out2 = m_tmp.filePath(QStringLiteral("out2.txt"));
        const Run a = run({QStringLiteral("--fr=cyr"), QStringLiteral("--t"), QStringLiteral("lat"), QStringLiteral("--asc"),
                           QStringLiteral("-o") + out2, in});
        QCOMPARE(a.exitCode, 0);
        QCOMPARE(readAll(out2), QStringLiteral("Toshkent shahri,\r\nIs'hoq.\r\n").toUtf8());
    }

    void keepsByteOrderMarkAndEncoding()
    {
        const QString in = m_tmp.filePath(QStringLiteral("bom.txt"));
        const QString out = m_tmp.filePath(QStringLiteral("bom-out.txt"));
        writeAll(in, QByteArray("\xEF\xBB\xBF") + QStringLiteral("Салом").toUtf8());
        QCOMPARE(run({QStringLiteral("--to"), QStringLiteral("new"), in, QStringLiteral("--output"), out}).exitCode, 0);
        QCOMPARE(readAll(out), QByteArray("\xEF\xBB\xBF") + QStringLiteral("Salom").toUtf8());

        const QString in16 = m_tmp.filePath(QStringLiteral("utf16.txt"));
        writeAll(in16, utf16le(QStringLiteral("Шаҳар"), true));
        const Run r = run({QStringLiteral("--to"), QStringLiteral("lat"), in16});
        QCOMPARE(r.exitCode, 0);
        QCOMPARE(r.out, utf16le(QStringLiteral("Shahar"), true));
    }

    void usageErrors()
    {
        // (no arguments at all, or only a file, is GUI mode; with converter flags --to is required)
        Run r = run({QStringLiteral("--from"), QStringLiteral("lat")});
        QCOMPARE(r.exitCode, 2);
        QVERIFY2(r.err.contains("the following arguments are required: --to"), r.err.constData());
        r = run({QStringLiteral("--from"), QStringLiteral("latin"), QStringLiteral("--to"), QStringLiteral("cyr")});
        QCOMPARE(r.exitCode, 2);
        QVERIFY2(r.err.contains("argument --from: invalid choice: 'latin'"), r.err.constData());
        r = run({QStringLiteral("--to"), QStringLiteral("auto")});
        QCOMPARE(r.exitCode, 2);
        r = run({QStringLiteral("--to"), QStringLiteral("cyr"), QStringLiteral("--bogus")});
        QCOMPARE(r.exitCode, 2);
        QVERIFY2(r.err.contains("unrecognized arguments: --bogus"), r.err.constData());
        r = run({QStringLiteral("--to")});
        QCOMPARE(r.exitCode, 2);
        QVERIFY2(r.err.contains("expected one argument"), r.err.constData());
        r = run({QStringLiteral("--to"), QStringLiteral("cyr"), QStringLiteral("a.txt"), QStringLiteral("b.txt")});
        QCOMPARE(r.exitCode, 2);
    }

    void inputErrors()
    {
        Run r = run({QStringLiteral("--to"), QStringLiteral("cyr"), m_tmp.filePath(QStringLiteral("missing.txt"))});
        QCOMPARE(r.exitCode, 1);
        QVERIFY(!r.err.isEmpty());
        const QString bad = m_tmp.filePath(QStringLiteral("cp1251.txt"));
        const QString out = m_tmp.filePath(QStringLiteral("never.txt"));
        writeAll(bad, QByteArray("\xD1\xE0\xEB\xEE\xEC")); // "Салом" in Windows-1251
        r = run({QStringLiteral("--to"), QStringLiteral("lat"), bad, QStringLiteral("-o"), out});
        QCOMPARE(r.exitCode, 1);
        QVERIFY2(r.err.contains("UTF-8"), r.err.constData());
        QVERIFY(!QFile::exists(out));
    }

    void everyFixtureCase()
    {
        QFile f(QStringLiteral(":/spec/fixtures.json"));
        QVERIFY(f.open(QIODevice::ReadOnly));
        const QJsonArray cases = QJsonDocument::fromJson(f.readAll()).object()[u"cases"].toArray();
        QVERIFY(!cases.isEmpty());
        int failed = 0;
        for (const QJsonValue &v : cases) {
            const QJsonObject c = v.toObject();
            const Run r = run({QStringLiteral("--from"), c[u"from"].toString(), QStringLiteral("--to"), c[u"to"].toString()},
                              c[u"in"].toString().toUtf8());
            if (r.exitCode != 0 || QString::fromUtf8(r.out) != c[u"out"].toString()) {
                ++failed;
                qWarning().noquote() << "FAIL" << c[u"id"].toString() << QString::fromUtf8(r.out) << QString::fromUtf8(r.err);
            }
        }
        qInfo().noquote() << QStringLiteral("%1 of %2 fixture cases through the command line").arg(cases.size() - failed).arg(cases.size());
        QCOMPARE(failed, 0);
    }
};

QTEST_GUILESS_MAIN(TestCli)
#include "tst_cli.moc"
