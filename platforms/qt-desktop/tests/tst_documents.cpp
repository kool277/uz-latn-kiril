// Text file decoding and the format-aware document conversion used by the batch dialog and the editor.
#include "batch.hpp"
#include "documents.hpp"
#include "textfile.hpp"

#include <QDir>
#include <QFile>
#include <QTemporaryDir>
#include <QtTest>

using uztranslit::Options;
using uztranslit::Script;
using namespace uzt;

namespace {

QString convertDoc(DocumentFormat f, const QString &in, Script from, Script to, DocumentResult *res = nullptr)
{
    DocumentResult r;
    QString error;
    if (!Documents::convert(f, in, from, to, Options(), &r, &error))
        return QStringLiteral("<error: %1>").arg(error);
    if (res)
        *res = r;
    return r.text;
}

QByteArray readAll(const QString &path)
{
    QFile f(path);
    return f.open(QIODevice::ReadOnly) ? f.readAll() : QByteArray();
}

bool writeAll(const QString &path, const QByteArray &bytes)
{
    QDir().mkpath(QFileInfo(path).absolutePath());
    QFile f(path);
    return f.open(QIODevice::WriteOnly) && f.write(bytes) == bytes.size();
}

// QCOMPARE cuts long strings: show where they differ
bool sameText(const QString &got, const QString &want)
{
    if (got == want)
        return true;
    qsizetype i = 0;
    while (i < got.size() && i < want.size() && got[i] == want[i])
        ++i;
    const qsizetype from = qMax<qsizetype>(0, i - 40);
    qWarning().noquote() << QStringLiteral("texts differ at %1\n   got  ...%2\n   want ...%3")
                                .arg(i)
                                .arg(got.mid(from, 120), want.mid(from, 120));
    return false;
}

} // namespace

class TestDocuments : public QObject
{
    Q_OBJECT

private slots:
    void textFileEncodings_data()
    {
        QTest::addColumn<QByteArray>("bytes");
        QTest::addColumn<int>("encoding");
        QTest::addColumn<bool>("bom");
        QTest::addColumn<QString>("text");
        const QString t = QStringLiteral("Тошкент shahri\r\n");
        QTest::newRow("utf-8") << t.toUtf8() << int(TextEncoding::Utf8) << false << t;
        QTest::newRow("utf-8 bom") << QByteArray("\xEF\xBB\xBF") + t.toUtf8() << int(TextEncoding::Utf8) << true << t;
        QByteArray le("\xFF\xFE", 2), be("\xFE\xFF", 2);
        for (QChar c : t) {
            le += char(c.unicode() & 0xFF);
            le += char(c.unicode() >> 8);
            be += char(c.unicode() >> 8);
            be += char(c.unicode() & 0xFF);
        }
        QTest::newRow("utf-16le bom") << le << int(TextEncoding::Utf16LE) << true << t;
        QTest::newRow("utf-16be bom") << be << int(TextEncoding::Utf16BE) << true << t;
        // a second U+FEFF after the byte-order mark is text
        QTest::newRow("two boms") << QByteArray("\xEF\xBB\xBF\xEF\xBB\xBFx") << int(TextEncoding::Utf8) << true
                                  << QString(QChar(0xFEFF)) + u'x';
        QTest::newRow("empty") << QByteArray() << int(TextEncoding::Utf8) << false << QString();
    }

    void textFileEncodings()
    {
        QFETCH(QByteArray, bytes);
        QFETCH(int, encoding);
        QFETCH(bool, bom);
        QFETCH(QString, text);
        TextFile f;
        QVERIFY(TextFiles::decode(bytes, &f));
        QCOMPARE(int(f.encoding), encoding);
        QCOMPARE(f.bom, bom);
        QCOMPARE(f.text, text);
        QCOMPARE(TextFiles::encode(f), bytes); // byte for byte
    }

    void textFileRejectsWhatItCannotKeep()
    {
        TextFile f;
        QString error;
        QVERIFY(!TextFiles::decode(QByteArray("Salom \xC0\xC1 dunyo"), &f, &error)); // not UTF-8 (e.g. cp1251)
        QVERIFY(!error.isEmpty());
        QVERIFY(!TextFiles::decode(QByteArray("\xFF\xFE\x41", 3), &f, &error)); // odd UTF-16
    }

