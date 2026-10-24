// GUI smoke test (QT_QPA_PLATFORM=offscreen unless set): the main window converts typed and opened text, swaps,
// copies, converts the clipboard, accepts dropped files, switches the interface language, remembers its settings,
// and the batch dialog converts a folder.
#include "batchdialog.hpp"
#include "language.hpp"
#include "mainwindow.hpp"

#include <QAction>
#include <QApplication>
#include <QClipboard>
#include <QDir>
#include <QFile>
#include <QLineEdit>
#include <QMimeData>
#include <QPlainTextEdit>
#include <QPushButton>
#include <QSettings>
#include <QTemporaryDir>
#include <QtTest>

using uztranslit::Script;
using namespace uzt;

namespace {

QByteArray readAll(const QString &path)
{
    QFile f(path);
    return f.open(QIODevice::ReadOnly) ? f.readAll() : QByteArray("<missing>");
}

void writeAll(const QString &path, const QByteArray &bytes)
{
    QDir().mkpath(QFileInfo(path).absolutePath());
    QFile f(path);
    QVERIFY(f.open(QIODevice::WriteOnly));
    QCOMPARE(f.write(bytes), bytes.size());
}

void dropFiles(QWidget *target, const QStringList &paths)
{
    QMimeData mime;
    QList<QUrl> urls;
    for (const QString &p : paths)
        urls << QUrl::fromLocalFile(p);
    mime.setUrls(urls);
    const QPoint pos = target->rect().center();
    QDragEnterEvent enter(pos, Qt::CopyAction, &mime, Qt::LeftButton, Qt::NoModifier);
    QCoreApplication::sendEvent(target, &enter);
    QVERIFY(enter.isAccepted());
    QDropEvent drop(QPointF(pos), Qt::CopyAction, &mime, Qt::LeftButton, Qt::NoModifier);
    QCoreApplication::sendEvent(target, &drop);
    QVERIFY(drop.isAccepted());
}

} // namespace

class TestGui : public QObject
{
    Q_OBJECT

    QTemporaryDir m_tmp;

private slots:
    void initTestCase()
    {
        QVERIFY(m_tmp.isValid());
        QCoreApplication::setOrganizationName(QStringLiteral("UzTranslitTest"));
        QCoreApplication::setApplicationName(QStringLiteral("UzTranslitTest"));
        QSettings::setDefaultFormat(QSettings::IniFormat);
        QSettings::setPath(QSettings::IniFormat, QSettings::UserScope, m_tmp.filePath(QStringLiteral("settings")));
        QVERIFY(Language::apply(QStringLiteral("uz")));
    }

    void init()
    {
        QSettings().clear();
        Language::apply(QStringLiteral("uz"));
    }

    void liveConversion()
    {
        MainWindow w;
        w.show();
        QVERIFY(QTest::qWaitForWindowExposed(&w));
        QCOMPARE(w.source(), Script::Auto);
        QCOMPARE(w.target(), Script::New); // the default target
        w.setInputText(QStringLiteral("O'zbekiston shahri"));
        QCOMPARE(w.outputText(), QStringLiteral("Özbekiston şahri"));
        QCOMPARE(w.displayedOutput(), QStringLiteral("Özbekiston şahri"));
        QCOMPARE(w.detectedText(), QStringLiteral("aniqlandi: lotin 1995"));

        auto *input = w.findChild<QPlainTextEdit *>(QStringLiteral("input"));
        QVERIFY(input);
        input->clear();
        QTest::keyClicks(input, QStringLiteral("Toshkent shahri"));
        QTRY_COMPARE(w.outputText(), QStringLiteral("Toşkent şahri"));

        auto *toCyr = w.findChild<QPushButton *>(QStringLiteral("target_cyr"));
        QVERIFY(toCyr);
        QTest::mouseClick(toCyr, Qt::LeftButton);
        QCOMPARE(w.target(), Script::Cyr);
        QCOMPARE(w.outputText(), QStringLiteral("Тошкент шаҳри"));

        auto *fromCyr = w.findChild<QPushButton *>(QStringLiteral("source_cyr"));
        QTest::mouseClick(fromCyr, Qt::LeftButton);
        QCOMPARE(w.source(), Script::Cyr);
        QVERIFY(w.detectedText().isEmpty());
        QCOMPARE(w.outputText(), QStringLiteral("Toshkent shahri")); // cyr → cyr: unchanged

        w.setAsciiApostrophe(true);
        w.setSource(Script::Cyr);
        w.setTarget(Script::Lat);
        w.setInputText(QStringLiteral("Ўзбекистон"));
        QCOMPARE(w.outputText(), QStringLiteral("O'zbekiston"));
    }

