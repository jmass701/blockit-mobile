package com.blockit.mobile

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

/**
 * EngineForegroundService — the persistent foreground service that keeps the app
 * process (and therefore the Dart block engine's periodic loop, plus the native
 * enforcement services) alive against Android's aggressive background killing.
 *
 * This is the mobile equivalent of BlockIT's always-running elevated tray
 * process on Windows. It shows an ongoing notification (required for a
 * foreground service) and is restarted on boot by BootReceiver, mirroring the
 * Windows ONLOGON scheduled task.
 *
 * It doesn't do the blocking itself — the AccessibilityService (apps) and
 * VpnService (sites) do that, reading the JSON state directly. This service just
 * guarantees they and the Dart engine stay resident.
 */
class EngineForegroundService : Service() {

    override fun onCreate() {
        super.onCreate()
        // The SPECIAL_USE foreground-service type constant exists from API 34;
        // pass it there. On older releases the plain startForeground is fine.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(
                NOTIFICATION_ID,
                buildNotification(),
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
            )
        } else {
            startForeground(NOTIFICATION_ID, buildNotification())
        }
        isRunning = true
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        isRunning = true
        // START_STICKY: Android should recreate us if it kills the process, so
        // enforcement resumes without user intervention.
        return START_STICKY
    }

    override fun onDestroy() {
        isRunning = false
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun buildNotification(): Notification {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "BlockIT protection",
                NotificationManager.IMPORTANCE_LOW
            ).apply { description = "Keeps app & website blocking active." }
            nm.createNotificationChannel(channel)
        }

        val openIntent = Intent(this, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M)
            PendingIntent.FLAG_IMMUTABLE else 0
        val pending = PendingIntent.getActivity(this, 0, openIntent, flags)

        return Notification.Builder(this, CHANNEL_ID)
            .setContentTitle("BlockIT is protecting you")
            .setContentText("App & website blocking is active.")
            .setSmallIcon(android.R.drawable.ic_lock_lock)
            .setContentIntent(pending)
            .setOngoing(true)
            .build()
    }

    companion object {
        private const val CHANNEL_ID = "blockit_engine"
        private const val NOTIFICATION_ID = 1001

        @Volatile
        var isRunning: Boolean = false
            private set

        fun start(context: Context) {
            val intent = Intent(context, EngineForegroundService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, EngineForegroundService::class.java))
        }
    }
}
