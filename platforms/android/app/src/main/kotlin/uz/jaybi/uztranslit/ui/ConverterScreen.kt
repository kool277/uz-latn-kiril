package uz.jaybi.uztranslit.ui

import androidx.annotation.StringRes
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.consumeWindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.isImeVisible
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalResources
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import kotlinx.coroutines.launch
import uz.jaybi.uztranslit.R
import uz.jaybi.uztranslit.labelRes
import uz.jaybi.uztranslit.model.Script
import uz.jaybi.uztranslit.model.Source
import uz.jaybi.uztranslit.model.UserSettings
import uz.jaybi.uztranslit.model.textStats
import uz.jaybi.uztranslit.nameRes

/** The main screen: direction controls, the editor and the live result. */
@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
fun ConverterScreen(viewModel: ConverterViewModel, onOpenSettings: () -> Unit, onOpenFile: () -> Unit) {
    val loaded by viewModel.settings.collectAsStateWithLifecycle()
    val state by viewModel.state.collectAsStateWithLifecycle()
    val settings = loaded ?: UserSettings()
    val context = LocalContext.current
    val resources = LocalResources.current
    val snackbar = remember { SnackbarHostState() }
    val scope = rememberCoroutineScope()
    fun message(@StringRes id: Int) {
        scope.launch {
            snackbar.currentSnackbarData?.dismiss()
            snackbar.showSnackbar(resources.getString(id))
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.app_name)) },
                actions = {
                    IconButton(onClick = onOpenFile) {
                        Icon(painterResource(R.drawable.ic_file), contentDescription = stringResource(R.string.open_file))
                    }
                    IconButton(onClick = onOpenSettings) {
                        Icon(painterResource(R.drawable.ic_settings), contentDescription = stringResource(R.string.settings))
                    }
                },
            )
        },
        snackbarHost = { SnackbarHost(snackbar) },
    ) { padding ->
        BoxWithConstraints(
            Modifier
                .fillMaxSize()
                .padding(padding)
                .consumeWindowInsets(padding)
                .imePadding()
                .padding(horizontal = 16.dp, vertical = 8.dp),
        ) {
            // with the keyboard up on a small screen the editor needs the room more than the direction controls
            val compact = WindowInsets.isImeVisible && maxHeight < 480.dp
            val wide = maxWidth >= 600.dp
            Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                AnimatedVisibility(visible = !compact) {
                    DirectionControls(settings, enabled = loaded != null, viewModel)
                }
                val input: @Composable (Modifier) -> Unit = { m ->
                    InputPane(viewModel, state, m, onPaste = {
                        val text = readClipboardText(context)
                        if (text.isNullOrEmpty()) message(R.string.nothing_to_paste) else viewModel.onInputChange(text)
                    })
                }
                val result: @Composable (Modifier) -> Unit = { m ->
                    ResultPane(
                        state, m,
                        onCopy = {
                            when {
                                !copyText(context, state.result) -> message(R.string.text_too_large)
                                !systemConfirmsCopy -> message(R.string.copied)
                            }
                        },
                        onShare = { if (!shareText(context, state.result)) message(R.string.text_too_large) },
                    )
                }
                if (wide) {
                    Row(Modifier.weight(1f), horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                        input(Modifier.weight(1f))
                        result(Modifier.weight(1f))
                    }
                } else {
                    input(Modifier.weight(1f))
                    result(Modifier.weight(1f))
                }
            }
        }
    }
}

@Composable
private fun DirectionControls(settings: UserSettings, enabled: Boolean, viewModel: ConverterViewModel) {
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Caption(R.string.from_label)
        ChoiceRow(
            options = Source.entries,
            selected = settings.source,
            label = { stringResource(it.labelRes()) },
            onSelect = viewModel::setSource,
            enabled = enabled,
        )
        Caption(R.string.to_label)
        Row(verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = viewModel::swap, enabled = enabled) {
                Icon(painterResource(R.drawable.ic_swap), contentDescription = stringResource(R.string.swap))
            }
            ChoiceRow(
                options = Script.entries,
                selected = settings.target,
                label = { stringResource(it.labelRes()) },
                onSelect = viewModel::setTarget,
                enabled = enabled,
                modifier = Modifier.weight(1f),
            )
        }
        FilterChip(
            selected = settings.asciiApostrophe,
            onClick = { viewModel.setAsciiApostrophe(!settings.asciiApostrophe) },
            enabled = enabled,
            label = { Text(stringResource(R.string.ascii_apostrophe), maxLines = 1) },
        )
    }
}

@Composable
private fun Caption(@StringRes id: Int) {
    Text(stringResource(id), style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
}

@Composable
private fun PaneHeader(@StringRes title: Int, actions: @Composable () -> Unit) {
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Text(stringResource(title), style = MaterialTheme.typography.titleSmall, modifier = Modifier.weight(1f))
        actions()
    }
}

@Composable
private fun StatsLine(text: String) {
    Text(
        text,
        style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        maxLines = 2,
        overflow = TextOverflow.Ellipsis,
        modifier = Modifier.padding(horizontal = 4.dp),
    )
}

@Composable
private fun InputPane(viewModel: ConverterViewModel, state: ConverterState, modifier: Modifier, onPaste: () -> Unit) {
    val text = viewModel.input
    Column(modifier) {
        PaneHeader(R.string.input_label) {
            IconButton(onClick = onPaste) {
                Icon(painterResource(R.drawable.ic_paste), contentDescription = stringResource(R.string.paste))
            }
            IconButton(onClick = viewModel::clear, enabled = text.isNotEmpty()) {
                Icon(painterResource(R.drawable.ic_clear), contentDescription = stringResource(R.string.clear))
            }
        }
        OutlinedTextField(
            value = text,
            onValueChange = viewModel::onInputChange,
            modifier = Modifier.weight(1f).fillMaxWidth(),
            placeholder = { Text(stringResource(R.string.input_placeholder)) },
            keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.None, autoCorrectEnabled = false),
        )
        val stats = remember(text) { textStats(text) }
        val detected = state.detected?.takeIf { state.text == text && text.isNotEmpty() }
        StatsLine(
            if (detected == null) {
                statsText(stats)
            } else {
                statsText(stats) + " · " + stringResource(R.string.detected, stringResource(detected.nameRes()))
            },
        )
    }
}

@Composable
private fun ResultPane(
    state: ConverterState,
    modifier: Modifier,
    onCopy: () -> Unit,
    onShare: () -> Unit,
) {
    Column(modifier) {
        PaneHeader(R.string.result_label) {
            IconButton(onClick = onCopy, enabled = state.result.isNotEmpty()) {
                Icon(painterResource(R.drawable.ic_copy), contentDescription = stringResource(R.string.copy))
            }
            IconButton(onClick = onShare, enabled = state.result.isNotEmpty()) {
                Icon(painterResource(R.drawable.ic_share), contentDescription = stringResource(R.string.share))
            }
        }
        OutlinedTextField(
            value = state.result,
            onValueChange = {},
            readOnly = true,
            modifier = Modifier.weight(1f).fillMaxWidth(),
            placeholder = { Text(stringResource(R.string.result_label)) },
        )
        val from = state.from
        StatsLine(
            when {
                from == null -> ""
                state.sameScript -> stringResource(R.string.same_script)
                else -> statsText(state.resultStats) + " · " +
                    stringResource(R.string.direction, stringResource(from.nameRes()), stringResource(state.to.nameRes()))
            },
        )
    }
}
