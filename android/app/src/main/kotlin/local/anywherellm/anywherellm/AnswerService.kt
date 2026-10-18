package local.anywherellm.anywherellm

import android.app.ForegroundServiceStartNotAllowedException
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder

/**
 * Keeps the app running while an answer streams or is waited for, so Android neither ends it
 * nor cuts its connection when it goes out of sight: a foreground service with an ongoing
 * notification saying what it does.
 *
 * A service started with `startForegroundService` must reach `startForeground` before it stops,
 * or Android ends the app, so a let-go that comes first is carried out by [onStartCommand].
 */
class AnswerService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val note = Notes.ongoing(this, intent?.getStringExtra(EXTRA_TEXT) ?: "Answering")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(Notes.ONGOING_ID, note, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
        } else {
            startForeground(Notes.ONGOING_ID, note)
        }
        running = true
        // Let go of before it started, as when an answer ends at once.
        if (!wanted) stopSelf(startId)
        return START_NOT_STICKY
    }

    /** Android 15 ends a data sync after 6 hours a day: the answer is let go of then. */
    override fun onTimeout(startId: Int, fgsType: Int) = stopSelf()

    override fun onDestroy() {
        running = false
        super.onDestroy()
    }

    companion object {
        private const val EXTRA_TEXT = "local.anywherellm.answering"

        /** Whether the app asked to be held and has not let go since. */
        @Volatile
        private var wanted = false

        /** Whether the service is in the foreground, so a new text only redraws its notification
         * and a let-go can stop it. */
        @Volatile
        private var running = false

        /** Holds the app with an ongoing notification saying [text], or lets it go when null. */
        fun hold(context: Context, text: String?) {
            val intent = Intent(context, AnswerService::class.java)
            if (text == null) {
                wanted = false
                if (running) {
                    running = false
                    context.stopService(intent)
                }
                return
            }
            wanted = true
            if (running) {
                context.getSystemService(NotificationManager::class.java)
                    .notify(Notes.ONGOING_ID, Notes.ongoing(context, text))
                return
            }
            try {
                intent.putExtra(EXTRA_TEXT, text)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
            } catch (e: IllegalStateException) {
                // Out of sight already, where Android 12 and later refuse to start one
                // (ForegroundServiceStartNotAllowedException): the answer goes on while it can.
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
                    e !is ForegroundServiceStartNotAllowedException
                ) {
                    throw e
                }
            }
        }
    }
}
