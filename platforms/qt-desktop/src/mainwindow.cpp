#include "mainwindow.hpp"

#include "batchdialog.hpp"
#include "language.hpp"

#include <QAction>
#include <QActionGroup>
#include <QApplication>
#include <QButtonGroup>
#include <QClipboard>
#include <QCloseEvent>
#include <QDir>
#include <QDragEnterEvent>
#include <QDropEvent>
#include <QFileDialog>
#include <QFileInfo>
#include <QGridLayout>
#include <QHBoxLayout>
#include <QLabel>
#include <QMenu>
#include <QMenuBar>
#include <QMessageBox>
#include <QMimeData>
#include <QPlainTextEdit>
#include <QPushButton>
#include <QSplitter>
#include <QStatusBar>
#include <QTextCursor>
#include <QTextDocument>
#include <QVBoxLayout>

using uztranslit::Script;

namespace uzt {

namespace {

constexpr Script SOURCE_ORDER[] = {Script::Auto, Script::Cyr, Script::Lat, Script::New};
constexpr Script TARGET_ORDER[] = {Script::Cyr, Script::Lat, Script::New};

int targetIndex(Script s)
{
    return s == Script::Cyr ? 0 : s == Script::Lat ? 1 : 2;
}

QIcon appIcon()
{
    QIcon icon;
    for (int size : {16, 24, 32, 48, 64, 128, 256})
        icon.addFile(QStringLiteral(":/icons/uztranslit-%1.png").arg(size), QSize(size, size));
    return icon;
}

// characters (code points) and words (runs of non-space characters with a letter or digit)
std::pair<qsizetype, qsizetype> countText(const QString &t)
{
    qsizetype chars = 0;
    qsizetype words = 0;
    bool inWord = false;
    bool wordHasLetter = false;
    for (QChar c : t) {
        if (!c.isLowSurrogate())
            ++chars;
        if (c.isSpace()) {
            if (inWord && wordHasLetter)
                ++words;
            inWord = false;
            wordHasLetter = false;
            continue;
        }
        inWord = true;
        if (c.isLetterOrNumber() || c.isHighSurrogate())
            wordHasLetter = true;
    }
    if (inWord && wordHasLetter)
        ++words;
    return {chars, words};
}

} // namespace

MainWindow::MainWindow(QWidget *parent)
    : QMainWindow(parent), m_settings(AppSettings::load())
{
    setWindowIcon(appIcon());
    setAcceptDrops(true);
    m_convertTimer.setSingleShot(true);
    connect(&m_convertTimer, &QTimer::timeout, this, &MainWindow::convertNow);
    buildUi();
    buildMenus();
    buildTray();
    retranslateUi();
    syncButtons();
    if (m_settings.geometry.isEmpty() || !restoreGeometry(m_settings.geometry))
        resize(1040, 640);
    if (!m_settings.splitterState.isEmpty())
        m_splitter->restoreState(m_settings.splitterState);
    convertNow();
}

MainWindow::~MainWindow() = default;

// ---------------------------------------------------------------- construction
void MainWindow::buildUi()
{
    auto *central = new QWidget(this);
    auto *layout = new QVBoxLayout(central);

    // From: [Avto] [Кирилл] [Lotin 1995] [Yangi lotin]   detected: …
    // To:   [Кирилл] [Lotin 1995] [Yangi lotin]           [⇄ Swap]
    auto *direction = new QGridLayout;
    direction->setColumnStretch(2, 1);
    m_fromLabel = new QLabel(central);
    m_toLabel = new QLabel(central);
    direction->addWidget(m_fromLabel, 0, 0);
    direction->addWidget(m_toLabel, 1, 0);
    auto *sources = new QHBoxLayout;
    m_sourceGroup = new QButtonGroup(this);
    for (int k = 0; k < 4; ++k) {
        auto *b = new QPushButton(central);
        b->setCheckable(true);
        b->setObjectName(QStringLiteral("source_") + uztranslit::scriptId(SOURCE_ORDER[k]));
        m_sourceGroup->addButton(b, int(SOURCE_ORDER[k]));
        m_sourceButtons[k] = b;
        sources->addWidget(b);
    }
    m_detectedLabel = new QLabel(central);
    m_detectedLabel->setObjectName(QStringLiteral("detectedLabel"));
    sources->addSpacing(12);
    sources->addWidget(m_detectedLabel, 1);
    direction->addLayout(sources, 0, 1, 1, 2);
    auto *targets = new QHBoxLayout;
    m_targetGroup = new QButtonGroup(this);
    for (int k = 0; k < 3; ++k) {
        auto *b = new QPushButton(central);
        b->setCheckable(true);
        b->setObjectName(QStringLiteral("target_") + uztranslit::scriptId(TARGET_ORDER[k]));
        m_targetGroup->addButton(b, int(TARGET_ORDER[k]));
        m_targetButtons[k] = b;
        targets->addWidget(b);
    }
    targets->addStretch(1);
    direction->addLayout(targets, 1, 1);
    m_swapButton = new QPushButton(central);
    m_swapButton->setObjectName(QStringLiteral("swapButton"));
    direction->addWidget(m_swapButton, 1, 2, Qt::AlignRight);
    layout->addLayout(direction);

    m_splitter = new QSplitter(Qt::Horizontal, central);
    m_splitter->setChildrenCollapsible(false);
    const auto pane = [this](QLabel *&label, QPlainTextEdit *&edit, const QString &name) {
        auto *w = new QWidget(m_splitter);
        auto *v = new QVBoxLayout(w);
        v->setContentsMargins(0, 0, 0, 0);
        label = new QLabel(w);
        edit = new QPlainTextEdit(w);
        edit->setObjectName(name);
        label->setBuddy(edit);
        v->addWidget(label);
        v->addWidget(edit, 1);
        m_splitter->addWidget(w);
    };
    pane(m_inputLabel, m_input, QStringLiteral("input"));
    pane(m_outputLabel, m_output, QStringLiteral("output"));
    m_output->setReadOnly(true);
    m_output->setUndoRedoEnabled(false);
    layout->addWidget(m_splitter, 1);

    auto *bottom = new QHBoxLayout;
    m_openButton = new QPushButton(central);
    m_pasteButton = new QPushButton(central);
    m_clearButton = new QPushButton(central);
    m_statsLabel = new QLabel(central);
    m_statsLabel->setObjectName(QStringLiteral("statsLabel"));
    m_copyButton = new QPushButton(central);
    m_copyButton->setObjectName(QStringLiteral("copyButton"));
    m_saveButton = new QPushButton(central);
    bottom->addWidget(m_openButton);
    bottom->addWidget(m_pasteButton);
    bottom->addWidget(m_clearButton);
    bottom->addStretch(1);
    bottom->addWidget(m_statsLabel);
    bottom->addStretch(1);
    bottom->addWidget(m_copyButton);
    bottom->addWidget(m_saveButton);
    layout->addLayout(bottom);
    setCentralWidget(central);
    statusBar();

    connect(m_sourceGroup, &QButtonGroup::idClicked, this, [this](int id) { setSource(Script(id)); });
    connect(m_targetGroup, &QButtonGroup::idClicked, this, [this](int id) { setTarget(Script(id)); });
    connect(m_swapButton, &QPushButton::clicked, this, &MainWindow::swapDirection);
    connect(m_input, &QPlainTextEdit::textChanged, this, &MainWindow::scheduleConvert);
    connect(m_openButton, &QPushButton::clicked, this, &MainWindow::onOpen);
    connect(m_pasteButton, &QPushButton::clicked, m_input, &QPlainTextEdit::paste);
    connect(m_clearButton, &QPushButton::clicked, this, &MainWindow::clearInput);
    connect(m_copyButton, &QPushButton::clicked, this, &MainWindow::copyResult);
    connect(m_saveButton, &QPushButton::clicked, this, &MainWindow::onSaveAs);
    // files dropped on the input editor are opened, not inserted as text
    m_input->viewport()->installEventFilter(this);
}

void MainWindow::buildMenus()
{
    m_fileMenu = menuBar()->addMenu(QString());
    m_actOpen = m_fileMenu->addAction(QString(), this, &MainWindow::onOpen);
    m_actOpen->setShortcut(QKeySequence::Open);
    m_actSave = m_fileMenu->addAction(QString(), this, &MainWindow::onSaveAs);
    m_actSave->setShortcut(QKeySequence::Save);
    m_actBatch = m_fileMenu->addAction(QString(), this, [this] { openBatchDialog(); });
    m_actBatch->setShortcut(QKeySequence(Qt::CTRL | Qt::SHIFT | Qt::Key_O));
    m_fileMenu->addSeparator();
    m_actQuit = m_fileMenu->addAction(QString(), qApp, &QCoreApplication::quit);
    m_actQuit->setShortcut(QKeySequence::Quit);
    m_actQuit->setMenuRole(QAction::QuitRole);

    m_editMenu = menuBar()->addMenu(QString());
    m_actCopy = m_editMenu->addAction(QString(), this, &MainWindow::copyResult);
    m_actCopy->setShortcut(QKeySequence(Qt::CTRL | Qt::SHIFT | Qt::Key_C));
    m_actPaste = m_editMenu->addAction(QString(), m_input, &QPlainTextEdit::paste);
    m_actClear = m_editMenu->addAction(QString(), this, &MainWindow::clearInput);
    m_actSwap = m_editMenu->addAction(QString(), this, &MainWindow::swapDirection);
    m_actSwap->setShortcut(QKeySequence(Qt::CTRL | Qt::Key_R));
    m_editMenu->addSeparator();
    m_clipboardMenu = m_editMenu->addMenu(QString());
    for (int k = 0; k < 3; ++k) {
        const Script t = TARGET_ORDER[k];
        m_actClipboard[k] = m_clipboardMenu->addAction(QString(), this, [this, t] { convertClipboard(t); });
        m_actClipboard[k]->setObjectName(QStringLiteral("clipboard_") + uztranslit::scriptId(t));
    }

    m_optionsMenu = menuBar()->addMenu(QString());
    const auto option = [this](bool AppSettings::*field) {
        QAction *a = m_optionsMenu->addAction(QString());
        a->setCheckable(true);
        connect(a, &QAction::toggled, this, [this, field](bool on) {
            if (m_settings.*field == on)
                return;
            m_settings.*field = on;
            optionsChanged();
        });
        return a;
    };
    m_actAscii = option(&AppSettings::asciiApostrophe);
    m_actSkipUrls = option(&AppSettings::skipUrls);
    m_optionsMenu->addSeparator();
    m_actDictionary = option(&AppSettings::dictionary);
    m_actDropHard = option(&AppSettings::dropHardSignAfterO);
    m_actTsFinal = option(&AppSettings::tsFinal);
    m_optionsMenu->addSeparator();
    m_actKeepInTray = m_optionsMenu->addAction(QString());
    m_actKeepInTray->setCheckable(true);
    connect(m_actKeepInTray, &QAction::toggled, this, [this](bool on) {
        m_settings.keepInTray = on;
        m_settings.save();
    });

    m_languageMenu = menuBar()->addMenu(QString());
    m_languageGroup = new QActionGroup(this);
    const QStringList languages = Language::ids();
    for (int k = 0; k < 3; ++k) {
        const QString id = languages[k];
        QAction *a = m_languageMenu->addAction(Language::nativeName(id));
        a->setCheckable(true);
        a->setData(id);
        m_languageGroup->addAction(a);
        m_actLanguage[k] = a;
        connect(a, &QAction::triggered, this, [this, id] { setLanguage(id); });
    }

    m_helpMenu = menuBar()->addMenu(QString());
    m_actAbout = m_helpMenu->addAction(QString(), this, &MainWindow::onAbout);
    m_actAbout->setMenuRole(QAction::AboutRole);
    m_actAboutQt = m_helpMenu->addAction(QString(), qApp, &QApplication::aboutQt);
    m_actAboutQt->setMenuRole(QAction::AboutQtRole);
}

void MainWindow::buildTray()
{
    m_actShow = new QAction(this);
    connect(m_actShow, &QAction::triggered, this, [this] {
        showNormal();
        raise();
        activateWindow();
    });
    if (!QSystemTrayIcon::isSystemTrayAvailable()) {
        m_actKeepInTray->setVisible(false);
        return;
    }
    m_tray = new QSystemTrayIcon(windowIcon(), this);
    m_trayMenu = new QMenu(this);
    for (QAction *a : m_actClipboard)
        m_trayMenu->addAction(a);
    m_trayMenu->addSeparator();
    m_trayMenu->addAction(m_actShow);
    m_trayMenu->addAction(m_actQuit);
    m_tray->setContextMenu(m_trayMenu);
    connect(m_tray, &QSystemTrayIcon::activated, this, &MainWindow::onTrayActivated);
    m_tray->show();
}

void MainWindow::retranslateUi()
{
    m_fromLabel->setText(tr("From:"));
    m_toLabel->setText(tr("To:"));
    for (int k = 0; k < 4; ++k)
        m_sourceButtons[k]->setText(ScriptNames::button(SOURCE_ORDER[k]));
    for (int k = 0; k < 3; ++k)
        m_targetButtons[k]->setText(ScriptNames::button(TARGET_ORDER[k]));
    m_swapButton->setText(tr("⇄ Swap"));
    m_swapButton->setToolTip(tr("Swap the direction and continue with the result"));
    m_inputLabel->setText(tr("&Input"));
    m_outputLabel->setText(tr("&Result"));
    m_input->setPlaceholderText(tr("Type or paste text here, or drop a file — the result appears instantly. "
                                   "E.g.: O'zbekiston Respublikasi, Toshkent shahri."));
    m_output->setPlaceholderText(tr("Result"));
    m_openButton->setText(tr("Open…"));
    m_pasteButton->setText(tr("Paste"));
    m_clearButton->setText(tr("Clear"));
    m_copyButton->setText(tr("Copy"));
    m_saveButton->setText(tr("Save…"));

    m_fileMenu->setTitle(tr("&File"));
    m_actOpen->setText(tr("&Open…"));
    m_actSave->setText(tr("&Save result as…"));
    m_actBatch->setText(tr("Convert a &folder…"));
    m_actQuit->setText(tr("&Quit"));
    m_editMenu->setTitle(tr("&Edit"));
    m_actCopy->setText(tr("&Copy the result"));
    m_actPaste->setText(tr("&Paste into the input"));
    m_actClear->setText(tr("C&lear the input"));
    m_actSwap->setText(tr("S&wap the direction"));
    m_clipboardMenu->setTitle(tr("Convert the clip&board"));
    for (int k = 0; k < 3; ++k)
        m_actClipboard[k]->setText(tr("Convert clipboard to %1").arg(ScriptNames::inSentence(TARGET_ORDER[k])));
    m_optionsMenu->setTitle(tr("&Settings"));
    m_actAscii->setText(tr("Plain apostrophe ( ' ) instead of ʻ and ʼ"));
    m_actSkipUrls->setText(tr("Leave URLs and e-mail addresses unchanged"));
    m_actDictionary->setText(tr("Loanword dictionary: obyekt → объект, sirk → цирк"));
    m_actDropHard->setText(tr("ўъ → oʻ: мўъжиза → moʻjiza"));
    m_actTsFinal->setText(tr("Word-final -ts → ц: abzats → абзац"));
    m_actKeepInTray->setText(tr("Keep running in the system tray when the window is closed"));
    m_languageMenu->setTitle(tr("&Language"));
    m_helpMenu->setTitle(tr("&Help"));
    m_actAbout->setText(tr("&About UzTranslit"));
    m_actAboutQt->setText(tr("About &Qt"));
    m_actShow->setText(tr("Show UzTranslit"));
    if (m_tray)
        m_tray->setToolTip(tr("UzTranslit — Uzbek script converter"));
    updateDetected();
    updateStats();
    updateTitle();
}

void MainWindow::syncButtons()
{
    for (int k = 0; k < 4; ++k)
        m_sourceButtons[k]->setChecked(SOURCE_ORDER[k] == m_settings.source);
    m_targetButtons[targetIndex(m_settings.target)]->setChecked(true);
    const QSignalBlocker b1(m_actAscii), b2(m_actSkipUrls), b3(m_actDictionary), b4(m_actDropHard), b5(m_actTsFinal),
        b6(m_actKeepInTray);
    m_actAscii->setChecked(m_settings.asciiApostrophe);
    m_actSkipUrls->setChecked(m_settings.skipUrls);
    m_actDictionary->setChecked(m_settings.dictionary);
    m_actDropHard->setChecked(m_settings.dropHardSignAfterO);
    m_actTsFinal->setChecked(m_settings.tsFinal);
    m_actKeepInTray->setChecked(m_settings.keepInTray);
    for (QAction *a : m_actLanguage)
        a->setChecked(a->data().toString() == Language::current());
}

// ---------------------------------------------------------------- conversion
QString MainWindow::editorText() const
{
    // toRawText keeps no-break spaces (toPlainText turns them into spaces); blocks are joined by U+2029
    QString t = m_input->document()->toRawText();
    t.replace(QChar(QChar::ParagraphSeparator), m_lineEnding);
    return t;
}

QString MainWindow::inputText() const
{
    if (!m_input->document()->isModified() && !m_loadedText.isNull())
        return m_loadedText;
    return editorText();
}

QString MainWindow::displayedOutput() const
{
    return m_output->toPlainText();
}

void MainWindow::scheduleConvert()
{
    m_convertTimer.start(m_input->document()->characterCount() > 200000 ? 250 : 0);
}

void MainWindow::convertNow()
{
    m_convertTimer.stop();
    const QString text = inputText();
    DocumentResult r;
    QString error;
    if (!Documents::convert(m_format, text, m_settings.source, m_settings.target, m_settings.options(), &r, &error)) {
        showStatus(error);
        return;
    }
    m_detected = r.from;
    if (r.text != m_result || m_output->document()->isEmpty() != r.text.isEmpty()) {
        m_result = r.text;
        m_output->setPlainText(m_result);
    }
    if (!r.warning.isEmpty())
        showStatus(r.warning);
    updateDetected();
    updateStats();
}

void MainWindow::updateDetected()
{
    if (m_settings.source == Script::Auto && !inputText().isEmpty())
        m_detectedLabel->setText(tr("detected: %1").arg(ScriptNames::inSentence(m_detected)));
    else
        m_detectedLabel->clear();
}

QString MainWindow::detectedText() const
{
    return m_detectedLabel->text();
}

void MainWindow::updateStats()
{
    const auto [chars, words] = countText(inputText());
    m_statsLabel->setText(tr("%1 characters · %2 words").arg(chars).arg(words));
}

void MainWindow::updateTitle()
{
    const QString app = QStringLiteral("UzTranslit");
    setWindowTitle(m_currentFile.isEmpty() ? app
                                           : QStringLiteral("%1 — %2").arg(QFileInfo(m_currentFile).fileName(), app));
}

QString MainWindow::formatName(DocumentFormat format) const
{
    switch (format) {
    case DocumentFormat::PlainText: return tr("plain text");
    case DocumentFormat::Markdown: return tr("Markdown");
    case DocumentFormat::Subtitles: return tr("SubRip subtitles");
    case DocumentFormat::Json: return tr("JSON: string values");
    case DocumentFormat::Html: return tr("HTML: text only");
    case DocumentFormat::Xml: return tr("XML: text only");
    }
    return QString();
}

void MainWindow::setSource(Script script)
{
    m_settings.source = script;
    m_settings.save();
    syncButtons();
    convertNow();
}

void MainWindow::setTarget(Script script)
{
    if (script == Script::Auto)
        return;
    m_settings.target = script;
    m_settings.save();
    syncButtons();
    convertNow();
    if (m_batch)
        m_batch->setDirection(m_settings.source, m_settings.target);
}

void MainWindow::setAsciiApostrophe(bool on)
{
    m_actAscii->setChecked(on);
}

void MainWindow::optionsChanged()
{
    m_settings.save();
    if (m_batch)
        m_batch->setOptions(m_settings.options());
    convertNow();
}

void MainWindow::replaceInput(const QString &text)
{
    QTextCursor c(m_input->document());
    c.beginEditBlock();
    c.select(QTextCursor::Document);
    c.insertText(text); // undoable, unlike setPlainText()
    c.endEditBlock();
    m_loadedText = text;
    m_input->document()->setModified(false);
}

void MainWindow::setInputText(const QString &text)
{
    replaceInput(text);
    convertNow();
}

void MainWindow::swapDirection()
{
    convertNow();
    const Script oldSource = m_settings.source == Script::Auto ? m_detected : m_settings.source;
    m_settings.source = m_settings.target;
    m_settings.target = oldSource;
    m_settings.save();
    syncButtons();
    replaceInput(m_result);
    convertNow();
    if (m_batch)
        m_batch->setDirection(m_settings.source, m_settings.target);
}

void MainWindow::copyResult()
{
    convertNow();
    QGuiApplication::clipboard()->setText(m_result);
    showStatus(tr("Copied"));
}

void MainWindow::clearInput()
{
    replaceInput(QString());
    m_loadedText = QString();
    m_format = DocumentFormat::PlainText;
    m_fileFormat = TextFile();
    m_lineEnding = QStringLiteral("\n");
    m_currentFile.clear();
    updateTitle();
    convertNow();
}

QString MainWindow::swapButtonText() const
{
    return m_swapButton->text();
}

// ---------------------------------------------------------------- files
bool MainWindow::openFile(const QString &path)
{
    TextFile file;
    QString error;
    if (!TextFiles::read(path, &file, &error)) {
        QMessageBox::warning(this, tr("UzTranslit"),
                             tr("Cannot open %1:\n%2").arg(QDir::toNativeSeparators(path), error));
        return false;
    }
    const QFileInfo fi(path);
    m_currentFile = fi.absoluteFilePath();
    m_settings.lastDirectory = fi.absolutePath();
    m_settings.save();
    m_format = Documents::formatForFileName(path);
    m_lineEnding = file.text.contains(QStringView(u"\r\n")) ? QStringLiteral("\r\n") : QStringLiteral("\n");
    m_fileFormat = file;
    m_fileFormat.text.clear();
    m_input->setPlainText(file.text);
    m_loadedText = file.text;
    m_input->document()->setModified(false);
    updateTitle();
    convertNow();
    showStatus(tr("Opened %1 (%2)").arg(fi.fileName(), formatName(m_format)));
    return true;
}

bool MainWindow::saveResult(const QString &path)
{
    convertNow();
    TextFile out = m_fileFormat;
    out.text = m_result;
    QString error;
    if (!TextFiles::write(path, out, &error)) {
        QMessageBox::warning(this, tr("UzTranslit"),
                             tr("Cannot save %1:\n%2").arg(QDir::toNativeSeparators(path), error));
        return false;
    }
    m_settings.lastDirectory = QFileInfo(path).absolutePath();
    m_settings.save();
    showStatus(tr("Saved: %1").arg(QDir::toNativeSeparators(path)));
    return true;
}

void MainWindow::onOpen()
{
    const QString filter = tr("Text files") + QStringLiteral(" (*.txt *.md *.csv *.srt *.html *.htm *.json *.xml);;")
                           + tr("All files") + QStringLiteral(" (*)");
    const QString path = QFileDialog::getOpenFileName(this, tr("Open a text file"), m_settings.lastDirectory, filter);
    if (!path.isEmpty())
        openFile(path);
}

void MainWindow::onSaveAs()
{
    QString suggestion;
    const QString target = uztranslit::scriptId(m_settings.target);
    if (!m_currentFile.isEmpty()) {
        const QFileInfo fi(m_currentFile);
        suggestion = fi.absoluteDir().filePath(fi.completeBaseName() + u'-' + target
                                               + (fi.suffix().isEmpty() ? QString() : u'.' + fi.suffix()));
    } else {
        suggestion = QDir(m_settings.lastDirectory.isEmpty() ? QDir::homePath() : m_settings.lastDirectory)
                         .filePath(QStringLiteral("uztranslit-%1.txt").arg(target));
    }
    const QString path = QFileDialog::getSaveFileName(this, tr("Save the result as"), suggestion,
                                                      tr("All files") + QStringLiteral(" (*)"));
    if (!path.isEmpty())
        saveResult(path);
}

void MainWindow::onAbout()
{
    QMessageBox::about(
        this, tr("About UzTranslit"),
        tr("<p><b>UzTranslit %1</b></p>"
           "<p>Converts Uzbek text between Cyrillic, Latin 1995 and the Latin alphabet of law OʻRQ-1184 "
           "(21 October 2026): Oʻ→Ö, Gʻ→Ğ, Sh→Ş, Ch→Ç.</p>"
           "<p>The engine is the C++ port of the UzTranslit specification v%2 and passes its conformance tests. "
           "Your text never leaves this computer.</p>"
           "<p>MIT License · <a href=\"https://latin.jaybi.uz\">latin.jaybi.uz</a></p>")
            .arg(QCoreApplication::applicationVersion(), QLatin1String(uztranslit::VERSION)));
}

// ---------------------------------------------------------------- clipboard, tray
QAction *MainWindow::clipboardAction(Script target) const
{
    return m_actClipboard[targetIndex(target)];
}

bool MainWindow::convertClipboard(Script target)
{
    QClipboard *clipboard = QGuiApplication::clipboard();
    const QString text = clipboard->text();
    if (text.isEmpty()) {
        notify(tr("The clipboard has no text."));
        return false;
    }
    clipboard->setText(uztranslit::convert(text, Script::Auto, target, m_settings.options()));
    notify(tr("Clipboard converted to %1.").arg(ScriptNames::inSentence(target)));
    return true;
}

void MainWindow::notify(const QString &text)
{
    if (m_tray && m_tray->isVisible() && !isVisible())
        m_tray->showMessage(QStringLiteral("UzTranslit"), text, QSystemTrayIcon::Information, 3000);
    else
        showStatus(text);
}

void MainWindow::showStatus(const QString &text)
{
    statusBar()->showMessage(text, 6000);
}

void MainWindow::onTrayActivated(QSystemTrayIcon::ActivationReason reason)
{
    if (reason != QSystemTrayIcon::Trigger)
        return;
    if (isVisible() && isActiveWindow()) {
        hide();
    } else {
        showNormal();
        raise();
        activateWindow();
    }
}

BatchDialog *MainWindow::openBatchDialog(const QString &folder, const QStringList &files)
{
    if (!m_batch) {
        m_batch = new BatchDialog(m_settings.source, m_settings.target, m_settings.options(), this);
        m_batch->setAttribute(Qt::WA_DeleteOnClose);
    }
    if (!files.isEmpty())
        m_batch->setSourceFiles(files);
    else if (!folder.isEmpty())
        m_batch->setSourceFolder(folder);
    m_batch->show();
    m_batch->raise();
    m_batch->activateWindow();
    return m_batch;
}

void MainWindow::setLanguage(const QString &id)
{
    m_settings.language = id;
    m_settings.save();
    Language::apply(id); // LanguageChange reaches every widget: see changeEvent()
    syncButtons();
}

// ---------------------------------------------------------------- events
void MainWindow::changeEvent(QEvent *event)
{
    if (event->type() == QEvent::LanguageChange)
        retranslateUi();
    QMainWindow::changeEvent(event);
}

void MainWindow::closeEvent(QCloseEvent *event)
{
    m_settings.geometry = saveGeometry();
    m_settings.splitterState = m_splitter->saveState();
    m_settings.save();
    if (m_tray && m_tray->isVisible() && m_settings.keepInTray) {
        hide();
        event->ignore();
        if (!m_trayHintShown) {
            m_tray->showMessage(QStringLiteral("UzTranslit"),
                                tr("UzTranslit keeps running in the system tray: right-click its icon to convert "
                                   "the clipboard or to quit."),
                                QSystemTrayIcon::Information, 5000);
            m_trayHintShown = true;
        }
        return;
    }
    if (m_batch)
        m_batch->close();
    event->accept();
    QCoreApplication::quit();
}

QList<QUrl> MainWindow::localFileUrls(const QMimeData *mime)
{
    QList<QUrl> out;
    if (!mime || !mime->hasUrls())
        return out;
    for (const QUrl &u : mime->urls()) {
        if (u.isLocalFile())
            out << u;
    }
    return out;
}

void MainWindow::handleDroppedUrls(const QList<QUrl> &urls)
{
    QStringList files;
    QString folder;
    for (const QUrl &u : urls) {
        const QFileInfo fi(u.toLocalFile());
        if (fi.isDir() && folder.isEmpty())
            folder = fi.absoluteFilePath();
        else if (fi.isFile())
            files << fi.absoluteFilePath();
    }
    if (!folder.isEmpty())
        openBatchDialog(folder);
    else if (files.size() == 1)
        openFile(files.front());
    else if (files.size() > 1)
        openBatchDialog(QString(), files);
}

void MainWindow::dragEnterEvent(QDragEnterEvent *event)
{
    if (!localFileUrls(event->mimeData()).isEmpty())
        event->acceptProposedAction();
}

void MainWindow::dragMoveEvent(QDragMoveEvent *event)
{
    if (!localFileUrls(event->mimeData()).isEmpty())
        event->acceptProposedAction();
}

void MainWindow::dropEvent(QDropEvent *event)
{
    const QList<QUrl> urls = localFileUrls(event->mimeData());
    if (urls.isEmpty())
        return;
    event->acceptProposedAction();
    // not inside the drop handler: a message box there would block the drag source on some platforms
    QTimer::singleShot(0, this, [this, urls] { handleDroppedUrls(urls); });
}

bool MainWindow::eventFilter(QObject *watched, QEvent *event)
{
    if (watched == m_input->viewport()) {
        switch (event->type()) {
        case QEvent::DragEnter:
        case QEvent::DragMove: {
            auto *e = static_cast<QDragMoveEvent *>(event);
            if (!localFileUrls(e->mimeData()).isEmpty()) {
                e->acceptProposedAction();
                return true;
            }
            break;
        }
        case QEvent::Drop: {
            auto *e = static_cast<QDropEvent *>(event);
            if (!localFileUrls(e->mimeData()).isEmpty()) {
                dropEvent(e);
                return true;
            }
            break;
        }
        default:
            break;
        }
    }
    return QMainWindow::eventFilter(watched, event);
}

} // namespace uzt