    void plainText()
    {
        QCOMPARE(convertDoc(DocumentFormat::PlainText, QStringLiteral("Toshkent shahri"), Script::Lat, Script::Cyr),
                 QStringLiteral("Тошкент шаҳри"));
        DocumentResult r;
        QCOMPARE(convertDoc(DocumentFormat::PlainText, QStringLiteral("Салом"), Script::Auto, Script::Lat, &r),
                 QStringLiteral("Salom"));
        QCOMPARE(r.from, Script::Cyr);
        QVERIFY(r.changed);
    }

    void markdown()
    {
        const QString in = QStringLiteral(
            "---\ntitle: shahar\n---\n# Toshkent shahri\n\nMatn `kod shahar` va [havola](http://example.com/shahar) "
            "<span class=\"shahar\">shahar</span>.\n\n```js\nconst shahar = 1;\n```\n\n    indented shahar\n\n"
            "[ref]: http://example.com/shahar\n");
        const QString want = QStringLiteral(
            "---\ntitle: shahar\n---\n# Тошкент шаҳри\n\nМатн `kod shahar` ва [ҳавола](http://example.com/shahar) "
            "<span class=\"shahar\">шаҳар</span>.\n\n```js\nconst shahar = 1;\n```\n\n    indented shahar\n\n"
            "[ref]: http://example.com/shahar\n");
        QVERIFY(sameText(convertDoc(DocumentFormat::Markdown, in, Script::Lat, Script::Cyr), want));
    }

    void subtitles()
    {
        const QString in = QStringLiteral("1\r\n00:00:01,000 --> 00:00:02,500\r\n<i>Salom</i>, dunyo!\r\n{\\an8}Toshkent\r\n\r\n"
                                          "2\r\n00:00:03,000 --> 00:00:04,000\r\n2026 yil\r\n");
        const QString want = QStringLiteral("1\r\n00:00:01,000 --> 00:00:02,500\r\n<i>Салом</i>, дунё!\r\n{\\an8}Тошкент\r\n\r\n"
                                            "2\r\n00:00:03,000 --> 00:00:04,000\r\n2026 йил\r\n");
        QVERIFY(sameText(convertDoc(DocumentFormat::Subtitles, in, Script::Lat, Script::Cyr), want));
    }

    void json()
    {
        const QString in = QStringLiteral(
            "{\n  \"shahar\": \"Toshkent shahri\",\n  \"n\": 1,\n  \"list\": [\"salom\", \"o\\u0027zbek\", \"a\\nb\"],\n"
            "  \"esc\": \"\\u0421\\u0430\\u043b\\u043e\\u043c\",\n  \"same\": \"2026\"\n}\n");
        // keys stay, values convert; a string that spelled non-ASCII as \uXXXX keeps doing so
        const QString want = QStringLiteral(
            "{\n  \"shahar\": \"Тошкент шаҳри\",\n  \"n\": 1,\n  \"list\": [\"салом\", \"ўзбек\", \"а\\nб\"],\n"
            "  \"esc\": \"\\u0421\\u0430\\u043b\\u043e\\u043c\",\n  \"same\": \"2026\"\n}\n");
        QVERIFY(sameText(convertDoc(DocumentFormat::Json, in, Script::Lat, Script::Cyr), want));
        const QString cyr = QStringLiteral("{\"a\": \"\\u0421\\u0430\\u043b\\u043e\\u043c\"}");
        QCOMPARE(convertDoc(DocumentFormat::Json, cyr, Script::Cyr, Script::Lat),
                 QStringLiteral("{\"a\": \"Salom\"}"));
    }

