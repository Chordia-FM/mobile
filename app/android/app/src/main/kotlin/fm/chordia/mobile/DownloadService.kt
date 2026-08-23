package fm.chordia.mobile

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

/**
 * Keeps a batch of downloads running while the screen is off.
 *
 * Android stops an app's work shortly after it leaves the foreground, and a user who taps "download
 * this album" and pockets their phone reasonably expects to come back to a downloaded album. The
 * work itself stays in Dart — this only holds the process up while it happens, and publishes the
 * notification Android requires in exchange.
 *
 * Nothing depends on this for correctness. The queue is in SQLite, so a batch that is cut short
 * resumes from the bytes already written on the next launch; without this service that simply
 * happens more often.
 */
class DownloadService : Service() {
    companion object {
        private const val CHANNEL_ID = "fm.chordia.mobile.downloads"
        private const val NOTIFICATION_ID = 0x63_64 // 'cd'

        const val EXTRA_DONE = "done"
        const val EXTRA_TOTAL = "total"
        const val ACTION_UPDATE = "fm.chordia.mobile.downloads.UPDATE"
        const val ACTION_STOP = "fm.chordia.mobile.downloads.STOP"

        fun update(context: Context, done: Int, total: Int) {
            val intent = Intent(context, DownloadService::class.java).apply {
                action = ACTION_UPDATE
                putExtra(EXTRA_DONE, done)
                putExtra(EXTRA_TOTAL, total)
            }
            context.startForegroundService(intent)
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, DownloadService::class.java))
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopSelf()
            return START_NOT_STICKY
        }

        val done = intent?.getIntExtra(EXTRA_DONE, 0) ?: 0
        val total = intent?.getIntExtra(EXTRA_TOTAL, 0) ?: 0

        // startForeground has to be called promptly after startForegroundService or the system
        // kills the process with a ForegroundServiceDidNotStartInTimeException.
        val notification = buildNotification(done, total)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }

        // Not sticky: a restart with no intent would show a progress notification for a batch that
        // is no longer running. Dart restarts the service when it resumes the queue.
        return START_NOT_STICKY
    }

    private fun buildNotification(done: Int, total: Int): Notification {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (manager.getNotificationChannel(CHANNEL_ID) == null) {
            manager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    getString(R.string.download_channel_name),
                    // Low: a progress bar the user asked for should not make a sound.
                    NotificationManager.IMPORTANCE_LOW,
                ).apply { setShowBadge(false) },
            )
        }

        val open = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE,
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(getString(R.string.download_notification_title))
            .setContentText(
                getString(R.string.download_notification_progress, done, total),
            )
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setProgress(total.coerceAtLeast(1), done, total <= 0)
            .setOngoing(true)
            .setContentIntent(open)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .build()
    }
}
