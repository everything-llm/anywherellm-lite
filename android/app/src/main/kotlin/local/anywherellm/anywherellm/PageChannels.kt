package local.anywherellm.anywherellm

import android.webkit.WebSettings
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.webviewflutter.WebViewFlutterAndroidExternalApi

/**
 * The channels a page in the app's web view posts to, over `anywherellm/pages`. `listen`
 * (`{view, names, origin}`) gives the web view the plugin knows as `view` an object of each of
 * `names`, in frames of `origin` only, and hands what its main frame posts back as `message`
 * (`{view, name, message}`); it answers false where the device's web view cannot, and the page
 * then has no channel. The plugin's own `addJavaScriptChannel` gives every frame of every origin
 * the object and never says which posted, so a frame the page embeds could speak as the page.
 * `noCache` (`{view}`) switches the web view's HTTP cache off, for a page that holds a secret; it
 * answers false where the web view is not found.
 */
class PageChannels : FlutterPlugin {
    private var binding: FlutterPlugin.FlutterPluginBinding? = null
    private var channel: MethodChannel? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        this.binding = binding
        channel = MethodChannel(binding.binaryMessenger, CHANNEL).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "listen" -> {
                        val args = call.arguments as Map<*, *>
                        result.success(
                            listen(
                                (args["view"] as Number).toLong(),
                                (args["names"] as List<*>).map { it as String },
                                args["origin"] as String,
                            ),
                        )
                    }
                    "noCache" -> {
                        val args = call.arguments as Map<*, *>
                        result.success(noCache((args["view"] as Number).toLong()))
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        this.binding = null
    }

    /** Switches web view [view]'s HTTP cache off; false when it is not found. */
    private fun noCache(view: Long): Boolean {
        val web = binding?.let { WebViewFlutterAndroidExternalApi.getWebView(it, view) }
            ?: return false
        web.settings.cacheMode = WebSettings.LOAD_NO_CACHE
        return true
    }

    /** Gives web view [view] an object of each of [names] in frames of [origin]; false where it cannot. */
    private fun listen(view: Long, names: List<String>, origin: String): Boolean {
        if (!WebViewFeature.isFeatureSupported(WebViewFeature.WEB_MESSAGE_LISTENER)) return false
        val web = binding?.let { WebViewFlutterAndroidExternalApi.getWebView(it, view) }
            ?: return false
        return try {
            for (name in names) {
                WebViewCompat.addWebMessageListener(web, name, setOf(origin)) { _, message, _, isMainFrame, _ ->
                    val text = message.data
                    if (isMainFrame && text != null) {
                        channel?.invokeMethod(
                            "message",
                            mapOf("view" to view, "name" to name, "message" to text),
                        )
                    }
                }
            }
            true
        } catch (_: IllegalArgumentException) {
            // An origin the web view cannot take as a rule, such as one with a path.
            false
        }
    }

    private companion object {
        const val CHANNEL = "anywherellm/pages"
    }
}
