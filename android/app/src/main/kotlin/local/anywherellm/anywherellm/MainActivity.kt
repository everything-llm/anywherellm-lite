package local.anywherellm.anywherellm

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * The app. Over the `anywherellm/background` channel it holds the app while an answer runs
 * ([AnswerService]), says an answer is ready or that a skill waits for the person (`asking`,
 * taken back by `asked`), leaves without finishing, so the Flutter engine and an answer it
 * reads go on, and hands over each notification tapped as `{slug, thread}`:
 * `launchTap` answers the one that started the activity, once, and `tap` sends one tapped while
 * it runs. Notifications need a permission on Android 13 and later, which it asks for when an
 * answer first runs.
 */
class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var launchTap: Map<String, String>? = null
    private var asked = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        Notes.retire(this)
        launchTap = takeTap(intent)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BACKGROUND).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "launchTap" -> result.success(launchTap.also { launchTap = null })
                    "hold" -> {
                        askPermission()
                        AnswerService.hold(applicationContext, call.arguments as String?)
                        result.success(null)
                    }
                    "ready" -> {
                        val note = call.arguments as Map<*, *>
                        Notes.ready(
                            applicationContext,
                            note["title"] as String,
                            note["body"] as String,
                            note["slug"] as String,
                            note["thread"] as String,
                        )
                        result.success(null)
                    }
                    "asking" -> {
                        val note = call.arguments as Map<*, *>
                        Notes.asking(
                            applicationContext,
                            note["title"] as String,
                            note["body"] as String,
                            note["slug"] as String,
                            note["thread"] as String,
                        )
                        result.success(null)
                    }
                    "asked" -> {
                        Notes.asked(applicationContext)
                        result.success(null)
                    }
                    "leave" -> {
                        moveTaskToBack(true)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        takeTap(intent)?.let { channel?.invokeMethod("tap", it) }
    }

    /** The tapped notification's chat that [intent] carries, taken out so it is handed over once. */
    private fun takeTap(intent: Intent?): Map<String, String>? {
        if (intent?.action != Notes.ACTION_TAP) return null
        val slug = intent.getStringExtra(Notes.EXTRA_SLUG) ?: return null
        val thread = intent.getStringExtra(Notes.EXTRA_THREAD) ?: return null
        intent.removeExtra(Notes.EXTRA_SLUG)
        intent.removeExtra(Notes.EXTRA_THREAD)
        return mapOf("slug" to slug, "thread" to thread)
    }

    /** Asks for the notification permission when it is missing, once per run of the activity. */
    private fun askPermission() {
        val permission = Manifest.permission.POST_NOTIFICATIONS
        if (asked || Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED
        ) {
            return
        }
        asked = true
        requestPermissions(arrayOf(permission), 0)
    }

    private companion object {
        const val BACKGROUND = "anywherellm/background"
    }
}
