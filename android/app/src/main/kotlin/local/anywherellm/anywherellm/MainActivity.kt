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
 * ([AnswerService]), says an answer is ready, leaves without finishing, so the Flutter engine
 * and an answer it reads go on, and hands over each notification tapped: `launchTap` answers the
 * one that started the activity, once, and `tap` sends one tapped while it runs. Notifications
 * need a permission on Android 13 and later, which it asks for when an answer first runs.
 */
class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var launchTap: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        Notes.retire(this)
        launchTap = takeTap(intent)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BACKGROUND).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "launchTap" -> {
                        result.success(launchTap)
                        launchTap = null
                        return@setMethodCallHandler
                    }
                    "hold" -> {
                        askPermission()
                        AnswerService.hold(applicationContext, call.arguments as String?)
                    }
                    "ready" -> Notes.ready(applicationContext, call.arguments as String)
                    "leave" -> moveTaskToBack(true)
                    else -> return@setMethodCallHandler result.notImplemented()
                }
                result.success(null)
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        takeTap(intent)?.let { channel?.invokeMethod("tap", it) }
    }

    /** The tapped notification's payload that [intent] carries, taken out so it is handed over once. */
    private fun takeTap(intent: Intent?): String? {
        if (intent?.action != Notes.ACTION_TAP) return null
        val payload = intent.getStringExtra(Notes.EXTRA_PAYLOAD) ?: return null
        intent.removeExtra(Notes.EXTRA_PAYLOAD)
        return payload
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
        requestPermissions(arrayOf(permission), ASK_NOTIFICATIONS)
    }

    private var asked = false

    private companion object {
        const val BACKGROUND = "anywherellm/background"
        const val ASK_NOTIFICATIONS = 0x6e6f
    }
}
