package uz.jaybi.uztranslit

import android.content.ClipData
import android.content.ClipboardManager
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import uz.jaybi.uztranslit.model.ClipboardResult
import uz.jaybi.uztranslit.model.convertClipboard
import uz.jaybi.uztranslit.ui.MAX_TRANSFER_CHARS
import uz.jaybi.uztranslit.ui.readClipboardText
import uz.jaybi.uztranslit.ui.systemConfirmsCopy
import uz.jaybi.uztranslit.ui.toast

/**
 * Started by the Quick Settings tile. Since Android 10 only the app with window focus (or the default keyboard)
 * may read the clipboard, so this invisible, translucent activity waits for window focus, converts the
 * clipboard text to the user's target alphabet, writes it back and finishes.
 */
class ClipboardActivity : ComponentActivity() {
    private var started = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // never stay around invisibly if focus does not come (screen turned off, another window on top …)
        window.decorView.postDelayed({ if (!started) finish() }, FOCUS_TIMEOUT_MS)
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (!hasFocus || started) return
        started = true
        val text = readClipboardText(this)
        lifecycleScope.launch {
            val settings = settingsRepository.settings.first()
            val result = withContext(Dispatchers.Default) {
                if (text != null && text.length > MAX_TRANSFER_CHARS) null else convertClipboard(text, settings)
            }
            when (result) {
                null -> toast(this@ClipboardActivity, getString(R.string.text_too_large))
                ClipboardResult.Empty -> toast(this@ClipboardActivity, getString(R.string.clipboard_empty))
                is ClipboardResult.AlreadyInTarget ->
                    toast(this@ClipboardActivity, getString(R.string.clipboard_same, getString(result.script.nameRes())))
                is ClipboardResult.Converted -> {
                    val clipboard = getSystemService(ClipboardManager::class.java)
                    val written = clipboard != null && try {
                        clipboard.setPrimaryClip(ClipData.newPlainText(getString(R.string.app_name), result.text))
                        true
                    } catch (_: RuntimeException) {
                        false
                    }
                    when {
                        !written -> toast(this@ClipboardActivity, getString(R.string.text_too_large))
                        !systemConfirmsCopy -> toast(
                            this@ClipboardActivity,
                            getString(R.string.clipboard_done, getString(result.from.nameRes()), getString(result.to.nameRes())),
                        )
                    }
                }
            }
            finish()
        }
    }

    private companion object {
        const val FOCUS_TIMEOUT_MS = 3000L
    }
}
