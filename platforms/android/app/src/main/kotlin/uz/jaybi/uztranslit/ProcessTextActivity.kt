package uz.jaybi.uztranslit

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalResources
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import uz.jaybi.uztranslit.model.Direction
import uz.jaybi.uztranslit.model.Script
import uz.jaybi.uztranslit.model.Source
import uz.jaybi.uztranslit.model.UserSettings
import uz.jaybi.uztranslit.model.convertText
import uz.jaybi.uztranslit.model.resolveDirection
import uz.jaybi.uztranslit.ui.ChoiceRow
import uz.jaybi.uztranslit.ui.copyText
import uz.jaybi.uztranslit.ui.shareText
import uz.jaybi.uztranslit.ui.systemConfirmsCopy
import uz.jaybi.uztranslit.ui.theme.UzTranslitTheme
import uz.jaybi.uztranslit.ui.toast

/**
 * "UzTranslit bilan oʻgirish" in the text selection menu of any app (ACTION_PROCESS_TEXT): shows the selected text
 * converted to the user's target (source detected) and gives it back in EXTRA_PROCESS_TEXT, which replaces the
 * selection, when the calling app allows that (EXTRA_PROCESS_TEXT_READONLY is false); otherwise copy or share.
 */
class ProcessTextActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val text = intent.getCharSequenceExtra(Intent.EXTRA_PROCESS_TEXT)?.toString()
        if (text.isNullOrEmpty()) {
            finish()
            return
        }
        val readOnly = intent.getBooleanExtra(Intent.EXTRA_PROCESS_TEXT_READONLY, false)
        val repository = settingsRepository
        setContent {
            UzTranslitTheme {
                val settings by repository.settings.collectAsStateWithLifecycle(initialValue = null)
                settings?.let { s ->
                    ProcessTextDialog(
                        text = text,
                        readOnly = readOnly,
                        settings = s,
                        onReplace = { result ->
                            setResult(RESULT_OK, Intent().putExtra(Intent.EXTRA_PROCESS_TEXT, result))
                            finish()
                        },
                        onDismiss = ::finish,
                    )
                }
            }
        }
    }
}

@Composable
private fun ProcessTextDialog(
    text: String,
    readOnly: Boolean,
    settings: UserSettings,
    onReplace: (String) -> Unit,
    onDismiss: () -> Unit,
) {
    val context = LocalContext.current
    val resources = LocalResources.current
    val initial = remember(text) { resolveDirection(text, Source.AUTO, settings.target) }
    var target by rememberSaveable { mutableStateOf(initial.to) }
    val direction = Direction(initial.from, target, initial.detected)
    val result = remember(text, direction, settings) { convertText(text, direction, settings.options()) }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(R.string.action_process_text)) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                ChoiceRow(
                    options = Script.entries,
                    selected = target,
                    label = { stringResource(it.labelRes()) },
                    onSelect = { target = it },
                )
                Text(
                    if (direction.from == direction.to) {
                        stringResource(R.string.same_script)
                    } else {
                        stringResource(R.string.direction, stringResource(direction.from.nameRes()), stringResource(direction.to.nameRes()))
                    },
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Surface(color = MaterialTheme.colorScheme.surfaceVariant, shape = MaterialTheme.shapes.medium) {
                    SelectionContainer {
                        Text(
                            result,
                            style = MaterialTheme.typography.bodyLarge,
                            modifier = Modifier
                                .fillMaxWidth()
                                .heightIn(max = 280.dp)
                                .verticalScroll(rememberScrollState())
                                .padding(12.dp),
                        )
                    }
                }
                if (readOnly) {
                    Text(stringResource(R.string.process_readonly), style = MaterialTheme.typography.bodySmall)
                }
            }
        },
        confirmButton = {
            if (readOnly) {
                TextButton(onClick = {
                    if (shareText(context, result)) onDismiss() else toast(context, resources.getString(R.string.text_too_large))
                }) { Text(stringResource(R.string.share)) }
            } else {
                TextButton(onClick = { onReplace(result) }) { Text(stringResource(R.string.process_replace)) }
            }
        },
        dismissButton = {
            Row {
                TextButton(onClick = onDismiss) { Text(stringResource(R.string.cancel)) }
                TextButton(onClick = {
                    when {
                        !copyText(context, result) -> toast(context, resources.getString(R.string.text_too_large))
                        else -> {
                            if (!systemConfirmsCopy) toast(context, resources.getString(R.string.copied))
                            onDismiss()
                        }
                    }
                }) { Text(stringResource(R.string.copy)) }
            }
        },
    )
}
