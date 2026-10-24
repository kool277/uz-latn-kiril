#include "batch.hpp"

#include "documents.hpp"
#include "textfile.hpp"

#include <QDir>
#include <QDirIterator>
#include <QFileInfo>

#include <algorithm>

namespace uzt {

namespace {

QString canonicalOrAbsolute(const QString &path)
{
    const QFileInfo fi(path);
    const QString c = fi.canonicalFilePath();
    return c.isEmpty() ? QDir::cleanPath(fi.absoluteFilePath()) : c;
}

bool isInside(const QString &path, const QString &dir)
{
    if (dir.isEmpty())
        return false;
    const Qt::CaseSensitivity cs =
#if defined(Q_OS_WIN) || defined(Q_OS_MACOS)
        Qt::CaseInsensitive;
#else
        Qt::CaseSensitive;
#endif
    return path.compare(dir, cs) == 0 || path.startsWith(dir + u'/', cs);
}

} // namespace

QList<BatchItem> Batch::collectFolder(const QString &sourceDir, const QString &outputDir, bool recursive,
                                      const QStringList &suffixes)
{
    QList<BatchItem> items;
    const QString src = canonicalOrAbsolute(sourceDir);
    const QString out = canonicalOrAbsolute(outputDir);
    QStringList lowered;
    for (const QString &s : suffixes)
        lowered << s.toLower();
    QDirIterator it(src, QDir::Files | QDir::NoDotAndDotDot,
                    recursive ? QDirIterator::Subdirectories : QDirIterator::NoIteratorFlags);
    const QDir base(src);
    while (it.hasNext()) {
        const QString path = it.next();
        const QFileInfo fi = it.fileInfo();
        if (!lowered.contains(fi.suffix().toLower()))
            continue;
        const QString absolute = canonicalOrAbsolute(path);
        if (isInside(absolute, out)) // the output folder inside the source folder: never convert our own output
            continue;
        const QString rel = base.relativeFilePath(path);
        // dot files and dot folders (.git, .vscode ...) are hidden by convention; on Windows the iterator does not
        // treat them as hidden, so they are left out here on every system
        if (rel.startsWith(u'.') || rel.contains(QStringLiteral("/.")))
            continue;
        items.push_back({absolute, QDir::cleanPath(out + u'/' + rel), rel});
    }
    std::sort(items.begin(), items.end(), [](const BatchItem &a, const BatchItem &b) { return a.display < b.display; });
    return items;
}

QList<BatchItem> Batch::collectFiles(const QStringList &files, const QString &outputDir)
{
    QList<BatchItem> items;
    const QString out = canonicalOrAbsolute(outputDir);
    for (const QString &f : files) {
        const QFileInfo fi(f);
        if (!fi.isFile())
            continue;
        items.push_back({canonicalOrAbsolute(f), QDir::cleanPath(out + u'/' + fi.fileName()), fi.fileName()});
    }
    return items;
}

BatchItemResult Batch::convertFile(const BatchItem &item, uztranslit::Script from, uztranslit::Script to,
                                   const uztranslit::Options &options)
{
    BatchItemResult r;
    if (canonicalOrAbsolute(item.target) == canonicalOrAbsolute(item.source)) {
        r.message = tr("The converted file would replace the original; choose another output folder.");
        return r;
    }
    TextFile input;
    QString error;
    if (!TextFiles::read(item.source, &input, &error)) {
        r.message = error;
        return r;
    }
    DocumentResult doc;
    if (!Documents::convert(Documents::formatForFileName(item.source), input.text, from, to, options, &doc, &error)) {
        r.message = error;
        return r;
    }
    r.from = doc.from;
    r.message = doc.warning;
    const QFileInfo target(item.target);
    if (!QDir().mkpath(target.absolutePath())) {
        r.message = tr("Cannot create the folder %1.").arg(QDir::toNativeSeparators(target.absolutePath()));
        return r;
    }
    TextFile output = input; // same encoding, byte-order mark kept
    output.text = doc.text;
    if (!TextFiles::write(item.target, output, &error)) {
        r.message = error;
        return r;
    }
    r.status = doc.changed ? BatchStatus::Converted : BatchStatus::Unchanged;
    return r;
}

BatchJob::BatchJob(QList<BatchItem> items, uztranslit::Script from, uztranslit::Script to, uztranslit::Options options)
    : m_items(std::move(items)), m_from(from), m_to(to), m_options(std::move(options))
{
}

void BatchJob::run()
{
    int converted = 0;
    int unchanged = 0;
    int failed = 0;
    for (int i = 0; i < int(m_items.size()); ++i) {
        if (m_cancel.load()) {
            emit finished(converted, unchanged, failed, true);
            return;
        }
        const BatchItemResult r = Batch::convertFile(m_items[i], m_from, m_to, m_options);
        switch (r.status) {
        case BatchStatus::Converted: ++converted; break;
        case BatchStatus::Unchanged: ++unchanged; break;
        case BatchStatus::Failed: ++failed; break;
        }
        emit itemFinished(i, int(r.status), r.message, int(r.from));
    }
    emit finished(converted, unchanged, failed, false);
}

} // namespace uzt
