package uz.jaybi.uztranslit.data

import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import java.io.File
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import uz.jaybi.uztranslit.model.Script
import uz.jaybi.uztranslit.model.Source
import uz.jaybi.uztranslit.model.UserSettings

/** The real DataStore implementation, on a temporary file. */
class SettingsRepositoryTest {
    @TempDir
    lateinit var dir: File

    @Test
    fun `defaults, then every field round-trips`() = runTest {
        val store = PreferenceDataStoreFactory.create(scope = backgroundScope) { File(dir, "settings.preferences_pb") }
        val repository = DataStoreSettingsRepository(store)
        assertEquals(UserSettings(), repository.settings.first())

        val changed = UserSettings(
            source = Source.CYR, target = Script.LAT, asciiApostrophe = true, dictionary = false, dropHardSignAfterO = false,
        )
        repository.update { changed }
        assertEquals(changed, repository.settings.first())
        repository.update { it.copy(source = Source.AUTO) }
        assertEquals(changed.copy(source = Source.AUTO), repository.settings.first())
    }
}
