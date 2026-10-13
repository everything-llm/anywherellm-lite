package local.anywherellm.anywherellm

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import org.json.JSONException
import org.json.JSONObject
import java.util.concurrent.atomic.AtomicInteger

/**
 * A push shown as a notification. Its payload is `{title, body, data}`, the shape of
 * AnythingLLM's pushes and the apps server's; each source has its own channel, so Android's
 * settings can quiet one. Tapping it opens [MainActivity] with the source and the payload,
 * which the Dart side reads for what to open.
 */
object PushNotes {
    const val ACTION_TAP = "local.anywherellm.PUSH_TAP"
    const val EXTRA_INSTANCE = "local.anywherellm.push.instance"
    const val EXTRA_PAYLOAD = "local.anywherellm.push.payload"

    /**
     * Each source's channel name, by its UnifiedPush instance: a copy of `PushSource` in
     * `lib/core/push.dart`, since this runs with no Flutter engine.
     */
    private val channels = mapOf("anythingllm" to "Scheduled jobs", "apps" to "Apps")

    /** The channels made in this process; Android keeps them, so once each is enough. */
    private val made = mutableSetOf<String>()

    /** The accent of the app's icon. */
    private const val COLOR = 0xFF4B5DC3.toInt()

    private val ids = AtomicInteger((System.currentTimeMillis() / 1000).toInt())

    fun show(context: Context, instance: String, content: ByteArray) {
        val payload = String(content, Charsets.UTF_8)
        val json = try {
            JSONObject(payload)
        } catch (_: JSONException) {
            null
        }
        val channel = channels[instance] ?: "Notifications"
        val title = json?.optString("title").orEmpty().ifEmpty { channel }
        val body = json?.optString("body").orEmpty()
        val manager = context.getSystemService(NotificationManager::class.java)
        val id = ids.incrementAndGet()
        val tap = Intent(context, MainActivity::class.java)
            .setAction(ACTION_TAP)
            .putExtra(EXTRA_INSTANCE, instance)
            .putExtra(EXTRA_PAYLOAD, payload)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        val open = PendingIntent.getActivity(
            context,
            id,
            tap,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            if (made.add(instance)) {
                manager.createNotificationChannel(
                    NotificationChannel(instance, channel, NotificationManager.IMPORTANCE_HIGH),
                )
            }
            Notification.Builder(context, instance)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context).setPriority(Notification.PRIORITY_HIGH)
        }
        val note = builder
            .setSmallIcon(R.drawable.ic_notification)
            .setColor(COLOR)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(Notification.BigTextStyle().bigText(body))
            .setAutoCancel(true)
            .setContentIntent(open)
            .build()
        // Without the permission Android drops it, as the person asked.
        manager.notify(id, note)
    }
}