    void editorKeepsNoBreakSpaces()
    {
        MainWindow w;
        w.setSource(Script::Lat);
        w.setTarget(Script::Cyr);
        auto *input = w.findChild<QPlainTextEdit *>(QStringLiteral("input"));
        QTest::keyClicks(input, QStringLiteral("10"));
        input->insertPlainText(QString(QChar(0xA0)) + QStringLiteral("shahar"));
        w.convertNow();
        QCOMPARE(w.inputText(), QStringLiteral("10") + QChar(0xA0) + QStringLiteral("shahar"));
        QCOMPARE(w.outputText(), QStringLiteral("10") + QChar(0xA0) + QStringLiteral("шаҳар"));
    }

    void swapCopyAndUndo()
    {
        MainWindow w;
        w.setSource(Script::Auto);
        w.setTarget(Script::Cyr);
        w.setInputText(QStringLiteral("Salom dunyo"));
        QCOMPARE(w.outputText(), QStringLiteral("Салом дунё"));
        w.copyResult();
        QCOMPARE(QGuiApplication::clipboard()->text(), QStringLiteral("Салом дунё"));
        w.swapDirection();
        QCOMPARE(w.source(), Script::Cyr);
        QCOMPARE(w.target(), Script::Lat); // the detected source
        QCOMPARE(w.inputText(), QStringLiteral("Салом дунё"));
        QCOMPARE(w.outputText(), QStringLiteral("Salom dunyo"));
        auto *input = w.findChild<QPlainTextEdit *>(QStringLiteral("input"));
        input->undo(); // the swap replaced the input undoably
        w.convertNow();
        QCOMPARE(w.inputText(), QStringLiteral("Salom dunyo"));
    }

    void clipboardActions()
    {
        MainWindow w;
        QClipboard *cb = QGuiApplication::clipboard();
        cb->setText(QStringLiteral("Тошкент шаҳри"));
        QVERIFY(w.clipboardAction(Script::New));
        w.clipboardAction(Script::New)->trigger();
        QCOMPARE(cb->text(), QStringLiteral("Toşkent şahri"));
        w.clipboardAction(Script::Lat)->trigger(); // auto-detected: new → lat
        QCOMPARE(cb->text(), QStringLiteral("Toshkent shahri"));
        QVERIFY(w.convertClipboard(Script::Cyr));
        QCOMPARE(cb->text(), QStringLiteral("Тошкент шаҳри"));
        QCOMPARE(w.clipboardAction(Script::Cyr)->text(), QStringLiteral("Buferni kirill alifbosiga oʻgirish"));
        cb->clear();
        QVERIFY(!w.convertClipboard(Script::Cyr));
    }

    void openAndSaveKeepEncoding()
    {
        const QString in = m_tmp.filePath(QStringLiteral("kirill.txt"));
        writeAll(in, QByteArray("\xEF\xBB\xBF") + QStringLiteral("Тошкент шаҳри\r\nИсҳоқ\r\n").toUtf8());
        MainWindow w;
        w.setTarget(Script::Lat);
        QVERIFY(w.openFile(in));
        QCOMPARE(w.inputText(), QStringLiteral("Тошкент шаҳри\r\nИсҳоқ\r\n")); // exact, CRLF included
        QCOMPARE(w.detectedText(), QStringLiteral("aniqlandi: kirill"));
        QCOMPARE(w.outputText(), QStringLiteral("Toshkent shahri\r\nIsʼhoq\r\n"));
        const QString out = m_tmp.filePath(QStringLiteral("lotin.txt"));
        QVERIFY(w.saveResult(out));
        QCOMPARE(readAll(out), QByteArray("\xEF\xBB\xBF") + QStringLiteral("Toshkent shahri\r\nIsʼhoq\r\n").toUtf8());
        QVERIFY(w.windowTitle().startsWith(QStringLiteral("kirill.txt")));
        // editing keeps the file's line-end style
        auto *input = w.findChild<QPlainTextEdit *>(QStringLiteral("input"));
        input->moveCursor(QTextCursor::End);
        input->insertPlainText(QStringLiteral("Ш"));
        w.convertNow();
        QCOMPARE(w.inputText(), QStringLiteral("Тошкент шаҳри\r\nИсҳоқ\r\nШ"));
        QCOMPARE(w.outputText(), QStringLiteral("Toshkent shahri\r\nIsʼhoq\r\nSh"));
    }

