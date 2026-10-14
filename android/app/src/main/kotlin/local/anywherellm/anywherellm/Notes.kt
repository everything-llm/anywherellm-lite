package local.anywherellm.anywherellm

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import java.util.concurrent.atomic.AtomicInteger

/**
 * The app's notifications: [ongoing], which is [AnswerService]'s, and [ready], the app's own
 * word that an answer is ready. Tapping the second opens [MainActivity] with the chat's slug and
 * thread, which the Dart side opens.
 */
object Notes {
    const val ACTION_TAP = "local.anywherellm.NOTE_TAP"
    const val EXTRA_SLUG = "local.anywherellm.note.slug"
    const val EXTRA_THREAD = "local.anywherellm.note.thread"

    /** The channels earlier versions showed notifications on, which [retire] deletes. */
    private val RETIRED = listOf("anythingllm", "apps")

    /** Deletes the channels the app no longer posts to, so Android's settings stop listing them. */
    fun retire(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(NotificationManager::class.java)
        RETIRED.forEach(manager::deleteNotificationChannel)
    }

    /** The channel of [AnswerService]'s ongoing notification, quiet. */
    private const val ANSWERING = "answering"

    /** The channel of an answer that is ready. */
    private const val ANSWERS = "answers"

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

    /** Shows that the answer in chat [thread] of workspace [slug] is ready: [title] over [body]. */
    fun ready(context: Context, title: String, body: String, slug: String, thread: String) {
        val id = ids.incrementAndGet()
        val tap = Intent(context, MainActivity::class.java)
            .setAction(ACTION_TAP)
            .putExtra(EXTRA_SLUG, slug)
            .putExtra(EXTRA_THREAD, thread)
        val note = builder(context, ANSWERS, "Answers ready", high = true, opens = tap, request = id)
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
