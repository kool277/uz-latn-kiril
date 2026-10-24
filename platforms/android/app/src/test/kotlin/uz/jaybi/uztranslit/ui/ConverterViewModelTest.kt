package uz.jaybi.uztranslit.ui

import java.io.FileNotFoundException
import java.io.IOException
import java.nio.charset.Charset
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import androidx.lifecycle.viewModelScope
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.Assertions.assertArrayEquals
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.Test
import uz.jaybi.uztranslit.data.DocumentStore
import uz.jaybi.uztranslit.data.DocumentTooLargeException
import uz.jaybi.uztranslit.data.SettingsRepository
import uz.jaybi.uztranslit.data.SharedDocument
import uz.jaybi.uztranslit.model.Script
import uz.jaybi.uztranslit.model.Source
import uz.jaybi.uztranslit.model.TextStats
import uz.jaybi.uztranslit.model.UserSettings

/** In-memory settings; [gate] holds writes back to test what happens while one is in flight. */
private class FakeSettingsRepository(initial: UserSettings = UserSettings()) : SettingsRepository {
    val stored = MutableStateFlow(initial)
    var gate: CompletableDeferred<Unit>? = null
    var writes = 0
    override val settings: Flow<UserSettings> = stored

    override suspend fun update(transform: (UserSettings) -> UserSettings) {
        gate?.await()
        writes++
        stored.update(transform)
    }
}

private class FakeDocumentStore : DocumentStore {
    val documents = mutableMapOf<String, SharedDocument>()
    val written = mutableMapOf<String, ByteArray>()
    var readError: Exception? = null
    var writeError: Exception? = null

    override suspend fun read(uri: String, maxBytes: Int): SharedDocument {
        readError?.let { throw it }
        val doc = documents[uri] ?: throw FileNotFoundException(uri)
        if (doc.bytes.size > maxBytes) throw DocumentTooLargeException(maxBytes)
        return doc
    }

    override suspend fun write(uri: String, bytes: ByteArray): String? {
        writeError?.let { throw it }
        written[uri] = bytes
        return "saved.txt"
    }
}

@OptIn(ExperimentalCoroutinesApi::class)
class ConverterViewModelTest {
    private val dispatcher = StandardTestDispatcher()
    private val repository = FakeSettingsRepository()
    private val documents = FakeDocumentStore()
    private lateinit var vm: ConverterViewModel

    @BeforeEach
    fun setUp() {
        Dispatchers.setMain(dispatcher)
        vm = ConverterViewModel(repository, documents, work = dispatcher)
    }

    @AfterEach
    fun tearDown() {
        vm.viewModelScope.cancel()
        Dispatchers.resetMain()
    }

    private fun test(body: suspend TestScope.() -> Unit) = runTest(dispatcher) {
        advanceUntilIdle() // settings read
        body()
    }

    private fun TestScope.type(text: String) {
        vm.onInputChange(text)
        advanceUntilIdle()
    }

    @Test
    fun `waits for the settings before converting`() = runTest(dispatcher) {
        assertNull(vm.settings.value)
        assertFalse(vm.state.value.ready)
        advanceUntilIdle()
        assertEquals(UserSettings(), vm.settings.value)
        assertTrue(vm.state.value.ready)
    }

    @Test
    fun `converts live, detecting the source`() = test {
        type("Тошкент шаҳри")
        val s = vm.state.value
        assertEquals("Тошкент шаҳри", vm.input)
        assertEquals("Toşkent şahri", s.result)
        assertEquals(Script.CYR, s.detected)
        assertEquals(Script.CYR, s.from)
        assertEquals(Script.NEW, s.to)
        assertEquals(TextStats(13, 2), s.inputStats)
        assertEquals(TextStats(13, 2), s.resultStats)
        type("Тошкент шаҳри, Ўзбекистон")
        assertEquals("Toşkent şahri, Özbekiston", vm.state.value.result)
    }

