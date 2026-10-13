package local.anywherellm.anywherellm

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * The app. Over the `anywherellm/push` channel it asks for the notification permission and
 * hands over each notification tapped: `launchTap` answers the one that started the activity,
 * once, and `tap` sends one tapped while it runs. Over `anywherellm/background` it holds the
 * app while an answer runs ([AnswerService]), says an answer is ready, and leaves without
 * finishing, so the Flutter engine and an answer it reads go on.
 */
class MainActivity : FlutterActivity() {
    private var push: MethodChannel? = null
    private var launchTap: Map<String, String>? = null
    private var asking: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        PushNotes.retire(this)
        launchTap = takeTap(intent)
        push = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "launchTap" -> {
                        result.success(launchTap)
                        launchTap = null
                    }
                    "askPermission" -> askPermission(result)
                    else -> result.notImplemented()
                }
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BACKGROUND)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "hold" -> AnswerService.hold(applicationContext, call.arguments as String?)
                    "ready" -> PushNotes.show(
                        applicationContext,
                        "answers",
                        (call.arguments as String).toByteArray(Charsets.UTF_8),
                    )
                    "leave" -> moveTaskToBack(true)
                    else -> return@setMethodCallHandler result.notImplemented()
                }
                result.success(null)
            }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        takeTap(intent)?.let { push?.invokeMethod("tap", it) }
    }

    /** The tapped notification [intent] carries, taken out so it is handed over once. */
    private fun takeTap(intent: Intent?): Map<String, String>? {
        if (intent?.action != PushNotes.ACTION_TAP) return null
        val instance = intent.getStringExtra(PushNotes.EXTRA_INSTANCE) ?: return null
        val payload = intent.getStringExtra(PushNotes.EXTRA_PAYLOAD) ?: return null
        intent.removeExtra(PushNotes.EXTRA_INSTANCE)
        intent.removeExtra(PushNotes.EXTRA_PAYLOAD)
        return mapOf("instance" to instance, "payload" to payload)
    }

    private fun askPermission(result: MethodChannel.Result) {
        val permission = Manifest.permission.POST_NOTIFICATIONS
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED
        ) {
            return result.success(true)
        }
        asking?.success(false)
        asking = result
        requestPermissions(arrayOf(permission), ASK_NOTIFICATIONS)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != ASK_NOTIFICATIONS) return
        asking?.success(grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED)
        asking = null
    }

    private companion object {
        const val CHANNEL = "anywherellm/push"
        const val BACKGROUND = "anywherellm/background"
        const val ASK_NOTIFICATIONS = 0x6e6f
    }
}
