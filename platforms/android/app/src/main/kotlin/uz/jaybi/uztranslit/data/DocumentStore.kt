package uz.jaybi.uztranslit.data

import android.content.ContentResolver
import android.provider.OpenableColumns
import androidx.core.net.toUri
import java.io.ByteArrayOutputStream
import java.io.FileNotFoundException
import java.io.IOException
import java.io.InputStream
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/** A file shared with the app or picked by the user. */
class SharedDocument(val name: String?, val mimeType: String?, val bytes: ByteArray)

/** The file is bigger than the limit the caller gave. */
class DocumentTooLargeException(val limit: Int) : IOException("larger than $limit bytes")

/** Reads shared files and writes converted ones (Storage Access Framework); URIs are passed as strings. */
interface DocumentStore {
    suspend fun read(uri: String, maxBytes: Int): SharedDocument

    /** Writes [bytes] to a document created with ACTION_CREATE_DOCUMENT; returns its display name if known. */
    suspend fun write(uri: String, bytes: ByteArray): String?
}

class ContentResolverDocumentStore(
    private val resolver: ContentResolver,
    private val io: CoroutineDispatcher = Dispatchers.IO,
) : DocumentStore {
    override suspend fun read(uri: String, maxBytes: Int): SharedDocument = withContext(io) {
        val u = uri.toUri()
        var name: String? = null
        var size: Long? = null
        try {
            resolver.query(u, arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE), null, null, null)?.use { c ->
                if (c.moveToFirst()) {
                    if (!c.isNull(0)) name = c.getString(0)
                    if (!c.isNull(1)) size = c.getLong(1)
                }
            }
        } catch (_: RuntimeException) {
            // some providers answer no metadata at all: the bytes are what matters
        }
        if ((size ?: 0L) > maxBytes) throw DocumentTooLargeException(maxBytes)
        val bytes = (resolver.openInputStream(u) ?: throw FileNotFoundException(uri)).use { it.readAtMost(maxBytes) }
        SharedDocument(name ?: u.lastPathSegment, resolver.getType(u), bytes)
    }

    override suspend fun write(uri: String, bytes: ByteArray): String? = withContext(io) {
        val u = uri.toUri()
        val stream = try {
            resolver.openOutputStream(u, "wt")
        } catch (_: FileNotFoundException) {
            resolver.openOutputStream(u, "w") // providers without truncate mode; the document is new anyway
        } ?: throw FileNotFoundException(uri)
        stream.use { it.write(bytes) }
        try {
            resolver.query(u, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c ->
                if (c.moveToFirst() && !c.isNull(0)) c.getString(0) else null
            }
        } catch (_: RuntimeException) {
            null
        }
    }

    private fun InputStream.readAtMost(limit: Int): ByteArray {
        val out = ByteArrayOutputStream()
        val buffer = ByteArray(64 * 1024)
        while (true) {
            val n = read(buffer)
            if (n < 0) break
            out.write(buffer, 0, n)
            if (out.size() > limit) throw DocumentTooLargeException(limit)
        }
        return out.toByteArray()
    }
}