    @Test
    fun `text already in the target goes to the other alphabet`() = test {
        type("Özbekiston")
        assertEquals("Ўзбекистон", vm.state.value.result)
        assertEquals(Script.NEW, vm.state.value.from)
        assertEquals(Script.CYR, vm.state.value.to)
    }

    @Test
    fun `an explicit source is not detected`() = test {
        vm.setSource(Source.NEW)
        vm.setTarget(Script.CYR)
        type("Ishoq") // detection would say Latin 1995 (Ишоқ); as Latin 2026 it is Исҳоқ
        assertEquals("Исҳоқ", vm.state.value.result)
        assertNull(vm.state.value.detected)
    }

    @Test
    fun `same source and target leave the text as it is`() = test {
        vm.setSource(Source.LAT)
        vm.setTarget(Script.LAT)
        type("Toshkent")
        assertEquals("Toshkent", vm.state.value.result)
        assertTrue(vm.state.value.sameScript)
    }

    @Test
    fun `target and options are applied and persisted`() = test {
        type("Ўзбекистон маъно")
        assertEquals("Özbekiston maʼno", vm.state.value.result)
        vm.setTarget(Script.LAT)
        advanceUntilIdle()
        assertEquals("Oʻzbekiston maʼno", vm.state.value.result)
        vm.setAsciiApostrophe(true)
        advanceUntilIdle()
        assertEquals("O'zbekiston ma'no", vm.state.value.result)
        assertEquals(UserSettings(target = Script.LAT, asciiApostrophe = true), repository.stored.value)
        assertEquals(2, repository.writes)
    }

    @Test
    fun `dictionary and the hard sign after o can be switched off`() = test {
        vm.setSource(Source.LAT)
        vm.setTarget(Script.CYR)
        type("obyekt")
        assertEquals("объект", vm.state.value.result)
        vm.setDictionary(false)
        advanceUntilIdle()
        assertEquals("обьект", vm.state.value.result)

        vm.setSource(Source.CYR)
        vm.setTarget(Script.LAT)
        type("мўъжиза")
        assertEquals("moʻjiza", vm.state.value.result)
        vm.setDropHardSignAfterO(false)
        advanceUntilIdle()
        assertEquals("moʻʼjiza", vm.state.value.result)
        assertEquals(
            UserSettings(source = Source.CYR, target = Script.LAT, dictionary = false, dropHardSignAfterO = false),
            repository.stored.value,
        )
    }

    @Test
    fun `swap converts the result back`() = test {
        type("Исҳоқ Тошкентда")
        assertEquals("Ishoq Toşkentda", vm.state.value.result)
        vm.swap()
        assertEquals("Ishoq Toşkentda", vm.input)
        advanceUntilIdle()
        assertEquals(Source.NEW, vm.settings.value?.source)
        assertEquals(Script.CYR, vm.settings.value?.target)
        assertEquals("Исҳоқ Тошкентда", vm.state.value.result)
        assertEquals(UserSettings(source = Source.NEW, target = Script.CYR), repository.stored.value)
    }

    @Test
    fun `swap right after typing a long text converts it first`() = test {
        val long = "Тошкент ".repeat(ConverterViewModel.LONG_TEXT / 8 + 1)
        vm.onInputChange(long) // still waiting for the typing pause
        vm.swap()
        assertEquals("Toşkent ".repeat(ConverterViewModel.LONG_TEXT / 8 + 1), vm.input)
        advanceUntilIdle()
        assertEquals(long, vm.state.value.result)
    }

    @Test
    fun `swap with an empty editor swaps the direction`() = test {
        vm.swap()
        advanceUntilIdle()
        assertEquals(Source.NEW, vm.settings.value?.source)
        assertEquals(Script.LAT, vm.settings.value?.target)
        assertEquals("", vm.input)
    }

