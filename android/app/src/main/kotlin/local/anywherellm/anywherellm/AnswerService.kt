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
 */
class AnswerService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val note = PushNotes.ongoing(this, intent?.getStringExtra(EXTRA_TEXT) ?: "Answering")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(PushNotes.ONGOING_ID, note, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
        } else {
            startForeground(PushNotes.ONGOING_ID, note)
        }
        return START_NOT_STICKY
    }

    /** Android 15 ends a data sync after 6 hours a day: the answer is let go of then. */
    override fun onTimeout(startId: Int, fgsType: Int) = stopSelf()

    override fun onDestroy() {
        held = false
        super.onDestroy()
    }

    companion object {
        private const val EXTRA_TEXT = "local.anywherellm.answering"

        /** Whether the service runs, so a new text only redraws its notification. */
        @Volatile
        private var held = false

        /** Holds the app with an ongoing notification saying [text], or lets it go when null. */
        fun hold(context: Context, text: String?) {
            val intent = Intent(context, AnswerService::class.java)
            if (text == null) {
                held = false
                context.stopService(intent)
                return
            }
            if (held) {
                context.getSystemService(NotificationManager::class.java)
                    .notify(PushNotes.ONGOING_ID, PushNotes.ongoing(context, text))
                return
            }
            try {
                intent.putExtra(EXTRA_TEXT, text)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
                held = true
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
