package com.lxi.kanade

import android.content.Context
import android.content.Intent
import android.media.projection.MediaProjectionManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract
import android.provider.Settings
import androidx.core.content.FileProvider
import com.ryanheise.audioservice.AudioService
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : AudioServiceActivity() {
    private var bubble: RecognizeBubble? = null
    private var pendingCapture: MethodChannel.Result? = null
    private var captureTitle = ""
    private var downloads: MethodChannel? = null
    private var pendingFolder: MethodChannel.Result? = null
    /** 从下载通知冷启动，等 Dart 起来后来取。 */
    private var openDownloads = false

    override fun onCreate(savedInstanceState: Bundle?) {
        openDownloads = savedInstanceState == null && intent?.action == DownloadService.ACTION_OPEN
        super.onCreate(savedInstanceState)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        if (intent.action == DownloadService.ACTION_OPEN) downloads?.invokeMethod("open", null)
    }

    override fun provideFlutterEngine(context: Context): FlutterEngine? =
        if ((application as KanadeApplication).separateAndroidPlayback) null
        else super.provideFlutterEngine(context)

    override fun onStart() {
        super.onStart()
        FloatingLyrics.uiVisible(this, true)
    }

    override fun onStop() {
        FloatingLyrics.uiVisible(this, false)
        super.onStop()
    }

    override fun onDestroy() {
        bubble?.hide()
        stopService(Intent(this, RecognizeService::class.java))
        super.onDestroy()
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQUEST_FOLDER) {
            val tree = data?.data.takeIf { resultCode == RESULT_OK }
            if (tree != null) {
                contentResolver.takePersistableUriPermission(
                    tree,
                    Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
                )
                MediaStoreBridge.setTree(tree)
            }
            pendingFolder?.success(tree != null)
            pendingFolder = null
            return
        }
        if (requestCode != REQUEST_CAPTURE) return
        val result = pendingCapture ?: return
        pendingCapture = null
        if (resultCode != RESULT_OK || data == null) {
            result.success(false)
            return
        }
        RecognizeService.onProjection = { ok -> result.success(ok) }
        try {
            startForegroundService(
                Intent(this, RecognizeService::class.java)
                    .putExtra(RecognizeService.EXTRA_TITLE, captureTitle)
                    .putExtra(RecognizeService.EXTRA_RESULT_CODE, resultCode)
                    .putExtra(RecognizeService.EXTRA_PROJECTION, data),
            )
        } catch (_: Exception) {
            RecognizeService.onProjection = null
            result.success(false)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val recognize = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "kanade/recognize")
        val bubble = RecognizeBubble(applicationContext) { action ->
            if (action == "open") {
                // 有悬浮窗权限，系统允许从后台把自己切回前台
                startActivity(
                    Intent(this, MainActivity::class.java)
                        .addFlags(Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or Intent.FLAG_ACTIVITY_SINGLE_TOP),
                )
            } else {
                recognize.invokeMethod("action", action)
            }
        }
        this.bubble = bubble
        recognize.setMethodCallHandler { call, result ->
            when (call.method) {
                "canOverlay" -> result.success(Settings.canDrawOverlays(this))
                "openOverlaySettings" -> {
                    startActivity(
                        Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:$packageName")),
                    )
                    result.success(null)
                }
                // 服务真进了前台才回 true；回 false 时 Dart 下次回到前台再试。
                // 起不来只是切走后录不了音，界面里照常识曲
                "startService" -> {
                    RecognizeService.onStarted = { ok -> result.success(ok) }
                    try {
                        startForegroundService(
                            Intent(this, RecognizeService::class.java)
                                .putExtra(RecognizeService.EXTRA_TITLE, call.argument<String>("title")),
                        )
                    } catch (_: Exception) {
                        RecognizeService.onStarted = null
                        result.success(false)
                    }
                }
                "canCaptureDevice" -> result.success(Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q)
                // 已有录屏授权就直接复用；没有时弹系统授权框，同意后由服务拿授权
                "requestCapture" -> when {
                    Build.VERSION.SDK_INT < Build.VERSION_CODES.Q -> result.success(false)
                    RecognizeService.projection != null -> result.success(true)
                    else -> {
                        pendingCapture?.success(false)
                        pendingCapture = result
                        captureTitle = call.argument<String>("title").orEmpty()
                        @Suppress("DEPRECATION")
                        startActivityForResult(
                            getSystemService(MediaProjectionManager::class.java).createScreenCaptureIntent(),
                            REQUEST_CAPTURE,
                        )
                    }
                }
                "stopService" -> {
                    stopService(Intent(this, RecognizeService::class.java))
                    result.success(null)
                }
                "show" -> {
                    bubble.show()
                    result.success(null)
                }
                "hide" -> {
                    bubble.hide()
                    result.success(null)
                }
                "update" -> {
                    bubble.update(call.arguments<Map<String, Any?>>()!!)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        val main = Handler(Looper.getMainLooper())
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "kanade/recognize/pcm").setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    val unavailable = { events.error("capture", "playback capture unavailable", null) }
                    val started = RecognizeService.startCapture(
                        onData = { pcm -> main.post { events.success(pcm) } },
                        onError = { main.post(unavailable) },
                    )
                    if (!started) unavailable()
                }

                override fun onCancel(arguments: Any?) {
                    RecognizeService.stopCapture()
                }
            },
        )
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "kanade/app_login").setMethodCallHandler { call, result ->
            when (call.method) {
                // 必须指定包名：QQ 音乐也注册了 wtloginmqq://，不指定可能被它接走
                "open" -> result.success(
                    try {
                        startActivity(
                            Intent(Intent.ACTION_VIEW, Uri.parse(call.argument<String>("url")))
                                .addCategory(Intent.CATEGORY_BROWSABLE)
                                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                .setPackage(call.argument<String>("package")),
                        )
                        true
                    } catch (_: Exception) {
                        false
                    },
                )
                else -> result.notImplemented()
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "kanade/playback").setMethodCallHandler { call, result ->
            when (call.method) {
                // 播放进程被系统单独杀掉时，绑定不会把它拉回来
                "start" -> result.success(
                    try {
                        startService(Intent(this, AudioService::class.java))
                        true
                    } catch (_: Exception) {
                        false
                    },
                )
                else -> result.notImplemented()
            }
        }
        downloads = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "kanade/downloads").apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "launched" -> {
                        result.success(openDownloads)
                        openDownloads = false
                    }
                    // 恢复下载：让用户授权下载文件夹，重装后的旧文件和 .lrc 才读得到
                    "pickFolder" -> {
                        pendingFolder?.success(false)
                        pendingFolder = result
                        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE)
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            intent.putExtra(DocumentsContract.EXTRA_INITIAL_URI, MediaStoreBridge.initialFolder())
                        }
                        try {
                            @Suppress("DEPRECATION")
                            startActivityForResult(intent, REQUEST_FOLDER)
                        } catch (_: Exception) {
                            pendingFolder = null
                            result.success(false)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "kanade/update").setMethodCallHandler { call, result ->
            when (call.method) {
                // 没开「安装未知应用」权限时，系统安装器会自己引导去打开
                "install" -> result.success(
                    try {
                        val uri = FileProvider.getUriForFile(
                            this,
                            "$packageName.update",
                            File(call.argument<String>("path")!!),
                        )
                        startActivity(
                            Intent(Intent.ACTION_VIEW)
                                .setDataAndType(uri, "application/vnd.android.package-archive")
                                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK),
                        )
                        true
                    } catch (_: Exception) {
                        false
                    },
                )
                else -> result.notImplemented()
            }
        }
    }

    companion object {
        private const val REQUEST_CAPTURE = 7301
        private const val REQUEST_FOLDER = 7302
    }
}