    @Test
    fun `clear empties editor and result`() = test {
        type("Salom")
        vm.clear()
        advanceUntilIdle()
        assertEquals("", vm.input)
        assertEquals("", vm.state.value.result)
        assertNull(vm.state.value.from)
    }

    @Test
    fun `long texts convert once typing pauses`() = test {
        val long = "Салом дунё ".repeat(ConverterViewModel.LONG_TEXT / 11 + 1)
        vm.onInputChange(long)
        advanceTimeBy(ConverterViewModel.LONG_TEXT_DELAY_MS - 10)
        runCurrent()
        assertEquals("", vm.state.value.result)
        vm.onInputChange(long + "Салом") // typing goes on: the wait starts again
        advanceTimeBy(ConverterViewModel.LONG_TEXT_DELAY_MS - 10)
        runCurrent()
        assertEquals("", vm.state.value.result)
        advanceUntilIdle()
        assertEquals("Salom dunyo ".repeat(ConverterViewModel.LONG_TEXT / 11 + 1) + "Salom", vm.state.value.result)
        assertEquals(long + "Салом", vm.state.value.text)
    }

    @Test
    fun `settings changed elsewhere are picked up`() = test {
        type("Тошкент")
        repository.stored.value = UserSettings(target = Script.LAT) // e.g. another window of the app
        advanceUntilIdle()
        assertEquals("Toshkent", vm.state.value.result)
    }

    @Test
    fun `echoes of slow writes do not undo newer changes`() = test {
        type("Тошкент")
        val gate = CompletableDeferred<Unit>()
        repository.gate = gate
        vm.setTarget(Script.LAT)
        advanceUntilIdle()
        assertEquals("Toshkent", vm.state.value.result)
        repository.stored.value = UserSettings(target = Script.NEW) // stale value arrives while the write waits
        advanceUntilIdle()
        assertEquals(Script.LAT, vm.settings.value?.target)
        gate.complete(Unit)
        advanceUntilIdle()
        assertEquals(Script.LAT, repository.stored.value.target)
        assertEquals(Script.LAT, vm.settings.value?.target)
        assertEquals("Toshkent", vm.state.value.result)
    }

    // ------------------------------------------------------------------ files

    private fun file(uri: String, name: String?, text: String, mime: String? = "text/plain", charset: Charset = Charsets.UTF_8) {
        documents.documents[uri] = SharedDocument(name, mime, text.toByteArray(charset))
    }

    @Test
    fun `a shared file is converted and saved under the target's name`() = test {
        file("content://in", "hujjat.txt", "Тошкент шаҳри\nЎзбекистон")
        vm.openFile("content://in", null)
        assertEquals(FilePhase.LOADING, vm.file.value?.phase)
        advanceUntilIdle()
        val f = vm.file.value!!
        assertEquals(FilePhase.READY, f.phase)
        assertEquals("hujjat.txt", f.name)
        assertEquals(Script.CYR, f.detected)
        assertEquals(Script.NEW, f.to)
        assertEquals("hujjat-new.txt", f.outputName)
        assertEquals("Toşkent şahri\nÖzbekiston", f.preview)
        assertFalse(f.truncated)
        assertFalse(f.legacyEncoding)

        vm.setFileTarget(Script.LAT)
        advanceUntilIdle()
        assertEquals("hujjat-lat.txt", vm.file.value?.outputName)
        assertEquals("Toshkent shahri\nOʻzbekiston", vm.file.value?.preview)

        vm.saveFile("content://out")
        advanceUntilIdle()
        assertEquals(FilePhase.SAVED, vm.file.value?.phase)
        assertEquals("saved.txt", vm.file.value?.savedName)
        assertArrayEquals("Toshkent shahri\nOʻzbekiston".toByteArray(Charsets.UTF_8), documents.written["content://out"])

        vm.closeFile()
        assertNull(vm.file.value)
    }

