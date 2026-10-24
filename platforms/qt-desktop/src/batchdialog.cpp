#include "batchdialog.hpp"

#include "language.hpp"

#include <QCheckBox>
#include <QCloseEvent>
#include <QComboBox>
#include <QDir>
#include <QDragEnterEvent>
#include <QDropEvent>
#include <QFileDialog>
#include <QFileInfo>
#include <QGridLayout>
#include <QHBoxLayout>
#include <QLabel>
#include <QLineEdit>
#include <QMimeData>
#include <QPlainTextEdit>
#include <QProgressBar>
#include <QPushButton>
#include <QThread>
#include <QVBoxLayout>

#include "documents.hpp"

using uztranslit::Script;

namespace uzt {

namespace {

constexpr Script FROM_ORDER[] = {Script::Auto, Script::Cyr, Script::Lat, Script::New};
constexpr Script TO_ORDER[] = {Script::Cyr, Script::Lat, Script::New};

QString canonical(const QString &path)
{
    const QFileInfo fi(path);
    const QString c = fi.canonicalFilePath();
    return c.isEmpty() ? QDir::cleanPath(fi.absoluteFilePath()) : c;
}

} // namespace

BatchDialog::BatchDialog(Script from, Script to, const uztranslit::Options &options, QWidget *parent)
    : QDialog(parent), m_options(options)
{
    setObjectName(QStringLiteral("batchDialog"));
    setAcceptDrops(true);

    auto *grid = new QGridLayout;
    m_sourceLabel = new QLabel(this);
    m_sourceEdit = new QLineEdit(this);
    m_sourceEdit->setObjectName(QStringLiteral("sourceEdit"));
    m_sourceBrowse = new QPushButton(this);
    m_outputLabel = new QLabel(this);
    m_outputEdit = new QLineEdit(this);
    m_outputEdit->setObjectName(QStringLiteral("outputEdit"));
    m_outputBrowse = new QPushButton(this);
    m_sourceLabel->setBuddy(m_sourceEdit);
    m_outputLabel->setBuddy(m_outputEdit);
    grid->addWidget(m_sourceLabel, 0, 0);
    grid->addWidget(m_sourceEdit, 0, 1);
    grid->addWidget(m_sourceBrowse, 0, 2);
    grid->addWidget(m_outputLabel, 1, 0);
    grid->addWidget(m_outputEdit, 1, 1);
    grid->addWidget(m_outputBrowse, 1, 2);
    m_recursive = new QCheckBox(this);
    m_recursive->setChecked(true);
    grid->addWidget(m_recursive, 2, 1, 1, 2);
    m_typesLabel = new QLabel(this);
    auto *types = new QHBoxLayout;
    for (const QString &suffix : Documents::batchSuffixes()) {
        auto *box = new QCheckBox(u'.' + suffix, this);
        box->setChecked(true);
        box->setProperty("suffix", suffix);
        m_types << box;
        types->addWidget(box);
    }
    types->addStretch(1);
    grid->addWidget(m_typesLabel, 3, 0);
    grid->addLayout(types, 3, 1, 1, 2);
    m_directionLabel = new QLabel(this);
    m_fromCombo = new QComboBox(this);
    m_toCombo = new QComboBox(this);
    for (Script s : FROM_ORDER)
        m_fromCombo->addItem(QString(), int(s));
    for (Script s : TO_ORDER)
        m_toCombo->addItem(QString(), int(s));
    auto *direction = new QHBoxLayout;
    direction->addWidget(m_fromCombo);
    direction->addWidget(new QLabel(QStringLiteral("→"), this));
    direction->addWidget(m_toCombo);
    direction->addStretch(1);
    grid->addWidget(m_directionLabel, 4, 0);
    grid->addLayout(direction, 4, 1, 1, 2);
    grid->setColumnStretch(1, 1);

    m_progress = new QProgressBar(this);
    m_progress->setRange(0, 1);
    m_progress->setValue(0);
    m_log = new QPlainTextEdit(this);
    m_log->setReadOnly(true);
    m_log->setObjectName(QStringLiteral("log"));
    m_status = new QLabel(this);
    m_status->setWordWrap(true);
    m_status->setObjectName(QStringLiteral("status"));

    auto *buttons = new QHBoxLayout;
    m_startButton = new QPushButton(this);
    m_startButton->setDefault(true);
    m_cancelButton = new QPushButton(this);
    m_closeButton = new QPushButton(this);
    buttons->addStretch(1);
    buttons->addWidget(m_startButton);
    buttons->addWidget(m_cancelButton);
    buttons->addWidget(m_closeButton);

    auto *layout = new QVBoxLayout(this);
    layout->addLayout(grid);
    layout->addWidget(m_progress);
    layout->addWidget(m_log, 1);
    layout->addWidget(m_status);
    layout->addLayout(buttons);

    connect(m_sourceBrowse, &QPushButton::clicked, this, [this] {
        const QString dir = QFileDialog::getExistingDirectory(this, m_sourceLabel->text(), m_sourceEdit->text());
        if (!dir.isEmpty())
            setSourceFolder(dir);
    });
    connect(m_outputBrowse, &QPushButton::clicked, this, [this] {
        const QString dir = QFileDialog::getExistingDirectory(this, m_outputLabel->text(), m_outputEdit->text());
        if (!dir.isEmpty())
            setOutputFolder(dir);
    });
    connect(m_sourceEdit, &QLineEdit::textEdited, this, [this] {
        m_files.clear();
        updateDefaultOutput();
    });
    connect(m_outputEdit, &QLineEdit::textEdited, this, [this] { m_outputEdited = true; });
    connect(m_toCombo, &QComboBox::currentIndexChanged, this, [this] { updateDefaultOutput(); });
    connect(m_startButton, &QPushButton::clicked, this, [this] { start(); });
    connect(m_cancelButton, &QPushButton::clicked, this, &BatchDialog::cancel);
    connect(m_closeButton, &QPushButton::clicked, this, &QDialog::close);

    setDirection(from, to);
    retranslateUi();
    setRunning(false);
    resize(720, 540);
}

BatchDialog::~BatchDialog()
{
    if (m_job)
        m_job->cancel();
    stopThread();
}

void BatchDialog::retranslateUi()
{
    setWindowTitle(tr("Convert a folder"));
    m_sourceLabel->setText(tr("Source folder:"));
    m_outputLabel->setText(tr("Output folder:"));
    m_sourceBrowse->setText(tr("Browse…"));
    m_outputBrowse->setText(tr("Browse…"));
    m_recursive->setText(tr("Include subfolders"));
    m_typesLabel->setText(tr("File types:"));
    m_directionLabel->setText(tr("Direction:"));
    for (int k = 0; k < m_fromCombo->count(); ++k)
        m_fromCombo->setItemText(k, ScriptNames::button(Script(m_fromCombo->itemData(k).toInt())));
    for (int k = 0; k < m_toCombo->count(); ++k)
        m_toCombo->setItemText(k, ScriptNames::button(Script(m_toCombo->itemData(k).toInt())));
    m_startButton->setText(tr("Start"));
    m_cancelButton->setText(tr("Cancel"));
    m_closeButton->setText(tr("Close"));
    m_log->setPlaceholderText(tr("Converted copies go to the output folder; the original files are never changed. "
                                 "HTML and XML: only the text is converted; JSON: only string values; Markdown: "
                                 "code and links stay as they are."));
    if (!m_files.isEmpty())
        m_sourceEdit->setText(tr("%1 files").arg(m_files.size()));
}

void BatchDialog::changeEvent(QEvent *event)
{
    if (event->type() == QEvent::LanguageChange)
        retranslateUi();
    QDialog::changeEvent(event);
}

void BatchDialog::setSourceFolder(const QString &dir)
{
    m_files.clear();
    m_sourceEdit->setReadOnly(false);
    m_sourceEdit->setText(QDir::toNativeSeparators(QDir::cleanPath(dir)));
    m_recursive->setEnabled(true);
    for (QCheckBox *b : m_types)
        b->setEnabled(true);
    updateDefaultOutput();
}

void BatchDialog::setSourceFiles(const QStringList &files)
{
    m_files = files;
    m_sourceEdit->setReadOnly(true);
    m_sourceEdit->setText(tr("%1 files").arg(files.size()));
    m_recursive->setEnabled(false);
    for (QCheckBox *b : m_types)
        b->setEnabled(false);
    updateDefaultOutput();
}

void BatchDialog::setOutputFolder(const QString &dir)
{
    m_outputEdit->setText(QDir::toNativeSeparators(QDir::cleanPath(dir)));
    m_outputEdited = true;
}

QString BatchDialog::outputFolder() const
{
    return QDir::fromNativeSeparators(m_outputEdit->text().trimmed());
}

void BatchDialog::setRecursive(bool on)
{
    m_recursive->setChecked(on);
}

void BatchDialog::setDirection(Script from, Script to)
{
    if (isRunning())
        return;
    m_fromCombo->setCurrentIndex(qMax(0, m_fromCombo->findData(int(from))));
    m_toCombo->setCurrentIndex(qMax(0, m_toCombo->findData(int(to))));
}

Script BatchDialog::fromScript() const
{
    return Script(m_fromCombo->currentData().toInt());
}

Script BatchDialog::toScript() const
{
    return Script(m_toCombo->currentData().toInt());
}

void BatchDialog::updateDefaultOutput()
{
    if (m_outputEdited)
        return;
    const QString target = uztranslit::scriptId(toScript());
    QString out;
    if (!m_files.isEmpty()) {
        out = QFileInfo(m_files.front()).absoluteDir().filePath(QStringLiteral("uztranslit-") + target);
    } else {
        const QString src = QDir::cleanPath(QDir::fromNativeSeparators(m_sourceEdit->text().trimmed()));
        if (!src.isEmpty() && src != u"." && src != u"/")
            out = src + u'-' + target;
    }
    m_outputEdit->setText(QDir::toNativeSeparators(out));
}

QStringList BatchDialog::selectedSuffixes() const
{
    QStringList out;
    for (QCheckBox *b : m_types) {
        if (b->isChecked())
            out << b->property("suffix").toString();
    }
    if (out.contains(QStringLiteral("html")))
        out << QStringLiteral("htm");
    return out;
}

bool BatchDialog::start()
{
    if (isRunning())
        return false;
    m_status->clear();
    const QString out = outputFolder();
    if (out.isEmpty()) {
        m_status->setText(tr("Choose an output folder."));
        return false;
    }
    QList<BatchItem> items;
    if (!m_files.isEmpty()) {
        items = Batch::collectFiles(m_files, out);
    } else {
        const QString src = QDir::fromNativeSeparators(m_sourceEdit->text().trimmed());
        if (src.isEmpty() || !QFileInfo(src).isDir()) {
            m_status->setText(tr("Choose a source folder."));
            return false;
        }
        if (canonical(src) == canonical(out)) {
            m_status->setText(tr("The output folder must differ from the source folder."));
            return false;
        }
        const QStringList suffixes = selectedSuffixes();
        if (suffixes.isEmpty()) {
            m_status->setText(tr("Choose at least one file type."));
            return false;
        }
        items = Batch::collectFolder(src, out, m_recursive->isChecked(), suffixes);
    }
    if (items.isEmpty()) {
        m_status->setText(tr("There are no files to convert."));
        return false;
    }
    m_items = items;
    m_converted = m_unchanged = m_failed = 0;
    m_log->clear();
    m_progress->setRange(0, int(items.size()));
    m_progress->setValue(0);

    auto *job = new BatchJob(items, fromScript(), toScript(), m_options);
    m_job = job;
    m_thread = new QThread(this);
    job->moveToThread(m_thread);
    connect(m_thread, &QThread::started, job, &BatchJob::run);
    connect(job, &BatchJob::itemFinished, this, &BatchDialog::onItemFinished);
    connect(job, &BatchJob::finished, this, &BatchDialog::onFinished);
    connect(m_thread, &QThread::finished, job, &QObject::deleteLater);
    setRunning(true);
    m_status->setText(tr("Converting %1 files…").arg(items.size()));
    m_thread->start();
    return true;
}

void BatchDialog::cancel()
{
    if (m_job)
        m_job->cancel();
}

void BatchDialog::stopThread()
{
    if (!m_thread)
        return;
    m_thread->quit();
    m_thread->wait();
    delete m_thread;
    m_thread = nullptr;
}

void BatchDialog::setRunning(bool running)
{
    m_startButton->setEnabled(!running);
    m_cancelButton->setEnabled(running);
    m_sourceEdit->setEnabled(!running);
    m_sourceBrowse->setEnabled(!running);
    m_outputEdit->setEnabled(!running);
    m_outputBrowse->setEnabled(!running);
    m_fromCombo->setEnabled(!running);
    m_toCombo->setEnabled(!running);
    m_recursive->setEnabled(!running && m_files.isEmpty());
    for (QCheckBox *b : m_types)
        b->setEnabled(!running && m_files.isEmpty());
}

void BatchDialog::onItemFinished(int index, int status, const QString &message, int from)
{
    if (index < 0 || index >= m_items.size())
        return;
    const BatchItem &item = m_items[index];
    QString line;
    switch (BatchStatus(status)) {
    case BatchStatus::Converted:
        ++m_converted;
        line = tr("%1: converted (%2 → %3)")
                   .arg(item.display, ScriptNames::inSentence(Script(from)), ScriptNames::inSentence(toScript()));
        break;
    case BatchStatus::Unchanged:
        ++m_unchanged;
        line = tr("%1: unchanged (%2)").arg(item.display, ScriptNames::inSentence(Script(from)));
        break;
    case BatchStatus::Failed:
        ++m_failed;
        line = tr("%1: error: %2").arg(item.display, message);
        break;
    }
    if (BatchStatus(status) != BatchStatus::Failed && !message.isEmpty())
        line += QStringLiteral(" — ") + message;
    m_log->appendPlainText(line);
    m_progress->setValue(index + 1);
}

void BatchDialog::onFinished(int converted, int unchanged, int failed, bool cancelled)
{
    stopThread();
    setRunning(false);
    const QString summary = tr("Converted: %1 · unchanged: %2 · errors: %3").arg(converted).arg(unchanged).arg(failed);
    m_status->setText((cancelled ? tr("Cancelled.") : tr("Done.")) + u' ' + summary);
    emit batchFinished(converted, unchanged, failed, cancelled);
}

QString BatchDialog::logText() const
{
    return m_log->toPlainText();
}

QString BatchDialog::statusText() const
{
    return m_status->text();
}

void BatchDialog::closeEvent(QCloseEvent *event)
{
    if (m_job)
        m_job->cancel();
    stopThread();
    QDialog::closeEvent(event);
}

void BatchDialog::reject()
{
    if (m_job)
        m_job->cancel();
    stopThread();
    QDialog::reject();
}

void BatchDialog::dragEnterEvent(QDragEnterEvent *event)
{
    if (!isRunning() && event->mimeData()->hasUrls())
        event->acceptProposedAction();
}

void BatchDialog::dropEvent(QDropEvent *event)
{
    QStringList files;
    QString folder;
    for (const QUrl &u : event->mimeData()->urls()) {
        if (!u.isLocalFile())
            continue;
        const QFileInfo fi(u.toLocalFile());
        if (fi.isDir() && folder.isEmpty())
            folder = fi.absoluteFilePath();
        else if (fi.isFile())
            files << fi.absoluteFilePath();
    }
    if (!folder.isEmpty())
        setSourceFolder(folder);
    else if (!files.isEmpty())
        setSourceFiles(files);
    else
        return;
    event->acceptProposedAction();
}

} // namespace uzt
