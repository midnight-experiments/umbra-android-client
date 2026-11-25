// The round trip on Android (instrumentation test), the same as ios/Tests/PsClientTests/RoundTripTests.swift.
// Uses the UniFFI Kotlin bindings
// (`uniffi.ps_client`, copied into src/main/kotlin by scripts/test.sh) and libps_client.so in jniLibs. The emulator
// reaches the host's ps-server at 10.0.2.2; the instrumentation argument `server` overrides it.
package ps.client

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertArrayEquals
import org.junit.Test
import org.junit.runner.RunWith
import uniffi.ps_client.PsClient
import java.net.HttpURLConnection
import java.net.URL

private val BASE: String =
    InstrumentationRegistry.getArguments().getString("server") ?: "http://10.0.2.2:8787"

private fun http(path: String, body: ByteArray? = null): ByteArray {
    val c = URL(BASE + path).openConnection() as HttpURLConnection
    if (body != null) {
        c.requestMethod = "POST"; c.doOutput = true; c.outputStream.use { it.write(body) }
    }
    check(c.responseCode == 200) { "http ${c.responseCode} $path" }
    return c.inputStream.use { it.readBytes() }
}

private fun unhex(s: String) = ByteArray(s.length / 2) { s.substring(2 * it, 2 * it + 2).toInt(16).toByte() }

@RunWith(AndroidJUnit4::class)
class RoundTripTest {
    @Test
    fun roundTripEveryTable() {
        val tables = JSONArray(String(http("/tables")))
        for (i in 0 until tables.length()) {
            val t = tables.getJSONObject(i)
            val (name, rows, cols) = Triple(t.getString("name"), t.getInt("rows"), t.getInt("cols"))
            val masks = http("/t/$name/masks")
            var start = System.nanoTime()
            val client = PsClient(rows.toUInt(), cols.toUInt(), unhex(t.getString("seed")), unhex(t.getString("snapshot")), masks)
            val loadMs = (System.nanoTime() - start) / 1e6
            val q = mutableListOf<Double>(); val d = mutableListOf<Double>()
            var requestBytes = 0; var answerBytes = 0
            val n = 7
            for (k in 0 until n) {
                val row = (k * 7919 + 5) % rows
                start = System.nanoTime()
                val request = client.request(row.toUInt())
                val bytes = request.bytes()
                q += (System.nanoTime() - start) / 1e6
                val answer = http("/t/$name/answer", bytes)
                start = System.nanoTime()
                val decoded = client.decode(request, answer)
                d += (System.nanoTime() - start) / 1e6
                assertArrayEquals("$name row $row", http("/t/$name/row/$row"), decoded)
                requestBytes = bytes.size; answerBytes = answer.size
            }
            val report = JSONObject(mapOf(
                "platform" to "android-emulator", "table" to name, "match" to true, "requests" to n, "loadMs" to loadMs,
                "queryMsMedian" to q.sorted()[n / 2], "decodeMsMedian" to d.sorted()[n / 2], "masksBytes" to masks.size,
                "requestBytes" to requestBytes, "answerBytes" to answerBytes,
                "nativeHeapBytes" to android.os.Debug.getNativeHeapAllocatedSize(),
            ))
            http("/report", report.toString().toByteArray())
        }
    }
}
