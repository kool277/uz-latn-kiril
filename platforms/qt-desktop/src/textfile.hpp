// Text files: UTF-8 (with or without a byte-order mark) and UTF-16 with a byte-order mark. Anything else is
// refused instead of being decoded with replacement characters, so no byte of the user's file is lost.
#pragma once

#include <QByteArray>
#include <QCoreApplication>
#include <QString>

namespace uzt {

enum class TextEncoding { Utf8, Utf16LE, Utf16BE };

struct TextFile
{
    QString text;                               // without the byte-order mark
    TextEncoding encoding = TextEncoding::Utf8; // written back the same way
    bool bom = false;                           // the file started with a byte-order mark: keep it
};

class TextFiles
{
    Q_DECLARE_TR_FUNCTIONS(TextFiles)

public:
    static constexpr qint64 MaxFileSize = qint64(512) << 20;

    static bool decode(const QByteArray &bytes, TextFile *out, QString *error = nullptr);
    static QByteArray encode(const TextFile &file);
    static bool read(const QString &path, TextFile *out, QString *error = nullptr);
    // writes atomically (QSaveFile): a failed write never leaves a half-written file behind
    static bool write(const QString &path, const TextFile &file, QString *error = nullptr);
};

} // namespace uzt
