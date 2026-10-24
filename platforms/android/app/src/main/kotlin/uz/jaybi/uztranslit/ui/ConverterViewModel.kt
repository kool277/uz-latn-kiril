package uz.jaybi.uztranslit.ui

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.ViewModelProvider.AndroidViewModelFactory.Companion.APPLICATION_KEY
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import java.io.IOException
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.filter
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.mapLatest
import kotlinx.coroutines.flow.mapNotNull
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import uz.jaybi.uztranslit.UzTranslitApplication
import uz.jaybi.uztranslit.data.ContentResolverDocumentStore
import uz.jaybi.uztranslit.data.DocumentStore
import uz.jaybi.uztranslit.data.DocumentTooLargeException
import uz.jaybi.uztranslit.data.SettingsRepository
import uz.jaybi.uztranslit.model.Direction
import uz.jaybi.uztranslit.model.MAX_FILE_BYTES
import uz.jaybi.uztranslit.model.Script
import uz.jaybi.uztranslit.model.Source
import uz.jaybi.uztranslit.model.TextEncoding
import uz.jaybi.uztranslit.model.TextStats
import uz.jaybi.uztranslit.model.UserSettings
import uz.jaybi.uztranslit.model.convertText
import uz.jaybi.uztranslit.model.decodeText
import uz.jaybi.uztranslit.model.encodeText
import uz.jaybi.uztranslit.model.extensionOf
import uz.jaybi.uztranslit.model.isSupportedTextFile
import uz.jaybi.uztranslit.model.outputFileName
import uz.jaybi.uztranslit.model.resolveDirection
import uz.jaybi.uztranslit.model.textStats

/** The converted text of the main screen. [text] is the input that [result] belongs to. */
data class ConverterState(
    val ready: Boolean = false,
    val text: String = "",
    val settings: UserSettings? = null,
    val result: String = "",
    /** The effective direction (null while the input is empty). */
    val from: Script? = null,
    val to: Script = Script.NEW,
    /** The detected source when the source is "Auto". */
    val detected: Script? = null,
    val inputStats: TextStats = TextStats.EMPTY,
    val resultStats: TextStats = TextStats.EMPTY,
) {
    val sameScript: Boolean get() = from != null && from == to
}

enum class FilePhase { LOADING, CONVERTING, READY, SAVING, SAVED, FAILED }

enum class FileError { READ, TOO_LARGE, TYPE, SAVE }

/** A file shared with the app (or opened in it), converted in memory and saved through the Storage Access Framework. */
data class FileState(
    val phase: FilePhase,
    val name: String? = null,
    val sizeBytes: Long = 0,
    val mimeType: String? = null,
    val detected: Script? = null,
    val from: Script? = null,
    val to: Script = Script.NEW,
    /** Suggested name of the converted file, e.g. hujjat-new.txt. */
    val outputName: String = "",
    val preview: String = "",
    val truncated: Boolean = false,
    /** The file was not UTF-8/UTF-16: it was read as Windows-1251 and the result is written as UTF-8. */
    val legacyEncoding: Boolean = false,
    val inputStats: TextStats = TextStats.EMPTY,
    val resultStats: TextStats = TextStats.EMPTY,
    val savedName: String? = null,
    /** Why the file failed ([FilePhase.FAILED]), or [FileError.SAVE] after a failed save ([FilePhase.READY]). */
    val error: FileError? = null,
) {
    val extension: String? get() = extensionOf(outputName)
}