    @Test
    fun `a file already in the target goes to the other alphabet`() = test {
        file("content://in", "eslatma.md", "# Özbekiston\n")
        vm.openFile("content://in", "text/markdown")
        advanceUntilIdle()
        assertEquals(Script.CYR, vm.file.value?.to)
        assertEquals("eslatma-cyr.md", vm.file.value?.outputName)
        assertEquals("# Ўзбекистон\n", vm.file.value?.preview)
    }

    @Test
    fun `byte order mark and utf-16 are kept, windows-1251 becomes utf-8`() = test {
        val bom = byteArrayOf(0xEF.toByte(), 0xBB.toByte(), 0xBF.toByte())
        documents.documents["content://bom"] = SharedDocument("a.csv", "text/csv", bom + "Тошкент".toByteArray())
        vm.openFile("content://bom", null)
        advanceUntilIdle()
        vm.saveFile("content://bom-out")
        advanceUntilIdle()
        assertArrayEquals(bom + "Toşkent".toByteArray(), documents.written["content://bom-out"])

        file("content://legacy", "eski.txt", "Тошкент", charset = Charset.forName("windows-1251"))
        vm.openFile("content://legacy", null)
        advanceUntilIdle()
        assertTrue(vm.file.value!!.legacyEncoding)
        vm.saveFile("content://legacy-out")
        advanceUntilIdle()
        assertArrayEquals("Toşkent".toByteArray(Charsets.UTF_8), documents.written["content://legacy-out"])
    }

    @Test
    fun `long files show a preview`() = test {
        file("content://in", "katta.srt", "Салом ".repeat(1000))
        vm.openFile("content://in", null)
        advanceUntilIdle()
        val f = vm.file.value!!
        assertTrue(f.truncated)
        assertEquals(ConverterViewModel.PREVIEW_CHARS, f.preview.length)
        assertEquals(TextStats(6000, 1000), f.resultStats)
    }

    @Test
    fun `unreadable, too large and unsupported files fail with a reason`() = test {
        vm.openFile("content://missing", null)
        advanceUntilIdle()
        assertEquals(FileState(phase = FilePhase.FAILED, error = FileError.READ), vm.file.value)

        documents.documents["content://big"] = SharedDocument("big.txt", "text/plain", ByteArray(11 * 1024 * 1024))
        vm.openFile("content://big", null)
        advanceUntilIdle()
        assertEquals(FileError.TOO_LARGE, vm.file.value?.error)

        file("content://html", "page.html", "<p>Salom</p>", mime = "text/html")
        vm.openFile("content://html", "text/plain")
        advanceUntilIdle()
        assertEquals(FileError.TYPE, vm.file.value?.error)

        documents.readError = SecurityException("permission revoked")
        vm.openFile("content://html", null)
        advanceUntilIdle()
        assertEquals(FileError.READ, vm.file.value?.error)
    }

    @Test
    fun `a failed save can be retried`() = test {
        file("content://in", "a.txt", "Салом")
        vm.openFile("content://in", null)
        advanceUntilIdle()
        documents.writeError = IOException("disk full")
        vm.saveFile("content://out")
        advanceUntilIdle()
        assertEquals(FilePhase.READY, vm.file.value?.phase)
        assertEquals(FileError.SAVE, vm.file.value?.error)
        documents.writeError = null
        vm.saveFile("content://out")
        advanceUntilIdle()
        assertEquals(FilePhase.SAVED, vm.file.value?.phase)
        assertNull(vm.file.value?.error)
    }

    @Test
    fun `a file shared before the settings were read uses them once they are`() = runTest(dispatcher) {
        repository.stored.value = UserSettings(target = Script.LAT)
        file("content://in", "a.txt", "Тошкент")
        vm.openFile("content://in", null)
        advanceUntilIdle()
        assertEquals(Script.LAT, vm.file.value?.to)
        assertEquals("Toshkent", vm.file.value?.preview)
    }
}
