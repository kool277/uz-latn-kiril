#include "textfile.hpp"

#include <QFile>
#include <QFileInfo>
#include <QSaveFile>
#include <QStringDecoder>
#include <QStringEncoder>

namespace uzt {

namespace {

QStringConverter::Encoding converterEncoding(TextEncoding e)
{
    switch (e) {
    case TextEncoding::Utf16LE: return QStringConverter::Utf16LE;
    case TextEncoding::Utf16BE: return QStringConverter::Utf16BE;
    case TextEncoding::Utf8: break;
    }
    return QStringConverter::Utf8;
}

} // namespace

bool TextFiles::decode(const QByteArray &bytes, TextFile *out, QString *error)
{
    TextFile f;
    qsizetype skip = 0;
    const auto at = [&bytes](qsizetype i) { return i < bytes.size() ? quint8(bytes[i]) : 0x100; };
    if (at(0) == 0xEF && at(1) == 0xBB && at(2) == 0xBF) {
        f.encoding = TextEncoding::Utf8;
        f.bom = true;
        skip = 3;
    } else if (at(0) == 0xFF && at(1) == 0xFE) {
        f.encoding = TextEncoding::Utf16LE;
        f.bom = true;
        skip = 2;
    } else if (at(0) == 0xFE && at(1) == 0xFF) {
        f.encoding = TextEncoding::Utf16BE;
        f.bom = true;
        skip = 2;
    }
    const QByteArrayView body = QByteArrayView(bytes).sliced(skip);
    if (f.encoding != TextEncoding::Utf8 && body.size() % 2 != 0) {
        if (error)
            *error = tr("The file is not valid UTF-16 text.");
        return false;
    }
    // ConvertInitialBom: a second U+FEFF after the byte-order mark is text and must stay
    QStringDecoder decoder(converterEncoding(f.encoding),
                           QStringConverter::Flag::Stateless | QStringConverter::Flag::ConvertInitialBom);
    f.text = decoder.decode(body);
    if (decoder.hasError()) {
        if (error)
            *error = f.encoding == TextEncoding::Utf8 ? tr("The file is not UTF-8 text (only UTF-8 and UTF-16 are supported).")
                                                      : tr("The file is not valid UTF-16 text.");
        return false;
    }
    if (out)
        *out = std::move(f);
    return true;
}

QByteArray TextFiles::encode(const TextFile &file)
{
    QStringEncoder encoder(converterEncoding(file.encoding), QStringConverter::Flag::Stateless);
    QByteArray body = encoder.encode(file.text);
    if (!file.bom)
        return body;
    QByteArray bom;
    switch (file.encoding) {
    case TextEncoding::Utf8: bom = QByteArray("\xEF\xBB\xBF", 3); break;
    case TextEncoding::Utf16LE: bom = QByteArray("\xFF\xFE", 2); break;
    case TextEncoding::Utf16BE: bom = QByteArray("\xFE\xFF", 2); break;
    }
    return bom + body;
}

bool TextFiles::read(const QString &path, TextFile *out, QString *error)
{
    QFile f(path);
    if (!f.open(QIODevice::ReadOnly)) {
        if (error)
            *error = f.errorString();
        return false;
    }
    if (f.size() > MaxFileSize) {
        if (error)
            *error = tr("The file is too large (more than %1 MB).").arg(MaxFileSize >> 20);
        return false;
    }
    const QByteArray bytes = f.readAll();
    if (f.error() != QFileDevice::NoError) {
        if (error)
            *error = f.errorString();
        return false;
    }
    return decode(bytes, out, error);
}

bool TextFiles::write(const QString &path, const TextFile &file, QString *error)
{
    QSaveFile f(path);
    if (!f.open(QIODevice::WriteOnly)) {
        if (error)
            *error = f.errorString();
        return false;
    }
    const QByteArray bytes = encode(file);
    if (f.write(bytes) != bytes.size()) {
        if (error)
            *error = f.errorString();
        f.cancelWriting();
        return false;
    }
    if (!f.commit()) {
        if (error)
            *error = f.errorString();
        return false;
    }
    return true;
}

} // namespace uzt
