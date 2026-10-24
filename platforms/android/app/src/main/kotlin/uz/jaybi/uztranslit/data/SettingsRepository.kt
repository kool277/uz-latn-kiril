package uz.jaybi.uztranslit.data

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.emptyPreferences
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import java.io.IOException
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import uz.jaybi.uztranslit.model.Script
import uz.jaybi.uztranslit.model.Source
import uz.jaybi.uztranslit.model.UserSettings

/** The user's settings, shared by every screen, the clipboard tile and the text selection dialog. */
interface SettingsRepository {
    val settings: Flow<UserSettings>

    suspend fun update(transform: (UserSettings) -> UserSettings)
}

/** One DataStore per process for the file "settings" (DataStore must never be opened twice). */
val Context.settingsDataStore: DataStore<Preferences> by preferencesDataStore(name = "settings")

class DataStoreSettingsRepository(private val store: DataStore<Preferences>) : SettingsRepository {
    override val settings: Flow<UserSettings> = store.data
        .catch { e -> if (e is IOException) emit(emptyPreferences()) else throw e } // unreadable file: defaults
        .map { it.toSettings() }
        .distinctUntilChanged()

    override suspend fun update(transform: (UserSettings) -> UserSettings) {
        store.edit { prefs ->
            val next = transform(prefs.toSettings())
            prefs[SOURCE] = next.source.id
            prefs[TARGET] = next.target.id
            prefs[ASCII_APOSTROPHE] = next.asciiApostrophe
            prefs[DICTIONARY] = next.dictionary
            prefs[DROP_HARD_SIGN_AFTER_O] = next.dropHardSignAfterO
        }
    }

    private fun Preferences.toSettings(): UserSettings {
        val defaults = UserSettings()
        return UserSettings(
            source = Source.of(this[SOURCE]) ?: defaults.source,
            target = Script.of(this[TARGET]) ?: defaults.target,
            asciiApostrophe = this[ASCII_APOSTROPHE] ?: defaults.asciiApostrophe,
            dictionary = this[DICTIONARY] ?: defaults.dictionary,
            dropHardSignAfterO = this[DROP_HARD_SIGN_AFTER_O] ?: defaults.dropHardSignAfterO,
        )
    }

    private companion object {
        val SOURCE = stringPreferencesKey("source")
        val TARGET = stringPreferencesKey("target")
        val ASCII_APOSTROPHE = booleanPreferencesKey("asciiApostrophe")
        val DICTIONARY = booleanPreferencesKey("dictionary")
        val DROP_HARD_SIGN_AFTER_O = booleanPreferencesKey("dropHardSignAfterO")
    }
}
