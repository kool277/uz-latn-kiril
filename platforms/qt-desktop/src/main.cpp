// uztranslit: the desktop app, and the command-line converter when started with converter flags.
// The command line is recognised on the raw argv before any application object exists, so the CLI runs on a
// QCoreApplication and never needs a display.
#include "cli.hpp"
#include "language.hpp"
#include "mainwindow.hpp"
#include "settings.hpp"

#include <QApplication>
#include <QCoreApplication>
#include <QFile>
#include <QFileInfo>
#include <QFileOpenEvent>
#include <QSettings>
#include <QTimer>

#ifdef Q_OS_WIN
#  include <cstdio>
#  include <io.h>
#  include <windows.h>
#endif

#ifndef UZT_VERSION
#  define UZT_VERSION "0.0.0"
#endif

namespace {

class FileOpenFilter : public QObject
{
public:
    explicit FileOpenFilter(uzt::MainWindow *window) : m_window(window) {}

protected:
    bool eventFilter(QObject *watched, QEvent *event) override
    {
        if (event->type() == QEvent::FileOpen) {
            const QString path = static_cast<QFileOpenEvent *>(event)->file();
            const QFileInfo fi(path);
            if (fi.isDir())
                m_window->openBatchDialog(fi.absoluteFilePath());
            else if (fi.isFile())
                m_window->openFile(fi.absoluteFilePath());
            return true;
        }
        return QObject::eventFilter(watched, event);
    }

private:
    uzt::MainWindow *m_window;
};

void setApplicationInfo()
{
    QCoreApplication::setOrganizationName(QStringLiteral("UzTranslit"));
    QCoreApplication::setOrganizationDomain(QStringLiteral("latin.jaybi.uz"));
    QCoreApplication::setApplicationName(QStringLiteral("UzTranslit"));
    QCoreApplication::setApplicationVersion(QStringLiteral(UZT_VERSION));
}

#ifdef Q_OS_WIN
// The Windows build is a GUI-subsystem program, so it starts without a console. Redirected streams (pipes, files)
// work as they are; a stream that is not redirected is connected to the console of the parent process (cmd.exe,
// PowerShell) when there is one.
void attachParentConsole()
{
    const bool needOut = _fileno(stdout) < 0 || GetStdHandle(STD_OUTPUT_HANDLE) == nullptr;
    const bool needErr = _fileno(stderr) < 0 || GetStdHandle(STD_ERROR_HANDLE) == nullptr;
    const bool needIn = _fileno(stdin) < 0 || GetStdHandle(STD_INPUT_HANDLE) == nullptr;
    if (!(needOut || needErr || needIn) || !AttachConsole(ATTACH_PARENT_PROCESS))
        return;
    FILE *f = nullptr;
    if (needOut && freopen_s(&f, "CONOUT$", "w", stdout) == 0)
        SetStdHandle(STD_OUTPUT_HANDLE, reinterpret_cast<HANDLE>(_get_osfhandle(_fileno(stdout))));
    if (needErr && freopen_s(&f, "CONOUT$", "w", stderr) == 0)
        SetStdHandle(STD_ERROR_HANDLE, reinterpret_cast<HANDLE>(_get_osfhandle(_fileno(stderr))));
    if (needIn && freopen_s(&f, "CONIN$", "r", stdin) == 0)
        SetStdHandle(STD_INPUT_HANDLE, reinterpret_cast<HANDLE>(_get_osfhandle(_fileno(stdin))));
}
#endif

} // namespace

int main(int argc, char *argv[])
{
    if (uzt::isCliInvocation(argc, argv)) {
#ifdef Q_OS_WIN
        attachParentConsole();
#endif
        QCoreApplication app(argc, argv);
        setApplicationInfo();
        return uzt::runCli(QCoreApplication::arguments());
    }

    QApplication app(argc, argv);
    setApplicationInfo();
    QGuiApplication::setDesktopFileName(QStringLiteral("uztranslit"));
    // the tray icon keeps the clipboard actions available; the window's close event decides when to quit
    QApplication::setQuitOnLastWindowClosed(false);
    // testing aid: settings in an INI file in this folder instead of the user's settings
    const QString settingsDir = qEnvironmentVariable("UZTRANSLIT_SETTINGS_DIR");
    if (!settingsDir.isEmpty()) {
        QSettings::setDefaultFormat(QSettings::IniFormat);
        QSettings::setPath(QSettings::IniFormat, QSettings::UserScope, settingsDir);
    }
    uzt::Language::apply(uzt::Language::resolve(uzt::AppSettings::load().language));

    uzt::MainWindow window;
    // macOS delivers "Open With" and files dropped on the Dock icon as QFileOpenEvent, not as arguments
    FileOpenFilter fileOpen(&window);
    app.installEventFilter(&fileOpen);
    window.show();

    // a file or a folder given on the command line ("Open with", drag onto the program icon)
    const QStringList args = QCoreApplication::arguments().mid(1);
    for (const QString &a : args) {
        const QFileInfo fi(a);
        if (fi.isDir()) {
            window.openBatchDialog(fi.absoluteFilePath());
            break;
        }
        if (fi.isFile()) {
            window.openFile(fi.absoluteFilePath());
            break;
        }
    }

    // Testing aids for the real binary (CI smoke test with QT_QPA_PLATFORM=offscreen):
    // UZTRANSLIT_QUIT_AFTER_MS=n quits after n ms; UZTRANSLIT_SMOKE_RESULT=path then writes the result there.
    bool ok = false;
    const int quitAfter = qEnvironmentVariableIntValue("UZTRANSLIT_QUIT_AFTER_MS", &ok);
    if (ok && quitAfter >= 0) {
        QTimer::singleShot(quitAfter, &app, [&window] {
            const QString path = qEnvironmentVariable("UZTRANSLIT_SMOKE_RESULT");
            if (!path.isEmpty()) {
                window.convertNow();
                QFile f(path);
                if (f.open(QIODevice::WriteOnly))
                    f.write(window.outputText().toUtf8());
            }
            QCoreApplication::quit();
        });
    }
    return app.exec();
}