    void openedHtmlConvertsTextOnly()
    {
        const QString in = m_tmp.filePath(QStringLiteral("sahifa.html"));
        writeAll(in, QStringLiteral("<p class=\"shahar\">Toshkent <b>shahri</b></p><script>var s = 'shahar';</script><br>").toUtf8());
        MainWindow w;
        w.setTarget(Script::Cyr);
        QVERIFY(w.openFile(in));
        QCOMPARE(w.documentFormat(), DocumentFormat::Html);
        QCOMPARE(w.outputText(),
                 QStringLiteral("<p class=\"shahar\">Тошкент <b>шаҳри</b></p><script>var s = 'shahar';</script><br>"));
        w.clearInput();
        QCOMPARE(w.documentFormat(), DocumentFormat::PlainText);
        QVERIFY(w.outputText().isEmpty());
    }

    void dropOpensFilesAndFolders()
    {
        const QString file = m_tmp.filePath(QStringLiteral("drop/yangi.txt"));
        writeAll(file, QStringLiteral("Özbekiston").toUtf8());
        MainWindow w;
        w.show();
        QVERIFY(QTest::qWaitForWindowExposed(&w));
        w.setTarget(Script::Cyr);
        auto *input = w.findChild<QPlainTextEdit *>(QStringLiteral("input"));
        dropFiles(input->viewport(), {file});
        QTRY_COMPARE(w.inputText(), QStringLiteral("Özbekiston"));
        QCOMPARE(w.outputText(), QStringLiteral("Ўзбекистон"));
        QCOMPARE(input->toPlainText(), QStringLiteral("Özbekiston")); // opened, not inserted as a file path

        dropFiles(&w, {QFileInfo(file).absolutePath()});
        BatchDialog *dialog = nullptr;
        QTRY_VERIFY((dialog = w.findChild<BatchDialog *>()) != nullptr);
        QTRY_VERIFY(dialog->isVisible());
        auto *source = dialog->findChild<QLineEdit *>(QStringLiteral("sourceEdit"));
        QCOMPARE(QDir::fromNativeSeparators(source->text()), QFileInfo(file).absolutePath());
        QCOMPARE(dialog->outputFolder(), QFileInfo(file).absolutePath() + QStringLiteral("-cyr"));
        dialog->close();
    }

    void languages()
    {
        MainWindow w;
        QCOMPARE(w.swapButtonText(), QStringLiteral("⇄ Almashtirish"));
        auto *cyr = w.findChild<QPushButton *>(QStringLiteral("source_cyr"));
        QCOMPARE(cyr->text(), QStringLiteral("Кирилл"));
        QCOMPARE(w.findChild<QPushButton *>(QStringLiteral("source_auto"))->text(), QStringLiteral("Avto"));
        QCOMPARE(w.findChild<QPushButton *>(QStringLiteral("source_new"))->text(), QStringLiteral("Yangi lotin"));
        QCOMPARE(QCoreApplication::translate("QWidgetTextControl", "&Copy"), QStringLiteral("&Nusxa olish"));

        w.setLanguage(QStringLiteral("ru")); // QEvent::LanguageChange is posted to every window
        QTRY_COMPARE(w.swapButtonText(), QStringLiteral("⇄ Поменять местами"));
        QCOMPARE(cyr->text(), QStringLiteral("Кириллица"));
        QCOMPARE(w.findChild<QPushButton *>(QStringLiteral("source_new"))->text(), QStringLiteral("Новая латиница"));
        QCOMPARE(w.clipboardAction(Script::Lat)->text(), QStringLiteral("Конвертировать буфер обмена: латиница 1995"));

        w.setLanguage(QStringLiteral("en"));
        QTRY_COMPARE(w.swapButtonText(), QStringLiteral("⇄ Swap"));
        QCOMPARE(cyr->text(), QStringLiteral("Cyrillic"));
        QCOMPARE(w.clipboardAction(Script::New)->text(), QStringLiteral("Convert clipboard to Latin 2026"));

        w.setLanguage(QStringLiteral("uz"));
        QTRY_COMPARE(w.swapButtonText(), QStringLiteral("⇄ Almashtirish"));
        QCOMPARE(QSettings().value(QStringLiteral("ui/language")).toString(), QStringLiteral("uz"));
    }

