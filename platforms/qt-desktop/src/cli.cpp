#include "cli.hpp"

#include "textfile.hpp"
#include "uztranslit.hpp"

#include <QByteArray>
#include <QFile>
#include <QFileInfo>
#include <QString>

#include <cstdio>
#include <cstring>
#include <exception>
#include <optional>

#ifdef Q_OS_WIN
#  include <fcntl.h>
#  include <io.h>
#  include <windows.h>
#endif

namespace uzt {
namespace {

const char *const LONG_OPTIONS[] = {"help", "from", "to", "ascii", "output", "version"};

QString programName(const QStringList &)
{
    return QStringLiteral("uztranslit"); // also for UzTranslit.app/Contents/MacOS/UzTranslit and uztranslit.exe
}

void writeStream(FILE *stream, const QByteArray &bytes, const QString &text)
{
#ifdef Q_OS_WIN
    // a console needs UTF-16 (WriteConsoleW); pipes and files get the bytes unchanged
    HANDLE h = GetStdHandle(stream == stderr ? STD_ERROR_HANDLE : STD_OUTPUT_HANDLE);
    DWORD mode = 0;
    if (h && h != INVALID_HANDLE_VALUE && GetConsoleMode(h, &mode)) {
        const auto *data = reinterpret_cast<const wchar_t *>(text.utf16());
        qsizetype left = text.size();
        while (left > 0) {
            DWORD written = 0;
            const DWORD chunk = DWORD(qMin<qsizetype>(left, 16384));
            if (!WriteConsoleW(h, data, chunk, &written, nullptr) || written == 0)
                break;
            data += written;
            left -= written;
        }
        return;
    }
    _setmode(_fileno(stream), _O_BINARY);
#else
    Q_UNUSED(text);
#endif
    std::fwrite(bytes.constData(), 1, std::size_t(bytes.size()), stream);
    std::fflush(stream);
}

void printErr(const QString &text)
{
    writeStream(stderr, text.toUtf8(), text);
}

QString usage(const QString &prog)
{
    return QStringLiteral("usage: %1 [-h] [--from {auto,cyr,lat,new}] --to {cyr,lat,new} [--ascii] [-o OUTPUT] [file]\n")
        .arg(prog);
}

QString help(const QString &prog)
{
    return usage(prog) + QStringLiteral(
               "\n"
               "Uzbek script converter (cyr / lat / new)\n"
               "\n"
               "positional arguments:\n"
               "  file                  input file (UTF-8); stdin if omitted\n"
               "\n"
               "options:\n"
               "  -h, --help            show this help message and exit\n"
               "  --from {auto,cyr,lat,new}\n"
               "  --to {cyr,lat,new}\n"
               "  --ascii               use ' instead of ʻ/ʼ\n"
               "  -o OUTPUT, --output OUTPUT\n"
               "                        write result to file instead of stdout\n"
               "  --version             show the version and exit\n");
}

int usageError(const QString &prog, const QString &message)
{
    printErr(usage(prog) + QStringLiteral("%1: error: %2\n").arg(prog, message));
    return 2;
}

// argparse: an exact long option, else a unique prefix of one
std::optional<QString> matchLongOption(const QString &name, QStringList *ambiguous)
{
    QStringList hits;
    for (const char *o : LONG_OPTIONS) {
        const QString opt = QString::fromLatin1(o);
        if (opt == name)
            return opt;
        if (!name.isEmpty() && opt.startsWith(name))
            hits << opt;
    }
    if (hits.size() == 1)
        return hits.front();
    if (ambiguous)
        *ambiguous = hits;
    return std::nullopt;
}

bool readAllStdin(QByteArray *out)
{
#ifdef Q_OS_WIN
    _setmode(_fileno(stdin), _O_BINARY);
#endif
    QByteArray data;
    char buf[65536];
    for (;;) {
        const std::size_t got = std::fread(buf, 1, sizeof buf, stdin);
        if (got > 0)
            data.append(buf, qsizetype(got));
        if (got < sizeof buf) {
            if (std::ferror(stdin))
                return false;
            break;
        }
    }
    *out = data;
    return true;
}

} // namespace

bool isCliInvocation(int argc, char **argv)
{
    for (int i = 1; i < argc; ++i) {
        const char *a = argv[i];
        if (std::strcmp(a, "--") == 0)
            break;
        if (std::strcmp(a, "-h") == 0 || std::strncmp(a, "-o", 2) == 0)
            return true;
        if (std::strncmp(a, "--", 2) == 0) {
            QString name = QString::fromLocal8Bit(a + 2);
            name = name.section(u'=', 0, 0);
            if (name.isEmpty())
                continue;
            for (const char *o : LONG_OPTIONS) {
                if (QString::fromLatin1(o).startsWith(name))
                    return true;
            }
        }
    }
    return false;
}

int runCli(const QStringList &arguments)
{
    using uztranslit::Script;
    const QString prog = programName(arguments);
    QString from = QStringLiteral("auto");
    std::optional<QString> to;
    std::optional<QString> output;
    std::optional<QString> file;
    bool ascii = false;
    QStringList unrecognized;
    bool onlyPositional = false;

    const auto checkChoice = [&](const QString &option, const QString &value, const QStringList &choices) -> bool {
        if (choices.contains(value))
            return true;
        QStringList quoted;
        for (const QString &c : choices)
            quoted << QStringLiteral("'%1'").arg(c);
        usageError(prog, QStringLiteral("argument %1: invalid choice: '%2' (choose from %3)")
                             .arg(option, value, quoted.join(QStringLiteral(", "))));
        return false;
    };

    for (qsizetype i = 1; i < arguments.size(); ++i) {
        const QString &a = arguments[i];
        if (!onlyPositional && a == u"--") {
            onlyPositional = true;
            continue;
        }
        if (!onlyPositional && a.startsWith(u"--")) {
            const qsizetype eq = a.indexOf(u'=');
            const QString name = a.mid(2, eq < 0 ? -1 : eq - 2);
            QStringList ambiguous;
            const std::optional<QString> opt = matchLongOption(name, &ambiguous);
            if (!opt) {
                if (ambiguous.size() > 1) {
                    QStringList dashed;
                    for (const QString &h : ambiguous)
                        dashed << QStringLiteral("--") + h;
                    return usageError(prog, QStringLiteral("ambiguous option: --%1 could match %2")
                                                .arg(name, dashed.join(QStringLiteral(", "))));
                }
                unrecognized << a;
                continue;
            }
            const bool takesValue = *opt == u"from" || *opt == u"to" || *opt == u"output";
            if (!takesValue) {
                if (eq >= 0)
                    return usageError(prog, QStringLiteral("argument --%1: ignored explicit argument '%2'")
                                                .arg(*opt, a.mid(eq + 1)));
                if (*opt == u"help") {
                    writeStream(stdout, help(prog).toUtf8(), help(prog));
                    return 0;
                }
                if (*opt == u"version") {
                    const QString v = QStringLiteral("%1 %2\n").arg(prog, QString::fromLatin1(uztranslit::VERSION));
                    writeStream(stdout, v.toUtf8(), v);
                    return 0;
                }
                ascii = true;
                continue;
            }
            QString value;
            if (eq >= 0) {
                value = a.mid(eq + 1);
            } else if (i + 1 < arguments.size() && !(arguments[i + 1].startsWith(u'-') && arguments[i + 1].size() > 1)) {
                value = arguments[++i];
            } else {
                return usageError(prog, QStringLiteral("argument %1: expected one argument")
                                            .arg(*opt == u"output" ? QStringLiteral("-o/--output")
                                                                   : QStringLiteral("--") + *opt));
            }
            if (*opt == u"from") {
                if (!checkChoice(QStringLiteral("--from"), value, {QStringLiteral("auto"), QStringLiteral("cyr"),
                                                                    QStringLiteral("lat"), QStringLiteral("new")}))
                    return 2;
                from = value;
            } else if (*opt == u"to") {
                if (!checkChoice(QStringLiteral("--to"), value,
                                 {QStringLiteral("cyr"), QStringLiteral("lat"), QStringLiteral("new")}))
                    return 2;
                to = value;
            } else {
                output = value;
            }
            continue;
        }
        if (!onlyPositional && a == u"-h") {
            writeStream(stdout, help(prog).toUtf8(), help(prog));
            return 0;
        }
        if (!onlyPositional && a.startsWith(u"-o")) {
            if (a.size() > 2) {
                output = a.mid(2);
            } else if (i + 1 < arguments.size() && !(arguments[i + 1].startsWith(u'-') && arguments[i + 1].size() > 1)) {
                output = arguments[++i];
            } else {
                return usageError(prog, QStringLiteral("argument -o/--output: expected one argument"));
            }
            continue;
        }
        if (!onlyPositional && a.startsWith(u'-') && a.size() > 1) {
            unrecognized << a;
            continue;
        }
        if (!file)
            file = a;
        else
            unrecognized << a;
    }
    if (!to)
        return usageError(prog, QStringLiteral("the following arguments are required: --to"));
    if (!unrecognized.isEmpty())
        return usageError(prog, QStringLiteral("unrecognized arguments: %1").arg(unrecognized.join(u' ')));

    // input: the file, or stdin ("-" too)
    QByteArray bytes;
    const bool fromStdin = !file || *file == u"-";
    const QString inputName = fromStdin ? QStringLiteral("<stdin>") : *file;
    if (fromStdin) {
        if (!readAllStdin(&bytes)) {
            printErr(QStringLiteral("%1: error: cannot read standard input\n").arg(prog));
            return 1;
        }
    } else {
        QFile f(*file);
        if (!f.open(QIODevice::ReadOnly)) {
            printErr(QStringLiteral("%1: error: %2: %3\n").arg(prog, *file, f.errorString()));
            return 1;
        }
        bytes = f.readAll();
    }
    TextFile input;
    QString decodeError;
    if (!TextFiles::decode(bytes, &input, &decodeError)) {
        printErr(QStringLiteral("%1: error: %2: %3\n").arg(prog, inputName, decodeError));
        return 1;
    }

    const uztranslit::Options options = ascii ? uztranslit::Options::ascii() : uztranslit::Options();
    TextFile result = input; // same encoding, byte-order mark kept
    try {
        result.text = uztranslit::convert(input.text, from, *to, options);
    } catch (const std::exception &e) {
        printErr(QStringLiteral("%1: error: %2\n").arg(prog, QString::fromUtf8(e.what())));
        return 1;
    }

    if (output) {
        QString writeError;
        if (!TextFiles::write(*output, result, &writeError)) {
            printErr(QStringLiteral("%1: error: %2: %3\n").arg(prog, *output, writeError));
            return 1;
        }
        return 0;
    }
    writeStream(stdout, TextFiles::encode(result), result.text);
    return 0;
}

} // namespace uzt
