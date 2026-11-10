package net.ohrtech.device.flutter

import net.ohrtech.device.OhrCertificates
import net.ohrtech.device.OhrException
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.ConcurrentHashMap
import javax.net.ssl.HttpsURLConnection
import javax.net.ssl.SSLSocketFactory

/**
 * HTTP through Android's own stack, with the app's client certificate and trusted CAs: the keys
 * live in the Android Keystore, which Dart's TLS can't use. Request and response bodies are whole.
 */
internal object Http {
    private class Entry(val factory: SSLSocketFactory, val madeAt: Long)

    private val factories = ConcurrentHashMap<String, Entry>()
    private const val KEEP_MS = 5 * 60_000L

    /** The certificates changed (a request or renewal): build the TLS context again. */
    fun forget() = factories.clear()

    /** The fleet's changes too (trusted CAs, bundles), from the first use; with an Agent before 1061, five minutes. */
    @Volatile
    private var watching: java.io.Closeable? = null

    private fun watch() {
        if (watching != null) return
        synchronized(this) {
            if (watching == null) {
                watching = try {
                    OhrCertificates.listen({ it.run() }) { forget() }
                } catch (e: OhrException) {
                    java.io.Closeable { }
                }
            }
        }
    }

    private fun factory(alias: String?): SSLSocketFactory {
        watch()
        val key = alias ?: ""
        val now = System.currentTimeMillis()
        factories[key]?.takeIf { now - it.madeAt < KEEP_MS }?.let { return it.factory }
        return OhrCertificates.sslContext(alias).socketFactory.also { factories[key] = Entry(it, now) }
    }

    fun send(r: HttpRequestData): HttpResponseData {
        val url = try {
            URL(r.url)
        } catch (e: Exception) {
            throw OhrException.InvalidConfig("url", e.message ?: "not a URL")
        }
        val c = url.openConnection() as HttpURLConnection
        try {
            if (c is HttpsURLConnection) c.sslSocketFactory = factory(r.alias)
            c.requestMethod = r.method
            c.instanceFollowRedirects = r.followRedirects
            c.connectTimeout = r.timeoutMs.toInt()
            c.readTimeout = r.timeoutMs.toInt()
            for ((k, v) in r.headers) c.setRequestProperty(k, v)
            r.body?.takeIf { it.isNotEmpty() }?.let { body ->
                c.doOutput = true
                c.setFixedLengthStreamingMode(body.size)
                c.outputStream.use { it.write(body) }
            }
            val status = c.responseCode
            val stream = if (status >= 400) c.errorStream else c.inputStream
            val body = stream?.use { it.readBytes() } ?: ByteArray(0)
            val headers = c.headerFields.filterKeys { it != null }.mapKeys { it.key.lowercase() }.mapValues { it.value.joinToString(", ") }
            return HttpResponseData(status.toLong(), c.responseMessage, headers, body, c.url.toString())
        } catch (e: IOException) {
            throw OhrException.Failed("HTTP ${r.method} ${r.url}: ${e.message ?: e}")
        } finally {
            c.disconnect()
        }
    }
}
