package local.anywherellm.anywherellm

import android.webkit.WebView
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
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
 * `forget` (`{view}`) blanks that web view, so its page's scripts stop, and empties the HTTP cache
 * the app's web views share, for a page that holds a secret as it closes. `edgeless` (`{view}`)
 * keeps the window's insets from that web view: it shows in a sheet clear of the system bars, so
 * a page's `env(safe-area-inset-*)` is 0 there, as in a browser tab, not the status bar's height.
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
                    "edgeless" -> {
                        val args = call.arguments as Map<*, *>
                        edgeless((args["view"] as Number).toLong())
                        result.success(null)
                    }
                    "forget" -> {
                        val args = call.arguments as Map<*, *>
                        forget((args["view"] as Number).toLong())
                        result.success(null)
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

    /**
     * Blanks web view [view], which lives on after its widget until it is collected, and empties
     * the HTTP cache every web view of the app shares, through a new web view when [view] is gone.
     */
    private fun forget(view: Long) {
        val binding = binding ?: return
        val web = WebViewFlutterAndroidExternalApi.getWebView(binding, view)
        if (web != null) {
            web.stopLoading()
            web.loadUrl("about:blank")
            web.clearCache(true)
        } else {
            WebView(binding.applicationContext).apply {
                clearCache(true)
                destroy()
            }
        }
    }

    /** Hands web view [view] no window insets, now and whenever the window's change. */
    private fun edgeless(view: Long) {
        val web = binding?.let { WebViewFlutterAndroidExternalApi.getWebView(it, view) } ?: return
        ViewCompat.setOnApplyWindowInsetsListener(web) { v, _ ->
            ViewCompat.onApplyWindowInsets(v, WindowInsetsCompat.CONSUMED)
        }
        ViewCompat.requestApplyInsets(web)
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