    void settingsPersist()
    {
        {
            MainWindow w;
            w.setSource(Script::Cyr);
            w.setTarget(Script::Lat);
            w.setAsciiApostrophe(true);
        }
        MainWindow again;
        QCOMPARE(again.source(), Script::Cyr);
        QCOMPARE(again.target(), Script::Lat);
        QVERIFY(again.settings().asciiApostrophe);
        QVERIFY(again.settings().dictionary);
        QVERIFY(again.settings().dropHardSignAfterO);
        again.setInputText(QStringLiteral("Ўзбек"));
        QCOMPARE(again.outputText(), QStringLiteral("O'zbek"));
    }

    void batchDialogConvertsAFolder()
    {
        const QString src = m_tmp.filePath(QStringLiteral("papka"));
        writeAll(src + QStringLiteral("/a.txt"), QStringLiteral("Тошкент шаҳри").toUtf8());
        writeAll(src + QStringLiteral("/ichki/b.html"), QStringLiteral("<p title=\"Салом\">Салом</p>").toUtf8());
        writeAll(src + QStringLiteral("/ichki/c.srt"), QStringLiteral("1\n00:00:01,000 --> 00:00:02,000\nСалом\n").toUtf8());
        writeAll(src + QStringLiteral("/skip.bin"), QByteArray("\x00\x01", 2));
        MainWindow w;
        w.setTarget(Script::New);
        BatchDialog *dialog = w.openBatchDialog(src);
        QVERIFY(dialog);
        const QString out = m_tmp.filePath(QStringLiteral("natija"));
        dialog->setOutputFolder(out);
        QSignalSpy done(dialog, &BatchDialog::batchFinished);
        QVERIFY(dialog->start());
        QVERIFY(dialog->isRunning() || done.size() == 1);
        QVERIFY(done.size() == 1 || done.wait(20000));
        QCOMPARE(done.front().at(0).toInt(), 3);
        QCOMPARE(dialog->convertedCount(), 3);
        QCOMPARE(dialog->failedCount(), 0);
        QVERIFY(!dialog->isRunning());
        QCOMPARE(readAll(out + QStringLiteral("/a.txt")), QStringLiteral("Toşkent şahri").toUtf8());
        QCOMPARE(readAll(out + QStringLiteral("/ichki/b.html")), QStringLiteral("<p title=\"Салом\">Salom</p>").toUtf8());
        QCOMPARE(readAll(out + QStringLiteral("/ichki/c.srt")),
                 QStringLiteral("1\n00:00:01,000 --> 00:00:02,000\nSalom\n").toUtf8());
        QVERIFY(!QFile::exists(out + QStringLiteral("/skip.bin")));
        QVERIFY2(dialog->logText().contains(QStringLiteral("a.txt: oʻgirildi (kirill → yangi lotin)")),
                 qPrintable(dialog->logText()));
        // the output folder must not be the source folder
        dialog->setOutputFolder(src);
        QVERIFY(!dialog->start());
        QVERIFY(!dialog->statusText().isEmpty());
        dialog->close();
    }

    // UZT_SCREENSHOT_DIR=dir saves the main window and the batch dialog in each language (for reviewing layouts)
    void screenshots()
    {
        const QString dir = qEnvironmentVariable("UZT_SCREENSHOT_DIR");
        if (dir.isEmpty())
            QSKIP("set UZT_SCREENSHOT_DIR to save screenshots");
        QDir().mkpath(dir);
        for (const QString &lang : Language::ids()) {
            Language::apply(lang);
            MainWindow w;
            w.resize(1040, 560);
            w.show();
            QVERIFY(QTest::qWaitForWindowExposed(&w));
            w.setInputText(QStringLiteral("Oʻzbekiston Respublikasi, Toshkent shahri. Isʼhoq, maʼno, obyekt, sirk, abzats."));
            QCoreApplication::processEvents();
            QVERIFY(w.grab().save(QDir(dir).filePath(QStringLiteral("main-%1.png").arg(lang))));
            BatchDialog *d = w.openBatchDialog(m_tmp.path());
            QVERIFY(QTest::qWaitForWindowExposed(d));
            QCoreApplication::processEvents();
            QVERIFY(d->grab().save(QDir(dir).filePath(QStringLiteral("batch-%1.png").arg(lang))));
            d->close();
        }
        Language::apply(QStringLiteral("uz"));
    }
};

int main(int argc, char **argv)
{
    if (!qEnvironmentVariableIsSet("QT_QPA_PLATFORM"))
        qputenv("QT_QPA_PLATFORM", "offscreen");
    QApplication app(argc, argv);
    QApplication::setQuitOnLastWindowClosed(false);
    TestGui test;
    return QTest::qExec(&test, argc, argv);
}

#include "tst_gui.moc"
