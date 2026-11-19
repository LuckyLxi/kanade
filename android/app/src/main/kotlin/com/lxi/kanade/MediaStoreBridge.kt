package com.lxi.kanade

import android.content.ContentValues
import android.content.Context
import android.media.MediaScannerConnection
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.util.Log
import androidx.annotation.Keep
import java.io.File
import java.io.IOException

/**
 * 下载的歌存进系统「音乐/Kanade」，由 Rust（download.rs）经 JNI 调用。
 * Android 10 起走 MediaStore，不需要存储权限；更早的系统直接写文件。
 * 这些方法只有 Rust 在调，不 @Keep 的话 release 包的 R8 会把它们删掉。
 */
@Keep
object MediaStoreBridge {
    private const val FOLDER = "Kanade"
    private lateinit var app: Context
    private val main = Handler(Looper.getMainLooper())

    fun install(context: Context) {
        app = context.applicationContext
        try {
            nativeInit()
        } catch (e: UnsatisfiedLinkError) {
            Log.e("MediaStoreBridge", "native library unavailable", e)
            return
        }
        // 「仅 Wi-Fi 下载」按是否计费判断，注册后会先回调一次当前网络
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            app.getSystemService(ConnectivityManager::class.java).registerDefaultNetworkCallback(
                object : ConnectivityManager.NetworkCallback() {
                    override fun onCapabilitiesChanged(network: Network, caps: NetworkCapabilities) {
                        nativeNetworkChanged(!caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED))
                    }
                },
            )
        }
    }

    /** [total] 为 0 时收起下载通知。 */
    @JvmStatic
    fun notifyDownloads(done: Int, total: Int) {
        main.post {
            if (total == 0) DownloadService.stop(app) else DownloadService.show(app, done, total)
        }
    }

    /** 把临时文件 [src] 存成 [name]，返回之后播放、删除用的地址。 */
    @JvmStatic
    fun save(src: String, name: String, mime: String): String {
        val source = File(src)
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            @Suppress("DEPRECATION")
            val dir = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MUSIC), FOLDER)
            dir.mkdirs()
            var dest = File(dir, name)
            var n = 2
            while (dest.exists()) {
                dest = File(dir, "${name.substringBeforeLast('.')} ($n).${name.substringAfterLast('.')}")
                n++
            }
            source.copyTo(dest)
            source.delete()
            MediaScannerConnection.scanFile(app, arrayOf(dest.path), arrayOf(mime), null)
            return dest.path
        }
        val resolver = app.contentResolver
        val collection = if (mime.startsWith("audio/")) {
            MediaStore.Audio.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        } else {
            MediaStore.Files.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        }
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, name)
            put(MediaStore.MediaColumns.MIME_TYPE, mime)
            put(MediaStore.MediaColumns.RELATIVE_PATH, "${Environment.DIRECTORY_MUSIC}/$FOLDER")
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        val uri = resolver.insert(collection, values) ?: throw IOException("MediaStore insert failed")
        try {
            val out = resolver.openOutputStream(uri) ?: throw IOException("MediaStore open failed")
            out.use { o -> source.inputStream().use { it.copyTo(o) } }
            values.clear()
            values.put(MediaStore.MediaColumns.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
        } catch (e: Exception) {
            resolver.delete(uri, null, null)
            throw e
        }
        source.delete()
        return uri.toString()
    }

    @JvmStatic
    fun delete(file: String) {
        try {
            if (file.startsWith("content://")) {
                app.contentResolver.delete(Uri.parse(file), null, null)
            } else {
                File(file).delete()
            }
        } catch (e: Exception) {
            // 重装 App 后旧文件不再归我们，删不掉就留在那里
            Log.w("MediaStoreBridge", "delete failed", e)
        }
    }

    @JvmStatic
    fun exists(file: String): Boolean {
        if (!file.startsWith("content://")) return File(file).isFile
        return try {
            app.contentResolver.openFileDescriptor(Uri.parse(file), "r")?.use { true } ?: false
        } catch (e: Exception) {
            false
        }
    }

    @JvmStatic
    private external fun nativeInit()

    @JvmStatic
    private external fun nativeNetworkChanged(metered: Boolean)
}
