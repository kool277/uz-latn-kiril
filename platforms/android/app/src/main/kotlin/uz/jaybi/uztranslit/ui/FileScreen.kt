package uz.jaybi.uztranslit.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import uz.jaybi.uztranslit.R
import uz.jaybi.uztranslit.labelRes
import uz.jaybi.uztranslit.model.MAX_FILE_BYTES
import uz.jaybi.uztranslit.model.Script
import uz.jaybi.uztranslit.model.SizeUnit
import uz.jaybi.uztranslit.model.formatSize
import uz.jaybi.uztranslit.nameRes

/** A shared or opened text file: detected alphabet, target choice, preview and "Save as hujjat-new.txt". */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FileScreen(file: FileState, onTarget: (Script) -> Unit, onSave: () -> Unit, onClose: () -> Unit) {
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.file_title)) },
                navigationIcon = {
                    IconButton(onClick = onClose) {
                        Icon(painterResource(R.drawable.ic_back), contentDescription = stringResource(R.string.back))
                    }
                },
            )
        },
    ) { padding ->
        Column(
            Modifier
                .fillMaxSize()
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            if (file.name != null) FileHeader(file)
            when (file.phase) {
                FilePhase.LOADING -> Progress(R.string.file_loading)
                FilePhase.FAILED -> {
                    Text(errorText(file.error), color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodyLarge)
                    OutlinedButton(onClick = onClose) { Text(stringResource(R.string.file_done)) }
                }
                else -> FileBody(file, onTarget, onSave, onClose)
            }
        }
    }
}

@Composable
private fun FileHeader(file: FileState) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Icon(painterResource(R.drawable.ic_file), contentDescription = null, modifier = Modifier.size(32.dp))
        Column(Modifier.weight(1f)) {
            Text(file.name.orEmpty(), style = MaterialTheme.typography.titleMedium, maxLines = 2, overflow = TextOverflow.Ellipsis)
            if (file.sizeBytes > 0) {
                Text(sizeText(file.sizeBytes), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}

@Composable
private fun FileBody(file: FileState, onTarget: (Script) -> Unit, onSave: () -> Unit, onClose: () -> Unit) {
    val from = file.from ?: return
    val busy = file.phase == FilePhase.CONVERTING || file.phase == FilePhase.SAVING
    Text(
        stringResource(R.string.detected, stringResource(from.nameRes())),
        style = MaterialTheme.typography.bodyMedium,
    )
    Text(stringResource(R.string.file_to), style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
    ChoiceRow(
        options = Script.entries,
        selected = file.to,
        label = { stringResource(it.labelRes()) },
        onSelect = onTarget,
        enabled = !busy,
    )
    if (from == file.to) Text(stringResource(R.string.same_script), style = MaterialTheme.typography.bodySmall)
    if (file.legacyEncoding) Text(stringResource(R.string.file_encoding_legacy), style = MaterialTheme.typography.bodySmall)
    if (file.phase == FilePhase.CONVERTING) {
        Progress(R.string.file_converting)
    } else {
        Text(stringResource(R.string.file_preview), style = MaterialTheme.typography.titleSmall)
        Surface(color = MaterialTheme.colorScheme.surfaceVariant, shape = MaterialTheme.shapes.medium) {
            SelectionContainer {
                Text(
                    file.preview,
                    fontFamily = FontFamily.Monospace,
                    style = MaterialTheme.typography.bodySmall,
                    modifier = Modifier
                        .fillMaxWidth()
                        .heightIn(max = 320.dp)
                        .verticalScroll(rememberScrollState())
                        .padding(12.dp),
                )
            }
        }
        val stats = statsText(file.resultStats) + " · " +
            stringResource(R.string.direction, stringResource(from.nameRes()), stringResource(file.to.nameRes()))
        Text(stats, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        if (file.truncated) {
            Text(
                pluralStringResource(R.plurals.file_preview_truncated, file.preview.length, file.preview.length),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
    if (file.error == FileError.SAVE) {
        Text(stringResource(R.string.file_error_save), color = MaterialTheme.colorScheme.error)
    }
    when (file.phase) {
        FilePhase.SAVED -> {
            Text(stringResource(R.string.file_saved, file.savedName ?: file.outputName), style = MaterialTheme.typography.bodyLarge)
            Button(onClick = onClose) { Text(stringResource(R.string.file_done)) }
        }
        FilePhase.SAVING -> Progress(R.string.file_saving)
        else -> Button(onClick = onSave, enabled = file.phase == FilePhase.READY, modifier = Modifier.fillMaxWidth()) {
            Icon(painterResource(R.drawable.ic_save), contentDescription = null, modifier = Modifier.padding(end = 8.dp))
            Text(stringResource(R.string.file_save, file.outputName), maxLines = 2, overflow = TextOverflow.Ellipsis)
        }
    }
}

@Composable
private fun Progress(text: Int) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        CircularProgressIndicator(Modifier.size(24.dp), strokeWidth = 3.dp)
        Text(stringResource(text))
    }
}

@Composable
private fun errorText(error: FileError?): String = when (error) {
    FileError.TOO_LARGE -> stringResource(R.string.file_error_too_large, MAX_FILE_BYTES / (1024 * 1024))
    FileError.TYPE -> stringResource(R.string.file_error_type)
    FileError.SAVE -> stringResource(R.string.file_error_save)
    FileError.READ, null -> stringResource(R.string.file_error_read)
}

@Composable
private fun sizeText(bytes: Long): String {
    val (number, unit) = formatSize(bytes)
    return when (unit) {
        SizeUnit.B -> stringResource(R.string.size_b, number)
        SizeUnit.KB -> stringResource(R.string.size_kb, number)
        SizeUnit.MB -> stringResource(R.string.size_mb, number)
    }
}
