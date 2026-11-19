package com.lxi.kanade

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
import android.util.Log

/**
 * 下载期间的前台服务和进度通知，跑在播放进程里，由 Rust 经 [MediaStoreBridge.notifyDownloads] 控制。
 * 点通知打开下载管理页。
 */
class DownloadService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        running = true
    }

    override fun onDestroy() {
        running = false
        super.onDestroy()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val notification = build(this, intent?.getIntExtra(EXTRA_DONE, 0) ?: 0, intent?.getIntExtra(EXTRA_TOTAL, 0) ?: 0)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
        } else {
            startForeground(ID, notification)
        }
        return START_NOT_STICKY
    }

    companion object {
        const val ACTION_OPEN = "com.lxi.kanade.OPEN_DOWNLOADS"
        private const val EXTRA_DONE = "done"
        private const val EXTRA_TOTAL = "total"
        private const val CHANNEL = "com.lxi.kanade.download"
        private const val ID = 3

        /** 只在主线程读写。 */
        private var running = false

        fun show(context: Context, done: Int, total: Int) {
            if (running) {
                context.getSystemService(NotificationManager::class.java).notify(ID, build(context, done, total))
                return
            }
            try {
                val intent = Intent(context, DownloadService::class.java)
                    .putExtra(EXTRA_DONE, done)
                    .putExtra(EXTRA_TOTAL, total)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
            } catch (e: Exception) {
                // 在后台时系统不让开前台服务，下载照常进行，只是没有通知
                Log.w("DownloadService", "start failed", e)
            }
        }

        fun stop(context: Context) {
            if (running) context.stopService(Intent(context, DownloadService::class.java))
        }

        private fun build(context: Context, done: Int, total: Int): Notification {
            val manager = context.getSystemService(NotificationManager::class.java)
            val title = context.getString(R.string.download_progress, done, total)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                manager.createNotificationChannel(
                    NotificationChannel(
                        CHANNEL,
                        context.getString(R.string.download_channel),
                        NotificationManager.IMPORTANCE_LOW,
                    ),
                )
            }
            val open = PendingIntent.getActivity(
                context,
                0,
                Intent(context, MainActivity::class.java)
                    .setAction(ACTION_OPEN)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
            @Suppress("DEPRECATION")
            val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Notification.Builder(context, CHANNEL)
            } else {
                Notification.Builder(context)
            }
            return builder
                .setSmallIcon(android.R.drawable.stat_sys_download)
                .setContentTitle(title)
                .setProgress(total, done, false)
                .setContentIntent(open)
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .build()
        }
    }
}
