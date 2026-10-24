package uz.jaybi.uztranslit.ui

import android.content.ClipData
import android.content.ClipboardManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.widget.Toast
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.text.BasicText
import androidx.compose.foundation.text.TextAutoSize
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.sp
import uz.jaybi.uztranslit.MainActivity
import uz.jaybi.uztranslit.R
import uz.jaybi.uztranslit.model.TextStats

/** Texts longer than this are not put on the clipboard or into a share intent (the Binder limit is ~1 MB). */
const val MAX_TRANSFER_CHARS = 200_000

/**
 * A row of segmented buttons for alphabets. Labels shrink to fit narrow screens (four labels such as
 * "Lotin 1995" and "Новая латиница" on a 360 dp phone) instead of wrapping.
 */
@Composable
fun <T> ChoiceRow(
    options: List<T>,
    selected: T,
    label: @Composable (T) -> String,
    onSelect: (T) -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
) {
    SingleChoiceSegmentedButtonRow(modifier.fillMaxWidth()) {
        options.forEachIndexed { index, option ->
            SegmentedButton(
                selected = option == selected,
                onClick = { onSelect(option) },
                shape = SegmentedButtonDefaults.itemShape(index, options.size),
                enabled = enabled,
                icon = {},
                label = { FittingLabel(label(option)) },
            )
        }
    }
}

@Composable
private fun FittingLabel(text: String) {
    val style = MaterialTheme.typography.labelLarge
    BasicText(
        text = text,
        style = style.copy(color = LocalContentColor.current, textAlign = TextAlign.Center),
        maxLines = 1,
        autoSize = TextAutoSize.StepBased(minFontSize = 9.sp, maxFontSize = style.fontSize, stepSize = 0.5.sp),
    )
}

/** "12 belgi · 2 soʻz" */
@Composable
fun statsText(stats: TextStats): String = stringResource(
    R.string.stats,
    pluralStringResource(R.plurals.chars_count, stats.chars, stats.chars),
    pluralStringResource(R.plurals.words_count, stats.words, stats.words),
)

/** Android 13+ confirms clipboard writes itself; earlier versions get a toast. */
val systemConfirmsCopy: Boolean get() = Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU

/** Puts [text] on the clipboard; false when it is too long or the clipboard refused it. */
fun copyText(context: Context, text: String): Boolean {
    if (text.length > MAX_TRANSFER_CHARS) return false
    return try {
        val clipboard = context.getSystemService(ClipboardManager::class.java) ?: return false
        clipboard.setPrimaryClip(ClipData.newPlainText(context.getString(R.string.app_name), text))
        true
    } catch (_: RuntimeException) {
        false
    }
}

/** The clipboard's text (the app has window focus whenever the user taps a button). */
fun readClipboardText(context: Context): String? = try {
    val clip = context.getSystemService(ClipboardManager::class.java)?.primaryClip
    if (clip == null || clip.itemCount == 0) null else clip.getItemAt(0).coerceToText(context)?.toString()
} catch (_: RuntimeException) {
    null
}

/** Opens the share sheet for [text] (UzTranslit itself is left out of it); false when it cannot be sent. */
fun shareText(context: Context, text: String): Boolean {
    if (text.length > MAX_TRANSFER_CHARS) return false
    return try {
        val send = Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, text)
        val chooser = Intent.createChooser(send, context.getString(R.string.share_result))
            .putExtra(Intent.EXTRA_EXCLUDE_COMPONENTS, arrayOf(ComponentName(context, MainActivity::class.java)))
        if (context !is android.app.Activity) chooser.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(chooser)
        true
    } catch (_: RuntimeException) { // no target, or the text did not fit into the intent
        false
    }
}

fun toast(context: Context, text: String) {
    Toast.makeText(context.applicationContext, text, Toast.LENGTH_SHORT).show()
}