    void htmlTextNodesOnly()
    {
        // not XML (<meta>, <br>): the tag-preserving rewrite
        const QString in = QStringLiteral(
            "<!DOCTYPE html>\n<html lang=\"uz\"><head><meta charset=\"utf-8\"><title>Salom</title>"
            "<style>p::before{content:\"shahar\"}</style><script>if (a > b) s = \"shahar\";</script></head>\n"
            "<body><p class=\"shahar\" title='shahar'>Toshkent <b>shahri</b> &amp; viloyati&nbsp;&mdash; 1<br>"
            "O&#39;zbekiston</p><!-- shahar --><code>shahar</code><span translate=\"no\">shahar</span>"
            "<div class=\"a notranslate\">shahar <i>shahar</i></div><textarea>shahar</textarea> a &lt; b &unknown; shahar</body></html>\n");
        const QString want = QStringLiteral(
            "<!DOCTYPE html>\n<html lang=\"uz\"><head><meta charset=\"utf-8\"><title>Салом</title>"
            "<style>p::before{content:\"shahar\"}</style><script>if (a > b) s = \"shahar\";</script></head>\n"
            "<body><p class=\"shahar\" title='shahar'>Тошкент <b>шаҳри</b> &amp; вилояти&nbsp;— 1<br>"
            "Ўзбекистон</p><!-- shahar --><code>shahar</code><span translate=\"no\">shahar</span>"
            "<div class=\"a notranslate\">shahar <i>shahar</i></div><textarea>шаҳар</textarea> а &lt; б &unknown; шаҳар</body></html>\n");
        QVERIFY(sameText(convertDoc(DocumentFormat::Html, in, Script::Lat, Script::Cyr), want));
    }

    void xhtmlThroughXmlStream()
    {
        const QString in = QStringLiteral(
            "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<!DOCTYPE html>\n"
            "<html xmlns=\"http://www.w3.org/1999/xhtml\" xml:lang=\"uz\"><head><title>Salom</title>"
            "<script>if (a > b) s = \"shahar\";</script></head>\n<body><p>Toshkent shahri</p><div></div><br/>"
            "<code>shahar</code><p translate=\"no\">shahar</p></body></html>\n");
        const QString want = QStringLiteral(
            "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<!DOCTYPE html>\n"
            "<html xmlns=\"http://www.w3.org/1999/xhtml\" xml:lang=\"uz\"><head><title>Салом</title>"
            "<script>if (a > b) s = \"shahar\";</script></head>\n<body><p>Тошкент шаҳри</p><div></div><br/>"
            "<code>shahar</code><p translate=\"no\">shahar</p></body></html>\n");
        DocumentResult r;
        QVERIFY(sameText(convertDoc(DocumentFormat::Html, in, Script::Lat, Script::Cyr, &r), want));
        QVERIFY(r.warning.isEmpty());
    }

    void xmlStream()
    {
        const QString in = QStringLiteral(
            "<?xml version=\"1.0\"?>\r\n<!-- shahar -->\r\n<kitob xmlns:dc=\"http://purl.org/dc/elements/1.1/\" id=\"1\">\r\n"
            "  <dc:title>Toshkent shahri &amp; viloyati</dc:title>\r\n  <bo/>\r\n  <ikki></ikki>\r\n"
            "  <![CDATA[shahar <b>]]>\r\n  <?pi shahar?>\r\n  <style>a > b { content: \"shahar\" }</style>\r\n</kitob>\r\n");
        const QString want = QStringLiteral(
            "<?xml version=\"1.0\"?>\r\n<!-- shahar -->\r\n<kitob xmlns:dc=\"http://purl.org/dc/elements/1.1/\" id=\"1\">\r\n"
            "  <dc:title>Тошкент шаҳри &amp; вилояти</dc:title>\r\n  <bo/>\r\n  <ikki></ikki>\r\n"
            "  <![CDATA[shahar <b>]]>\r\n  <?pi shahar?>\r\n  <style>a > b { content: \"shahar\" }</style>\r\n</kitob>\r\n");
        DocumentResult r;
        QVERIFY(sameText(convertDoc(DocumentFormat::Xml, in, Script::Lat, Script::Cyr, &r), want));
        QVERIFY(r.changed);
        QVERIFY(r.warning.isEmpty());
        // the writer re-serialises markup: single quotes become double quotes (same document)
        QCOMPARE(convertDoc(DocumentFormat::Xml, QStringLiteral("<a b='1'>shahar</a>"), Script::Lat, Script::New),
                 QStringLiteral("<a b=\"1\">şahar</a>"));
    }

