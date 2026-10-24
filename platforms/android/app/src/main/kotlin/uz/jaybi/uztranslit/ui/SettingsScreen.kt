package uz.jaybi.uztranslit.ui

import androidx.annotation.StringRes
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import uz.jaybi.uztranslit.BuildConfig
import uz.jaybi.uztranslit.R
import uz.jaybi.uztranslit.core.UzTranslit
import uz.jaybi.uztranslit.labelRes
import uz.jaybi.uztranslit.model.Script
import uz.jaybi.uztranslit.model.UserSettings

private const val WEB_APP = "https://latin.jaybi.uz"

/** Target alphabet, apostrophe style, dictionary and ўъ: persisted, shared with the tile and the text dialog. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(viewModel: ConverterViewModel, onBack: () -> Unit) {
    val loaded by viewModel.settings.collectAsStateWithLifecycle()
    val s = loaded ?: UserSettings()
    val enabled = loaded != null
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.settings)) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
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
                .verticalScroll(rememberScrollState()),
        ) {
            Section(R.string.settings_target)
            Text(
                stringResource(R.string.settings_target_summary),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(horizontal = 16.dp),
            )
            Column(Modifier.selectableGroup()) {
                for (script in Script.entries) {
                    Choice(stringResource(script.labelRes()), s.target == script, enabled) { viewModel.setTarget(script) }
                }
            }
            HorizontalDivider()
            Section(R.string.settings_apostrophe)
            Column(Modifier.selectableGroup()) {
                Choice(stringResource(R.string.settings_apostrophe_typographic), !s.asciiApostrophe, enabled) {
                    viewModel.setAsciiApostrophe(false)
                }
                Choice(stringResource(R.string.settings_apostrophe_ascii), s.asciiApostrophe, enabled) {
                    viewModel.setAsciiApostrophe(true)
                }
            }
            HorizontalDivider()
            Section(R.string.settings_rules)
            Toggle(R.string.settings_dictionary, R.string.settings_dictionary_summary, s.dictionary, enabled, viewModel::setDictionary)
            Toggle(
                R.string.settings_drop_hard, R.string.settings_drop_hard_summary, s.dropHardSignAfterO, enabled,
                viewModel::setDropHardSignAfterO,
            )
            HorizontalDivider()
            Section(R.string.settings_about)
            Text(
                stringResource(R.string.settings_about_text),
                style = MaterialTheme.typography.bodyMedium,
                modifier = Modifier.padding(horizontal = 16.dp),
            )
            Text(
                stringResource(R.string.settings_version, BuildConfig.VERSION_NAME, UzTranslit.VERSION),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
            )
            val uriHandler = LocalUriHandler.current
            TextButton(
                onClick = { runCatching { uriHandler.openUri(WEB_APP) } },
                modifier = Modifier.padding(horizontal = 4.dp, vertical = 8.dp),
            ) {
                Text(stringResource(R.string.settings_web))
            }
        }
    }
}

@Composable
private fun Section(@StringRes title: Int) {
    Text(
        stringResource(title),
        style = MaterialTheme.typography.titleSmall,
        color = MaterialTheme.colorScheme.primary,
        modifier = Modifier.padding(start = 16.dp, end = 16.dp, top = 20.dp, bottom = 8.dp),
    )
}

@Composable
private fun Choice(label: String, selected: Boolean, enabled: Boolean, onSelect: () -> Unit) {
    ListItem(
        headlineContent = { Text(label) },
        leadingContent = { RadioButton(selected = selected, onClick = null, enabled = enabled) },
        modifier = Modifier.selectable(selected = selected, enabled = enabled, role = Role.RadioButton, onClick = onSelect),
    )
}

@Composable
private fun Toggle(@StringRes title: Int, @StringRes summary: Int, checked: Boolean, enabled: Boolean, onChange: (Boolean) -> Unit) {
    ListItem(
        headlineContent = { Text(stringResource(title)) },
        supportingContent = { Text(stringResource(summary)) },
        trailingContent = { Switch(checked = checked, onCheckedChange = null, enabled = enabled) },
        modifier = Modifier.toggleable(value = checked, enabled = enabled, role = Role.Switch, onValueChange = onChange),
    )
}
