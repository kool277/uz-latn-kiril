package uz.jaybi.uztranslit

import android.app.Application
import android.content.Context
import androidx.annotation.StringRes
import uz.jaybi.uztranslit.data.DataStoreSettingsRepository
import uz.jaybi.uztranslit.data.SettingsRepository
import uz.jaybi.uztranslit.data.settingsDataStore
import uz.jaybi.uztranslit.model.Script
import uz.jaybi.uztranslit.model.Source

class UzTranslitApplication : Application() {
    /** The settings of every screen, the Quick Settings tile and the text selection dialog (one DataStore). */
    val settingsRepository: SettingsRepository by lazy { DataStoreSettingsRepository(settingsDataStore) }
}

val Context.settingsRepository: SettingsRepository
    get() = (applicationContext as UzTranslitApplication).settingsRepository

/** Label of a segmented control: Кирилл / Lotin 1995 / Yangi lotin. */
@StringRes
fun Script.labelRes(): Int = when (this) {
    Script.CYR -> R.string.script_cyr
    Script.LAT -> R.string.script_lat
    Script.NEW -> R.string.script_new
}

@StringRes
fun Source.labelRes(): Int = script?.labelRes() ?: R.string.script_auto

/** Name inside a sentence: "aniqlandi: kirill", "kirill → yangi lotin". */
@StringRes
fun Script.nameRes(): Int = when (this) {
    Script.CYR -> R.string.name_cyr
    Script.LAT -> R.string.name_lat
    Script.NEW -> R.string.name_new
}
