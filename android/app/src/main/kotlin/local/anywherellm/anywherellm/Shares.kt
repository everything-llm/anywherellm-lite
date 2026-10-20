package local.anywherellm.anywherellm

import android.content.ContentResolver
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.OpenableColumns
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.InputStream
import java.util.concurrent.Executors

/**
 * What other apps share with the app, over the `anywherellm/shares` channel: `launchShare`
 * answers the share that started the activity, once, `share` sends each one that reaches it
 * while it runs, and `read` answers a shared file's bytes by its id. A share is `{text}`, a
 * shared text or an `anywherellm:` link opened in the app, or `{file, name, size}`, a file
 * another app's provider serves, read through the [ContentResolver] only when it is used and
 * never written to a file, so the name the sharing app gives is only ever shown. A file by a
 * `file:` path, or one this app's own providers serve, is refused, so a share cannot hand over
 * the app's own files. Every call to another app's provider runs on [reader], in the order the
 * shares came, never on the main thread.
 */
class Shares(private val context: Context, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, CHANNEL)
    private val reader = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    // Touched on [reader] only.
    private val files = mutableListOf<Uri>()
    private var launchShare: Map<String, Any?>? = null

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "launchShare" -> reader.execute {
                    val share = launchShare.also { launchShare = null }
                    main.post { result.success(share) }
                }
                "read" -> {
                    val id = call.argument<Int>("id") ?: -1
                    reader.execute {
                        val bytes = runCatching { open(files[id]) { it.readBytes() } }.getOrNull()
                        main.post {
                            if (bytes == null) {
                                result.error("unreadable", "The shared file could not be read.", null)
                            } else {
                                result.success(bytes)
                            }
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    /** Keeps the share [intent], which started the activity, for `launchShare`. */
    fun launch(intent: Intent?) {
        reader.execute { launchShare = take(intent) }
    }

    /** Sends the share [intent], which reached the running activity, as `share`. */
    fun arrived(intent: Intent) {
        reader.execute { take(intent)?.let { main.post { channel.invokeMethod("share", it) } } }
    }

    /** Stops [reader], as the engine goes. */
    fun close() {
        reader.shutdown()
    }

    /** The share [intent] holds, taken out of it so it is handed over once; null for none. */
    private fun take(intent: Intent?): Map<String, Any?>? = when (intent?.action) {
        Intent.ACTION_SEND -> {
            val stream = stream(intent)
            val text = intent.getCharSequenceExtra(Intent.EXTRA_TEXT)
            intent.removeExtra(Intent.EXTRA_STREAM)
            intent.removeExtra(Intent.EXTRA_TEXT)
            stream?.let(::file) ?: text?.let { mapOf("text" to "$it") }
        }
        Intent.ACTION_VIEW -> intent.data
            ?.takeIf { it.scheme == "anywherellm" }
            ?.also { intent.data = null }
            ?.let { mapOf("text" to "$it") }
        else -> null
    }

    private fun stream(intent: Intent): Uri? = runCatching {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
        }
    }.getOrNull()

    /**
     * The file at [uri] as a share, kept by its id, with the name and size its provider gives, or
     * else the size its bytes count; null for one the app does not take.
     */
    private fun file(uri: Uri): Map<String, Any?>? {
        if (uri.scheme != ContentResolver.SCHEME_CONTENT) return null
        val authority = uri.authority ?: return null
        @Suppress("DEPRECATION")
        val provider = context.packageManager.resolveContentProvider(authority, 0)
        if (provider?.packageName == context.packageName) return null
        var name: String? = null
        var size: Long? = null
        runCatching {
            val columns = arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE)
            context.contentResolver.query(uri, columns, null, null, null)?.use { row ->
                if (!row.moveToFirst()) return@use
                val named = row.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (named >= 0 && !row.isNull(named)) name = row.getString(named)
                val sized = row.getColumnIndex(OpenableColumns.SIZE)
                if (sized >= 0 && !row.isNull(sized)) size = row.getLong(sized)
            }
        }
        // Counted, not kept: the bytes are read again only when the file is used.
        val counted = size ?: runCatching { open(uri, ::count) }.getOrDefault(0L)
        files += uri
        return mapOf("file" to files.lastIndex, "name" to (name ?: uri.lastPathSegment), "size" to counted)
    }

    private fun <T> open(uri: Uri, use: (InputStream) -> T): T =
        context.contentResolver.openInputStream(uri)?.use(use) ?: error("No stream for $uri")

    /** How many bytes [stream] holds, read through and dropped. */
    private fun count(stream: InputStream): Long {
        val buffer = ByteArray(64 * 1024)
        var total = 0L
        while (true) {
            val read = stream.read(buffer)
            if (read < 0) return total
            total += read
        }
    }

    private companion object {
        const val CHANNEL = "anywherellm/shares"
    }
}
