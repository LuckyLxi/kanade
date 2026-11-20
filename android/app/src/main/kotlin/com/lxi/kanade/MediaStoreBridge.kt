package com.lxi.kanade

import android.content.ContentUris
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
import android.os.ParcelFileDescriptor
import android.provider.DocumentsContract
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
    private const val PREFS = "downloads"
    private const val TREE = "tree"
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
            val uri = Uri.parse(file)
            if (file.startsWith("content://") && DocumentsContract.isDocumentUri(app, uri)) {
                DocumentsContract.deleteDocument(app.contentResolver, uri)
            } else if (file.startsWith("content://")) {
                app.contentResolver.delete(uri, null, null)
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

    /** 选文件夹时先停在「音乐/Kanade」。 */
    fun initialFolder(): Uri = DocumentsContract.buildDocumentUri(
        "com.android.externalstorage.documents",
        "primary:${Environment.DIRECTORY_MUSIC}/$FOLDER",
    )

    /** 恢复下载时用户选的文件夹（已拿到长期读写授权）；重装后旧文件只有这样才读得到 .lrc、删得掉。 */
    fun setTree(tree: Uri) {
        app.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString(TREE, tree.toString()).apply()
    }

    private fun tree(): Uri? {
        val tree = app.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(TREE, null) ?: return null
        val uri = Uri.parse(tree)
        return uri.takeIf { app.contentResolver.persistedUriPermissions.any { it.uri == uri && it.isReadPermission } }
    }

    /**
     * 下载文件夹里的文件，一行一个「地址\t文件名\t大小\tmedia:<id>」。选过文件夹时列那个文件夹，
     * 最后一项是同一文件的 MediaStore id，用来认出地址记成 MediaStore 的旧记录；
     * 没选过时只列 MediaStore 里看得到的（这次安装存的），地址和 [save] 返回的写法一样。
     */
    @JvmStatic
    fun list(): String {
        val out = StringBuilder()
        fun add(file: String, name: String, size: Long, alias: String = "") {
            out.append(file).append('\t').append(name).append('\t').append(size).append('\t').append(alias).append('\n')
        }
        tree()?.let { tree ->
            val children = DocumentsContract.buildChildDocumentsUriUsingTree(tree, DocumentsContract.getTreeDocumentId(tree))
            app.contentResolver.query(
                children,
                arrayOf(
                    DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                    DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                    DocumentsContract.Document.COLUMN_SIZE,
                    DocumentsContract.Document.COLUMN_MIME_TYPE,
                ),
                null,
                null,
                null,
            )?.use { c ->
                while (c.moveToNext()) {
                    if (c.getString(3) == DocumentsContract.Document.MIME_TYPE_DIR) continue
                    val name = c.getString(1) ?: continue
                    val doc = DocumentsContract.buildDocumentUriUsingTree(tree, c.getString(0))
                    val media = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        try {
                            MediaStore.getMediaUri(app, doc)?.let { "media:${ContentUris.parseId(it)}" }
                        } catch (e: Exception) {
                            null
                        }
                    } else {
                        null
                    }
                    add(doc.toString(), name, c.getLong(2), media.orEmpty())
                }
            }
            return out.toString()
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            @Suppress("DEPRECATION")
            val dir = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MUSIC), FOLDER)
            dir.listFiles()?.filter { it.isFile }?.forEach { add(it.path, it.name, it.length()) }
            return out.toString()
        }
        val files = MediaStore.Files.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        val audio = MediaStore.Audio.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        app.contentResolver.query(
            files,
            arrayOf(
                MediaStore.MediaColumns._ID,
                MediaStore.MediaColumns.DISPLAY_NAME,
                MediaStore.MediaColumns.SIZE,
                MediaStore.Files.FileColumns.MEDIA_TYPE,
            ),
            "${MediaStore.MediaColumns.RELATIVE_PATH} = ?",
            arrayOf("${Environment.DIRECTORY_MUSIC}/$FOLDER/"),
            null,
        )?.use { c ->
            while (c.moveToNext()) {
                val name = c.getString(1) ?: continue
                val base = if (c.getInt(3) == MediaStore.Files.FileColumns.MEDIA_TYPE_AUDIO) audio else files
                add(ContentUris.withAppendedId(base, c.getLong(0)).toString(), name, c.getLong(2))
            }
        }
        return out.toString()
    }

    /** 只读打开，把文件描述符交给 Rust（由它关闭）；打不开返回 -1。 */
    @JvmStatic
    fun openFd(file: String): Int = try {
        val fd = if (file.startsWith("content://")) {
            app.contentResolver.openFileDescriptor(Uri.parse(file), "r")
        } else {
            ParcelFileDescriptor.open(File(file), ParcelFileDescriptor.MODE_READ_ONLY)
        }
        fd?.detachFd() ?: -1
    } catch (e: Exception) {
        Log.w("MediaStoreBridge", "open failed", e)
        -1
    }

    @JvmStatic
    private external fun nativeInit()

    @JvmStatic
    private external fun nativeNetworkChanged(metered: Boolean)
}
