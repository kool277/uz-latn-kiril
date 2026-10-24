// Batch conversion dialog: a folder (or dropped files) → an output folder, in a worker thread.
#pragma once

#include "batch.hpp"
#include "uztranslit.hpp"

#include <QDialog>
#include <QPointer>
#include <QStringList>

class QCheckBox;
class QComboBox;
class QLabel;
class QLineEdit;
class QPlainTextEdit;
class QProgressBar;
class QPushButton;
class QThread;

namespace uzt {

class BatchDialog : public QDialog
{
    Q_OBJECT

public:
    BatchDialog(uztranslit::Script from, uztranslit::Script to, const uztranslit::Options &options,
                QWidget *parent = nullptr);
    ~BatchDialog() override;

    void setSourceFolder(const QString &dir);
    void setSourceFiles(const QStringList &files);
    void setOutputFolder(const QString &dir);
    QString outputFolder() const;
    void setRecursive(bool on);
    void setDirection(uztranslit::Script from, uztranslit::Script to);
    void setOptions(const uztranslit::Options &options) { m_options = options; }

    bool start(); // validates the input and starts; false (with the reason shown in the dialog) otherwise
    void cancel();
    bool isRunning() const { return m_thread != nullptr; }
    int convertedCount() const { return m_converted; }
    int unchangedCount() const { return m_unchanged; }
    int failedCount() const { return m_failed; }
    QString logText() const;
    QString statusText() const;

signals:
    void batchFinished(int converted, int unchanged, int failed, bool cancelled);

protected:
    void changeEvent(QEvent *event) override;
    void closeEvent(QCloseEvent *event) override;
    void reject() override;
    void dragEnterEvent(QDragEnterEvent *event) override;
    void dropEvent(QDropEvent *event) override;

private:
    void retranslateUi();
    void updateDefaultOutput();
    void setRunning(bool running);
    void stopThread();
    void onItemFinished(int index, int status, const QString &message, int from);
    void onFinished(int converted, int unchanged, int failed, bool cancelled);
    QStringList selectedSuffixes() const;
    uztranslit::Script fromScript() const;
    uztranslit::Script toScript() const;

    uztranslit::Options m_options;
    QStringList m_files;      // dropped files (instead of a folder)
    bool m_outputEdited = false;
    QList<BatchItem> m_items;
    QThread *m_thread = nullptr;
    QPointer<BatchJob> m_job;
    int m_converted = 0;
    int m_unchanged = 0;
    int m_failed = 0;

    QLabel *m_sourceLabel = nullptr;
    QLineEdit *m_sourceEdit = nullptr;
    QPushButton *m_sourceBrowse = nullptr;
    QLabel *m_outputLabel = nullptr;
    QLineEdit *m_outputEdit = nullptr;
    QPushButton *m_outputBrowse = nullptr;
    QCheckBox *m_recursive = nullptr;
    QLabel *m_typesLabel = nullptr;
    QList<QCheckBox *> m_types;
    QLabel *m_directionLabel = nullptr;
    QComboBox *m_fromCombo = nullptr;
    QComboBox *m_toCombo = nullptr;
    QProgressBar *m_progress = nullptr;
    QPlainTextEdit *m_log = nullptr;
    QLabel *m_status = nullptr;
    QPushButton *m_startButton = nullptr;
    QPushButton *m_cancelButton = nullptr;
    QPushButton *m_closeButton = nullptr;
};

} // namespace uzt
