package com.bernoulli.trailrunner.trail_runner

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder

/**
 * A minimal foreground service that keeps the app process alive while offline
 * map tiles are downloading.
 *
 * The download work itself runs on the Flutter main isolate; this service only
 * prevents Android from suspending or killing the process (and eases network
 * throttling) while the app is in the background. It is started when a download
 * begins and stopped when the last one finishes.
 */
class DownloadService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startForegroundNotification()
        return START_STICKY
    }

    private fun startForegroundNotification() {
        val channelId = "trail_runner_downloads"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager =
                getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (manager.getNotificationChannel(channelId) == null) {
                manager.createNotificationChannel(
                    NotificationChannel(
                        channelId,
                        "Offline map downloads",
                        NotificationManager.IMPORTANCE_LOW,
                    ),
                )
            }
        }

        val builder =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Notification.Builder(this, channelId)
            } else {
                @Suppress("DEPRECATION")
                Notification.Builder(this)
            }
        val notification =
            builder
                .setContentTitle("RunTiyul")
                .setContentText("Downloading offline maps")
                .setSmallIcon(android.R.drawable.stat_sys_download)
                .setOngoing(true)
                .build()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    override fun onDestroy() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
        super.onDestroy()
    }

    private companion object {
        const val NOTIFICATION_ID = 4711
    }
}
