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
 * The app's notifications. A push, or the app's own word that an answer is ready, is drawn
 * from a payload `{title, body, data}`, the shape of AnythingLLM's pushes and the apps
 * server's; each kind has its own channel, so Android's settings can quiet one. Tapping it
 * opens [MainActivity] with the channel and the payload, which the Dart side reads for what to
 * open. [ongoing] is [AnswerService]'s.
 */
object PushNotes {
    const val ACTION_TAP = "local.anywherellm.PUSH_TAP"
    const val EXTRA_INSTANCE = "local.anywherellm.push.instance"
    const val EXTRA_PAYLOAD = "local.anywherellm.push.payload"

    /**
     * Each source's channel name, by its UnifiedPush instance: a copy of `PushSource` in
     * `lib/core/push.dart`, since this runs with no Flutter engine.
     */
    private val channels = mapOf(
        "anythingllm" to "Scheduled jobs",
        "apps" to "Apps",
        "answers" to "Answers ready",
    )

    /** The channel of [AnswerService]'s ongoing notification, quiet. */
    private const val ANSWERING = "answering"

    const val ONGOING_ID = 1

    /** The channels made in this process; Android keeps them, so once each is enough. */
    private val made = mutableSetOf<String>()

    /** The accent of the app's icon. */
    private const val COLOR = 0xFF4B5DC3.toInt()

    private val ids = AtomicInteger((System.currentTimeMillis() / 1000).toInt() and 0x3fffffff)

    /** What [AnswerService] shows while it holds the app: [text], and a tap opens the app. */
    fun ongoing(context: Context, text: String): Notification {
        val app = Intent(context, MainActivity::class.java)
        return builder(context, ANSWERING, "Answering", high = false, opens = app, request = 0)
            .setContentTitle(text)
            .setOngoing(true)
            .build()
    }

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
        val id = ids.incrementAndGet()
        val tap = Intent(context, MainActivity::class.java)
            .setAction(ACTION_TAP)
            .putExtra(EXTRA_INSTANCE, instance)
            .putExtra(EXTRA_PAYLOAD, payload)
        val note = builder(context, instance, channel, high = true, opens = tap, request = id)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(Notification.BigTextStyle().bigText(body))
            .setAutoCancel(true)
            .build()
        // Without the permission Android drops it, as the person asked.
        context.getSystemService(NotificationManager::class.java).notify(id, note)
    }

    /**
     * A notification on [channel], named [name] in Android's settings and made the first time,
     * urgent when [high], in the app's icon and accent, which opens [opens]: [request] tells
     * apart the taps of notifications shown at once.
     */
    private fun builder(
        context: Context,
        channel: String,
        name: String,
        high: Boolean,
        opens: Intent,
        request: Int,
    ): Notification.Builder {
        val open = PendingIntent.getActivity(
            context,
            request,
            opens.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            if (made.add(channel)) {
                val importance = if (high) {
                    NotificationManager.IMPORTANCE_HIGH
                } else {
                    NotificationManager.IMPORTANCE_LOW
                }
                context.getSystemService(NotificationManager::class.java)
                    .createNotificationChannel(NotificationChannel(channel, name, importance))
            }
            Notification.Builder(context, channel)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context)
                .setPriority(if (high) Notification.PRIORITY_HIGH else Notification.PRIORITY_LOW)
        }
        return builder
            .setSmallIcon(R.drawable.ic_notification)
            .setColor(COLOR)
            .setContentIntent(open)
    }
}
