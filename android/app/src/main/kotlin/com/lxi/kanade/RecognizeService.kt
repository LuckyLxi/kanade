package com.lxi.kanade

import android.annotation.SuppressLint
import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioPlaybackCaptureConfiguration
import android.media.AudioRecord
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.Process
import androidx.annotation.RequiresApi
import kotlin.math.max

/**
 * 听歌识曲期间的前台服务：切到别的软件后系统才允许接着录音。
 * 录手机内声音时还持有录屏授权（[projection]），弹窗关掉、服务停止前一直复用，不再重复弹授权框。
 */
class RecognizeService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val title = intent?.getStringExtra(EXTRA_TITLE).orEmpty()
        val manager = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL, title, NotificationManager.IMPORTANCE_LOW),
            )
        }
        val open = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE,
        )
        @Suppress("DEPRECATION")
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL)
        } else {
            Notification.Builder(this)
        }
        val notification = builder
            .setSmallIcon(R.drawable.ic_bubble_mic)
            .setContentTitle(title)
            .setContentIntent(open)
            .setOngoing(true)
            .build()
        @Suppress("DEPRECATION")
        val grant = intent?.getParcelableExtra<Intent>(EXTRA_PROJECTION)
        // Android 14 起麦克风权限被收回、录屏授权失效时会抛 SecurityException，
        // 这里是系统回调，没人接住就会崩：当作没录成
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                var type = ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
                if (grant != null || projection != null) {
                    type = type or ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION
                }
                startForeground(ID, notification, type)
            } else {
                startForeground(ID, notification)
            }
            foreground = true
        } catch (_: Exception) {
            if (grant != null) {
                val ready = onProjection
                onProjection = null
                ready?.invoke(false)
            }
            reportStarted()
            // 之前已经在前台的接着跑，不丢掉已有的录屏授权
            if (!foreground) stopSelf()
            return START_NOT_STICKY
        }
        reportStarted()
        // 系统要求先以 mediaProjection 类型进入前台，才能拿录屏授权
        if (grant != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val ready = onProjection
            onProjection = null
            ready?.invoke(
                try {
                    val code = intent.getIntExtra(EXTRA_RESULT_CODE, Activity.RESULT_CANCELED)
                    projection = getSystemService(MediaProjectionManager::class.java)
                        .getMediaProjection(code, grant)
                        ?.apply {
                            registerCallback(
                                object : MediaProjection.Callback() {
                                    override fun onStop() {
                                        stopCapture()
                                        projection = null
                                    }
                                },
                                Handler(Looper.getMainLooper()),
                            )
                        }
                    projection != null
                } catch (_: Exception) {
                    false
                },
            )
        }
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        stopCapture()
        projection?.stop()
        projection = null
        // 不在这里回 onStarted：刚停又启动时，旧实例的销毁排在新实例启动前面，回了就把新的那次报成没起来
        foreground = false
        super.onDestroy()
    }

    /**
     * 在后台线程读系统内录的 16 位单声道 PCM；有的应用禁止被录，读到的是静音。
     * 建内录要先向系统注册截取规则，要一百多毫秒，放在主线程会卡住悬浮球的动画。
     */
    @RequiresApi(Build.VERSION_CODES.Q)
    private class PlaybackCapture(
        projection: MediaProjection,
        onData: (ByteArray) -> Unit,
        onError: () -> Unit,
    ) {
        @Volatile
        private var running = true

        init {
            Thread {
                val record = try {
                    build(projection).apply { startRecording() }
                } catch (_: Exception) {
                    if (running) onError()
                    return@Thread
                }
                val buffer = ByteArray(CHUNK)
                while (running) {
                    val n = record.read(buffer, 0, buffer.size)
                    if (n < 0) break
                    if (n > 0) onData(buffer.copyOf(n))
                }
                record.stop()
                record.release()
            }.start()
        }

        @SuppressLint("MissingPermission") // 录音前 Dart 侧已拿到麦克风权限
        private fun build(projection: MediaProjection) = AudioRecord.Builder()
            .setAudioFormat(
                AudioFormat.Builder()
                    .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                    .setSampleRate(SAMPLE_RATE)
                    .setChannelMask(AudioFormat.CHANNEL_IN_MONO)
                    .build(),
            )
            .setBufferSizeInBytes(
                max(
                    AudioRecord.getMinBufferSize(SAMPLE_RATE, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT),
                    CHUNK * 2,
                ),
            )
            .setAudioPlaybackCaptureConfig(
                AudioPlaybackCaptureConfiguration.Builder(projection)
                    .addMatchingUsage(AudioAttributes.USAGE_MEDIA)
                    .addMatchingUsage(AudioAttributes.USAGE_GAME)
                    .addMatchingUsage(AudioAttributes.USAGE_UNKNOWN)
                    .excludeUid(Process.myUid())
                    .build(),
            )
            .build()

        fun stop() {
            running = false
        }
    }

    companion object {
        const val EXTRA_TITLE = "title"
        const val EXTRA_RESULT_CODE = "resultCode"
        const val EXTRA_PROJECTION = "projection"
        const val SAMPLE_RATE = 16000
        private const val CHUNK = SAMPLE_RATE / 10 * 2 // 100 ms
        private const val CHANNEL = "com.lxi.kanade.recognize"
        private const val ID = 2

        /** 以下都只在主线程读写。 */
        var projection: MediaProjection? = null
            private set
        var onProjection: ((Boolean) -> Unit)? = null

        /** 等着知道服务进没进前台；系统收下启动请求不代表进得去。 */
        var onStarted: ((Boolean) -> Unit)? = null
        private var foreground = false
        private var capture: PlaybackCapture? = null

        private fun reportStarted() {
            val done = onStarted
            onStarted = null
            done?.invoke(foreground)
        }

        /** 没有录屏授权或系统低于 Android 10 时返回 false；之后建不起来在后台线程调 [onError]。 */
        fun startCapture(onData: (ByteArray) -> Unit, onError: () -> Unit): Boolean {
            stopCapture()
            val projection = projection ?: return false
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return false
            capture = PlaybackCapture(projection, onData, onError)
            return true
        }

        fun stopCapture() {
            capture?.stop()
            capture = null
        }
    }
}