/**
 * Main screen logic: live conversion of the editor text with the user's settings, swap, settings changes (persisted
 * through [SettingsRepository]) and the conversion of shared files. No Android framework calls: JVM unit tests run it.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class ConverterViewModel(
    private val settingsRepository: SettingsRepository,
    private val documents: DocumentStore,
    private val work: CoroutineDispatcher = Dispatchers.Default,
) : ViewModel() {

    /** The editor text, as Compose state: the text field reads its own value back synchronously while typing. */
    var input: String by mutableStateOf("")
        private set

    /** Everything a conversion depends on, changed atomically (a swap changes the text and the direction at once). */
    private data class Request(val text: String, val settings: UserSettings?)

    private val request = MutableStateFlow(Request("", null))
    private var pendingWrites = 0

    /** The user's settings, as shown by the controls; null until they have been read. */
    val settings: StateFlow<UserSettings?> = request.map { it.settings }.distinctUntilChanged()
        .stateIn(viewModelScope, SharingStarted.Eagerly, null)

    val state: StateFlow<ConverterState> = request
        .filter { it.settings != null }
        .mapLatest { r ->
            // short texts convert on every keystroke; long ones once typing pauses (like the web app)
            if (r.text.length >= LONG_TEXT) delay(LONG_TEXT_DELAY_MS)
            withContext(work) { compute(r.text, r.settings!!) }
        }
        .stateIn(viewModelScope, SharingStarted.Eagerly, ConverterState())

    private val _file = MutableStateFlow<FileState?>(null)
    val file: StateFlow<FileState?> = _file.asStateFlow()
    private var fileText: String? = null
    private var fileResult: String? = null
    private var fileEncoding = TextEncoding.UTF8
    private var fileJob: Job? = null

    init {
        viewModelScope.launch {
            settingsRepository.settings.collect { s ->
                // while our own writes are in flight their echoes would undo newer local changes
                if (pendingWrites == 0) request.update { it.copy(settings = s) }
            }
        }
    }

    private fun compute(text: String, s: UserSettings): ConverterState {
        if (text.isEmpty()) return ConverterState(ready = true, settings = s, to = s.target)
        val d = resolveDirection(text, s.source, s.target)
        val result = convertText(text, d, s.options())
        return ConverterState(
            ready = true, text = text, settings = s, result = result, from = d.from, to = d.to, detected = d.detected,
            inputStats = textStats(text), resultStats = textStats(result),
        )
    }

    // ------------------------------------------------------------------ editor and settings

    fun onInputChange(text: String) {
        input = text
        request.update { it.copy(text = text) }
    }

    fun clear() = onInputChange("")

    fun setSource(source: Source) = updateSettings { it.copy(source = source) }

    fun setTarget(target: Script) = updateSettings { it.copy(target = target) }

    fun setAsciiApostrophe(on: Boolean) = updateSettings { it.copy(asciiApostrophe = on) }

    fun setDictionary(on: Boolean) = updateSettings { it.copy(dictionary = on) }

    fun setDropHardSignAfterO(on: Boolean) = updateSettings { it.copy(dropHardSignAfterO = on) }

    /**
     * Swaps the direction and makes the result the new input, so the text converts back. The new source is the
     * alphabet the result is in (explicit, not "Auto": Ishoq is Latin 2026, and detection would call it Latin 1995).
     */
    fun swap() {
        val s = request.value.settings ?: return
        val text = input
        val st = state.value
        val current = st.ready && st.text == text && st.settings == s && st.from != null
        val d = when {
            text.isEmpty() -> Direction(s.source.script ?: Script.LAT, s.target)
            current -> Direction(st.from, st.to, st.detected)
            else -> resolveDirection(text, s.source, s.target)
        }
        val newText = when {
            text.isEmpty() -> ""
            current -> st.result
            else -> convertText(text, d, s.options())
        }
        val transform = { u: UserSettings -> u.copy(source = Source.of(d.to), target = d.from) }
        input = newText
        request.update { Request(newText, it.settings?.let(transform)) }
        persist(transform)
    }

    private fun updateSettings(transform: (UserSettings) -> UserSettings) {
        if (request.value.settings == null) return // not read yet: the controls are disabled until then
        request.update { it.copy(settings = it.settings?.let(transform)) }
        persist(transform)
    }

    private fun persist(transform: (UserSettings) -> UserSettings) {
        pendingWrites++
        viewModelScope.launch {
            try {
                settingsRepository.update(transform)
            } catch (_: IOException) {
                // not saved: the change still applies until the app restarts
            } finally {
                pendingWrites--
            }
        }
    }

    private suspend fun awaitSettings(): UserSettings =
        request.value.settings ?: request.mapNotNull { it.settings }.first()

    // ------------------------------------------------------------------ files

    /** Reads, checks, decodes and converts a shared or opened file (to the user's target, source detected). */
    fun openFile(uri: String, mimeTypeHint: String?) {
        fileJob?.cancel()
        fileText = null
        fileResult = null
        _file.value = FileState(phase = FilePhase.LOADING)
        fileJob = viewModelScope.launch {
            val doc = try {
                documents.read(uri, MAX_FILE_BYTES)
            } catch (_: DocumentTooLargeException) {
                _file.value = FileState(phase = FilePhase.FAILED, error = FileError.TOO_LARGE)
                return@launch
            } catch (e: CancellationException) {
                throw e
            } catch (_: Exception) { // IOException, SecurityException (no permission), provider errors
                _file.value = FileState(phase = FilePhase.FAILED, error = FileError.READ)
                return@launch
            }
            val mimeType = doc.mimeType ?: mimeTypeHint
            if (!isSupportedTextFile(doc.name, mimeType)) {
                _file.value = FileState(phase = FilePhase.FAILED, name = doc.name, error = FileError.TYPE)
                return@launch
            }
            val decoded = withContext(work) { decodeText(doc.bytes) }
            fileText = decoded.text
            fileEncoding = decoded.encoding
            val d = resolveDirection(decoded.text, Source.AUTO, awaitSettings().target)
            _file.value = FileState(
                phase = FilePhase.CONVERTING, name = doc.name, sizeBytes = doc.bytes.size.toLong(), mimeType = mimeType,
                detected = d.detected, from = d.from, to = d.to, outputName = outputFileName(doc.name, d.to),
                legacyEncoding = decoded.encoding == TextEncoding.WINDOWS_1251,
            )
            convertFile(d)
        }
    }

    private suspend fun convertFile(d: Direction) {
        val text = fileText ?: return
        val options = awaitSettings().options()
        _file.update { it?.copy(phase = FilePhase.CONVERTING, from = d.from, to = d.to, error = null) }
        val result = withContext(work) { convertText(text, d, options) }
        val inputStats = withContext(work) { textStats(text) }
        val resultStats = withContext(work) { textStats(result) }
        fileResult = result
        _file.update {
            it?.copy(
                phase = FilePhase.READY, outputName = outputFileName(it.name, d.to), preview = result.take(PREVIEW_CHARS),
                truncated = result.length > PREVIEW_CHARS, inputStats = inputStats, resultStats = resultStats,
                savedName = null,
            )
        }
    }

    /** Converts the open file to another alphabet (the source stays the detected one). */
    fun setFileTarget(target: Script) {
        val f = _file.value ?: return
        val from = f.from ?: return
        if (fileText == null || f.phase == FilePhase.SAVING || (f.to == target && f.phase == FilePhase.READY)) return
        fileJob?.cancel()
        fileJob = viewModelScope.launch { convertFile(Direction(from, target, f.detected)) }
    }

    /** Writes the converted file to [uri], a document the user created with ACTION_CREATE_DOCUMENT. */
    fun saveFile(uri: String) {
        val f = _file.value ?: return
        val result = fileResult ?: return
        if (f.phase != FilePhase.READY && f.phase != FilePhase.SAVED) return
        val encoding = fileEncoding.output
        fileJob = viewModelScope.launch {
            _file.update { it?.copy(phase = FilePhase.SAVING, error = null) }
            try {
                val bytes = withContext(work) { encodeText(result, encoding) }
                val savedAs = documents.write(uri, bytes)
                _file.update { it?.copy(phase = FilePhase.SAVED, savedName = savedAs ?: it.outputName) }
            } catch (e: CancellationException) {
                throw e
            } catch (_: Exception) {
                _file.update { it?.copy(phase = FilePhase.READY, error = FileError.SAVE) }
            }
        }
    }

    fun closeFile() {
        fileJob?.cancel()
        fileText = null
        fileResult = null
        _file.value = null
    }

    companion object {
        const val LONG_TEXT = 50_000
        const val LONG_TEXT_DELAY_MS = 250L
        const val PREVIEW_CHARS = 2000

        val Factory: ViewModelProvider.Factory = viewModelFactory {
            initializer {
                val app = this[APPLICATION_KEY] as UzTranslitApplication
                ConverterViewModel(app.settingsRepository, ContentResolverDocumentStore(app.contentResolver))
            }
        }
    }
}
