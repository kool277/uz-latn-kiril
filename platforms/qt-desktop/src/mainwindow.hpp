// Main window: two editors side by side with live conversion, direction controls, file open/save, drag and
// drop, the batch dialog and the system tray with "Convert clipboard to …" actions.
#pragma once

#include "documents.hpp"
#include "settings.hpp"
#include "textfile.hpp"
#include "uztranslit.hpp"

#include <QMainWindow>
#include <QPointer>
#include <QSystemTrayIcon>
#include <QTimer>
#include <QUrl>

class QAction;
class QActionGroup;
class QButtonGroup;
class QLabel;
class QMenu;
class QMimeData;
class QPlainTextEdit;
class QPushButton;
class QSplitter;

namespace uzt {

class BatchDialog;

class MainWindow : public QMainWindow
{
    Q_OBJECT

public:
    explicit MainWindow(QWidget *parent = nullptr);
    ~MainWindow() override;

    bool openFile(const QString &path);   // loads a text file into the input editor (errors in a message box)
    bool saveResult(const QString &path); // the result, in the encoding (and with the byte-order mark) of the input
    void setInputText(const QString &text);
    // The exact input: the opened (or set) text while the editor is unmodified — the editor itself normalises
    // line ends — otherwise the editor's text with its no-break spaces and the input's line-end style.
    QString inputText() const;
    QString outputText() const { return m_result; } // the exact result (the output editor only displays it)
    QString displayedOutput() const;
    void setSource(uztranslit::Script script);
    void setTarget(uztranslit::Script script);
    uztranslit::Script source() const { return m_settings.source; }
    uztranslit::Script target() const { return m_settings.target; }
    QString detectedText() const;
    DocumentFormat documentFormat() const { return m_format; }
    const AppSettings &settings() const { return m_settings; }
    void setAsciiApostrophe(bool on);

    void convertNow(); // runs a pending (debounced) conversion right away
    void swapDirection();
    void copyResult();
    void clearInput();
    bool convertClipboard(uztranslit::Script target);
    QAction *clipboardAction(uztranslit::Script target) const;
    BatchDialog *openBatchDialog(const QString &folder = QString(), const QStringList &files = QStringList());
    void handleDroppedUrls(const QList<QUrl> &urls);
    void setLanguage(const QString &id);
    QSystemTrayIcon *trayIcon() const { return m_tray; }
    QString swapButtonText() const;

protected:
    void changeEvent(QEvent *event) override;
    void closeEvent(QCloseEvent *event) override;
    void dragEnterEvent(QDragEnterEvent *event) override;
    void dragMoveEvent(QDragMoveEvent *event) override;
    void dropEvent(QDropEvent *event) override;
    bool eventFilter(QObject *watched, QEvent *event) override;

private:
    void buildUi();
    void buildMenus();
    void buildTray();
    void retranslateUi();
    void syncButtons();
    void optionsChanged();
    void scheduleConvert();
    void updateDetected();
    void updateStats();
    void updateTitle();
    void showStatus(const QString &text);
    void notify(const QString &text);
    void onOpen();
    void onSaveAs();
    void onAbout();
    void onTrayActivated(QSystemTrayIcon::ActivationReason reason);
    void replaceInput(const QString &text);
    QString editorText() const;
    QString formatName(DocumentFormat format) const;
    static QList<QUrl> localFileUrls(const QMimeData *mime);

    AppSettings m_settings;
    DocumentFormat m_format = DocumentFormat::PlainText; // of the opened file; plain text for typed text
    TextFile m_fileFormat;                               // encoding and byte-order mark of the opened file
    QString m_currentFile;
    QString m_loadedText; // the exact text behind the editor while it is unmodified
    QString m_lineEnding = QStringLiteral("\n");
    QString m_result;
    uztranslit::Script m_detected = uztranslit::Script::Lat;
    bool m_trayHintShown = false;
    QTimer m_convertTimer;

    QLabel *m_fromLabel = nullptr;
    QLabel *m_toLabel = nullptr;
    QLabel *m_detectedLabel = nullptr;
    QLabel *m_inputLabel = nullptr;
    QLabel *m_outputLabel = nullptr;
    QLabel *m_statsLabel = nullptr;
    QButtonGroup *m_sourceGroup = nullptr;
    QButtonGroup *m_targetGroup = nullptr;
    QPushButton *m_sourceButtons[4] = {};
    QPushButton *m_targetButtons[3] = {};
    QPushButton *m_swapButton = nullptr;
    QPushButton *m_openButton = nullptr;
    QPushButton *m_pasteButton = nullptr;
    QPushButton *m_clearButton = nullptr;
    QPushButton *m_copyButton = nullptr;
    QPushButton *m_saveButton = nullptr;
    QPlainTextEdit *m_input = nullptr;
    QPlainTextEdit *m_output = nullptr;
    QSplitter *m_splitter = nullptr;

    QMenu *m_fileMenu = nullptr;
    QMenu *m_editMenu = nullptr;
    QMenu *m_clipboardMenu = nullptr;
    QMenu *m_optionsMenu = nullptr;
    QMenu *m_languageMenu = nullptr;
    QMenu *m_helpMenu = nullptr;
    QAction *m_actOpen = nullptr;
    QAction *m_actSave = nullptr;
    QAction *m_actBatch = nullptr;
    QAction *m_actQuit = nullptr;
    QAction *m_actCopy = nullptr;
    QAction *m_actPaste = nullptr;
    QAction *m_actClear = nullptr;
    QAction *m_actSwap = nullptr;
    QAction *m_actClipboard[3] = {};
    QAction *m_actAscii = nullptr;
    QAction *m_actSkipUrls = nullptr;
    QAction *m_actDictionary = nullptr;
    QAction *m_actDropHard = nullptr;
    QAction *m_actTsFinal = nullptr;
    QAction *m_actKeepInTray = nullptr;
    QActionGroup *m_languageGroup = nullptr;
    QAction *m_actLanguage[3] = {};
    QAction *m_actAbout = nullptr;
    QAction *m_actAboutQt = nullptr;
    QAction *m_actShow = nullptr;

    QSystemTrayIcon *m_tray = nullptr;
    QMenu *m_trayMenu = nullptr;
    QPointer<BatchDialog> m_batch;
};

} // namespace uzt
