// Batch conversion of files: collecting the work, converting one file, and a job that runs in a worker thread.
#pragma once

#include "uztranslit.hpp"

#include <QCoreApplication>
#include <QList>
#include <QObject>
#include <QString>
#include <QStringList>

#include <atomic>

namespace uzt {

struct BatchItem
{
    QString source;  // absolute path of the input file
    QString target;  // absolute path of the converted file
    QString display; // path shown to the user (relative to the source folder)
};

enum class BatchStatus { Converted, Unchanged, Failed };

struct BatchItemResult
{
    BatchStatus status = BatchStatus::Failed;
    uztranslit::Script from = uztranslit::Script::Lat; // the source script used (detected for Auto)
    QString message;                                   // error, or a warning (fallback used)
};

class Batch
{
    Q_DECLARE_TR_FUNCTIONS(Batch)

public:
    // Files under sourceDir whose suffix is in `suffixes` (case-insensitive), mirrored under outputDir. Hidden files
    // and folders, symbolic links to folders and the output folder itself (when it lies inside the source) are skipped.
    static QList<BatchItem> collectFolder(const QString &sourceDir, const QString &outputDir, bool recursive,
                                          const QStringList &suffixes);
    // Individual files, written flat into outputDir.
    static QList<BatchItem> collectFiles(const QStringList &files, const QString &outputDir);
    // Reads, converts (format-aware, see documents.hpp) and writes one file. A file is never written over its source.
    static BatchItemResult convertFile(const BatchItem &item, uztranslit::Script from, uztranslit::Script to,
                                       const uztranslit::Options &options);
};

// Converts a list of files; move it to a QThread and invoke run(). cancel() may be called from any thread.
class BatchJob : public QObject
{
    Q_OBJECT

public:
    BatchJob(QList<BatchItem> items, uztranslit::Script from, uztranslit::Script to, uztranslit::Options options);

    void cancel() { m_cancel.store(true); }

public slots:
    void run();

signals:
    void itemFinished(int index, int status, const QString &message, int from);
    void finished(int converted, int unchanged, int failed, bool cancelled);

private:
    QList<BatchItem> m_items;
    uztranslit::Script m_from;
    uztranslit::Script m_to;
    uztranslit::Options m_options;
    std::atomic_bool m_cancel{false};
};

} // namespace uzt