    void xmlNotWellFormedFallsBack()
    {
        DocumentResult r;
        QCOMPARE(convertDoc(DocumentFormat::Xml, QStringLiteral("<a><b>shahar</a>"), Script::Lat, Script::Cyr, &r),
                 QStringLiteral("<a><b>шаҳар</a>"));
        QVERIFY(!r.warning.isEmpty());
    }

    void autoDetectionIgnoresMarkup()
    {
        // far more Latin letters in the markup than Cyrillic ones in the text
        const QString in = QStringLiteral("<div class=\"container-fluid navigation-wrapper\"><p>Салом</p></div>");
        DocumentResult r;
        QCOMPARE(convertDoc(DocumentFormat::Html, in, Script::Auto, Script::Lat, &r),
                 QStringLiteral("<div class=\"container-fluid navigation-wrapper\"><p>Salom</p></div>"));
        QCOMPARE(r.from, Script::Cyr);
        QCOMPARE(convertDoc(DocumentFormat::Json, QStringLiteral("{\"title\": \"Салом\"}"), Script::Auto, Script::Lat, &r),
                 QStringLiteral("{\"title\": \"Salom\"}"));
        QCOMPARE(r.from, Script::Cyr);
    }

    void sameScriptIsUnchanged()
    {
        DocumentResult r;
        const QString in = QStringLiteral("<p>Salom</p>");
        QCOMPARE(convertDoc(DocumentFormat::Html, in, Script::Auto, Script::Lat, &r), in);
        QVERIFY(!r.changed);
    }

    void formats()
    {
        QCOMPARE(Documents::formatForFileName(QStringLiteral("a.MD")), DocumentFormat::Markdown);
        QCOMPARE(Documents::formatForFileName(QStringLiteral("a.srt")), DocumentFormat::Subtitles);
        QCOMPARE(Documents::formatForFileName(QStringLiteral("a.json")), DocumentFormat::Json);
        QCOMPARE(Documents::formatForFileName(QStringLiteral("a.htm")), DocumentFormat::Html);
        QCOMPARE(Documents::formatForFileName(QStringLiteral("a.xml")), DocumentFormat::Xml);
        QCOMPARE(Documents::formatForFileName(QStringLiteral("a.csv")), DocumentFormat::PlainText);
        QCOMPARE(Documents::batchSuffixes(),
                 QStringList({"txt", "md", "csv", "srt", "html", "json", "xml"}));
    }

    void batchFolder()
    {
        QTemporaryDir tmp;
        QVERIFY(tmp.isValid());
        const QString src = tmp.filePath(QStringLiteral("hujjatlar"));
        const QString out = tmp.filePath(QStringLiteral("hujjatlar-new"));
        QVERIFY(writeAll(src + QStringLiteral("/a.txt"), QByteArray("\xEF\xBB\xBF") + QStringLiteral("Тошкент шаҳри\r\n").toUtf8()));
        QVERIFY(writeAll(src + QStringLiteral("/ichki/b.md"), QStringLiteral("# Shahar `kod shahar`\n").toUtf8()));
        QVERIFY(writeAll(src + QStringLiteral("/ichki/c.csv"), QStringLiteral("shahar,2026\n").toUtf8()));
        QVERIFY(writeAll(src + QStringLiteral("/d.png"), QByteArray("\x89PNG", 4)));         // not a batch type
        QVERIFY(writeAll(src + QStringLiteral("/.hidden.txt"), QByteArray("shahar")));     // hidden
        QVERIFY(writeAll(src + QStringLiteral("/bad.txt"), QByteArray("\xC0\xC1")));       // not UTF-8
        QVERIFY(writeAll(src + QStringLiteral("/e.json"), QByteArray("{\"k\": \"Ozbek\"}")));

        const QList<BatchItem> items = Batch::collectFolder(src, out, true, Documents::batchSuffixes());
        QStringList names;
        for (const BatchItem &i : items)
            names << i.display;
        QCOMPARE(names, QStringList({"a.txt", "bad.txt", "e.json", "ichki/b.md", "ichki/c.csv"}));
        QCOMPARE(Batch::collectFolder(src, out, false, Documents::batchSuffixes()).size(), 3);

        int converted = 0, unchanged = 0, failed = 0;
        for (const BatchItem &i : items) {
            const BatchItemResult r = Batch::convertFile(i, Script::Auto, Script::New, Options());
            converted += r.status == BatchStatus::Converted;
            unchanged += r.status == BatchStatus::Unchanged;
            failed += r.status == BatchStatus::Failed;
        }
        QCOMPARE(converted, 3);
        QCOMPARE(unchanged, 1); // e.json: "Ozbek" is the same in Latin 1995 and 2026
        QCOMPARE(failed, 1);    // bad.txt
        QCOMPARE(readAll(out + QStringLiteral("/a.txt")),
                 QByteArray("\xEF\xBB\xBF") + QStringLiteral("Toşkent şahri\r\n").toUtf8()); // BOM and CRLF kept
        QCOMPARE(readAll(out + QStringLiteral("/ichki/b.md")), QStringLiteral("# Şahar `kod shahar`\n").toUtf8());
        QCOMPARE(readAll(out + QStringLiteral("/ichki/c.csv")), QStringLiteral("şahar,2026\n").toUtf8());
        QVERIFY(!QFile::exists(out + QStringLiteral("/bad.txt")));
        // the sources are untouched
        QCOMPARE(readAll(src + QStringLiteral("/ichki/c.csv")), QStringLiteral("shahar,2026\n").toUtf8());
    }

