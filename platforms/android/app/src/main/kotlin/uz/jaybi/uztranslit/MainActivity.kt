package uz.jaybi.uztranslit

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.webkit.MimeTypeMap
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContract
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.viewModels
import androidx.annotation.StringRes
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.core.content.IntentCompat
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import uz.jaybi.uztranslit.model.TEXT_FILE_MIME_TYPES
import uz.jaybi.uztranslit.ui.ConverterScreen
import uz.jaybi.uztranslit.ui.ConverterViewModel
import uz.jaybi.uztranslit.ui.FileScreen
import uz.jaybi.uztranslit.ui.FileState
import uz.jaybi.uztranslit.ui.SettingsScreen
import uz.jaybi.uztranslit.ui.theme.UzTranslitTheme
import uz.jaybi.uztranslit.ui.toast

/**
 * The launcher activity, and the share target: shared text opens in the editor, a shared .txt/.md/.srt/.csv file
 * opens the file screen (and the activity closes again after saving, back in the app that shared it).
 */
class MainActivity : ComponentActivity() {
    private val viewModel: ConverterViewModel by viewModels { ConverterViewModel.Factory }

    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        if (savedInstanceState == null) handleShare(intent)
        setContent {
            UzTranslitTheme {
                val file by viewModel.file.collectAsStateWithLifecycle()
                var showSettings by rememberSaveable { mutableStateOf(false) }
                val openDocument = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
                    if (uri != null) viewModel.openFile(uri.toString(), null)
                }
                val createDocument = rememberLauncherForActivityResult(CreateTextDocument()) { uri ->
                    if (uri != null) viewModel.saveFile(uri.toString())
                }
                val current = file
                when {
                    current != null -> {
                        val close = {
                            viewModel.closeFile()
                            if (isFileShare(intent)) finish()
                        }
                        BackHandler(onBack = close)
                        FileScreen(
                            file = current,
                            onTarget = viewModel::setFileTarget,
                            onSave = { launchOrToast(R.string.file_error_save) { createDocument.launch(current.outputName to mimeTypeFor(current)) } },
                            onClose = close,
                        )
                    }
                    showSettings -> {
                        BackHandler { showSettings = false }
                        SettingsScreen(viewModel, onBack = { showSettings = false })
                    }
                    else -> ConverterScreen(
                        viewModel,
                        onOpenSettings = { showSettings = true },
                        onOpenFile = { launchOrToast(R.string.file_error_read) { openDocument.launch(OPEN_MIME_TYPES) } },
                    )
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleShare(intent)
    }

    /** The system file picker is missing on a few devices (some TV and Go builds). */
    private fun launchOrToast(@StringRes error: Int, launch: () -> Unit) {
        try {
            launch()
        } catch (_: ActivityNotFoundException) {
            toast(this, getString(error))
        }
    }

    private fun handleShare(intent: Intent) {
        if (intent.action != Intent.ACTION_SEND) return
        val stream = IntentCompat.getParcelableExtra(intent, Intent.EXTRA_STREAM, Uri::class.java)
        if (stream != null) {
            viewModel.openFile(stream.toString(), intent.type)
        } else {
            intent.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString()?.let(viewModel::onInputChange)
        }
    }

    private companion object {
        /** What "Convert a file" offers in the system file picker; the extension is checked after picking. */
        val OPEN_MIME_TYPES = arrayOf("text/*", "application/csv", "application/x-subrip")

        fun isFileShare(intent: Intent?): Boolean = intent?.action == Intent.ACTION_SEND &&
            IntentCompat.getParcelableExtra(intent, Intent.EXTRA_STREAM, Uri::class.java) != null

        /** The MIME type for the new document: the one the system maps the extension to, so no ".txt" is appended. */
        fun mimeTypeFor(file: FileState): String {
            val byExtension = file.extension?.let { MimeTypeMap.getSingleton().getMimeTypeFromExtension(it) }
            return byExtension ?: file.mimeType?.takeIf { it in TEXT_FILE_MIME_TYPES } ?: "text/plain"
        }
    }
}

/** ACTION_CREATE_DOCUMENT with a file name and a MIME type chosen per call (CreateDocument fixes the type). */
class CreateTextDocument : ActivityResultContract<Pair<String, String>, Uri?>() {
    override fun createIntent(context: Context, input: Pair<String, String>): Intent =
        Intent(Intent.ACTION_CREATE_DOCUMENT)
            .addCategory(Intent.CATEGORY_OPENABLE)
            .setType(input.second)
            .putExtra(Intent.EXTRA_TITLE, input.first)

    override fun parseResult(resultCode: Int, intent: Intent?): Uri? =
        if (resultCode == Activity.RESULT_OK) intent?.data else null
}