    void batchNeverOverwritesTheSource()
    {
        QTemporaryDir tmp;
        const QString f = tmp.filePath(QStringLiteral("a.txt"));
        QVERIFY(writeAll(f, QByteArray("shahar")));
        const QList<BatchItem> items = Batch::collectFiles({f}, tmp.path());
        QCOMPARE(items.size(), 1);
        const BatchItemResult r = Batch::convertFile(items.front(), Script::Lat, Script::Cyr, Options());
        QCOMPARE(r.status, BatchStatus::Failed);
        QCOMPARE(readAll(f), QByteArray("shahar"));
    }

    void batchSkipsOutputInsideSource()
    {
        QTemporaryDir tmp;
        QVERIFY(writeAll(tmp.filePath(QStringLiteral("a.txt")), QByteArray("shahar")));
        QVERIFY(writeAll(tmp.filePath(QStringLiteral("out/old.txt")), QByteArray("shahar")));
        const QList<BatchItem> items =
            Batch::collectFolder(tmp.path(), tmp.filePath(QStringLiteral("out")), true, {QStringLiteral("txt")});
        QCOMPARE(items.size(), 1);
        QCOMPARE(items.front().display, QStringLiteral("a.txt"));
    }

    void batchJobCountsAndCancels()
    {
        QTemporaryDir tmp;
        for (int i = 0; i < 5; ++i)
            QVERIFY(writeAll(tmp.filePath(QStringLiteral("in/%1.txt").arg(i)), QByteArray("shahar")));
        const QList<BatchItem> items =
            Batch::collectFolder(tmp.filePath(QStringLiteral("in")), tmp.filePath(QStringLiteral("out")), true, {QStringLiteral("txt")});
        BatchJob job(items, Script::Lat, Script::Cyr, Options());
        QSignalSpy items_(&job, &BatchJob::itemFinished);
        QSignalSpy done(&job, &BatchJob::finished);
        job.run();
        QCOMPARE(items_.size(), 5);
        QCOMPARE(done.size(), 1);
        QCOMPARE(done.front().at(0).toInt(), 5);
        QCOMPARE(done.front().at(3).toBool(), false);
        BatchJob cancelled(items, Script::Lat, Script::Cyr, Options());
        QSignalSpy cancelledDone(&cancelled, &BatchJob::finished);
        cancelled.cancel();
        cancelled.run();
        QCOMPARE(cancelledDone.size(), 1);
        QCOMPARE(cancelledDone.front().at(3).toBool(), true);
    }
};

QTEST_GUILESS_MAIN(TestDocuments)
#include "tst_documents.moc"
