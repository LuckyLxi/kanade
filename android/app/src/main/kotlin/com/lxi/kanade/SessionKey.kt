package com.lxi.kanade

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Log
import java.io.File
import java.io.RandomAccessFile
import java.security.KeyStore
import javax.crypto.KeyGenerator
import javax.crypto.Mac
import javax.crypto.SecretKey

/**
 * 登录凭证的加密密钥：由 Keystore 里不可导出的 HMAC 密钥派生，交给 Rust（secret.rs）。
 * 每个进程启动时调用一次，必须早于 Flutter 引擎加载同一个 Rust 库。
 */
object SessionKey {
    private const val ALIAS = "kanade_session"

    fun install(context: Context) {
        try {
            System.loadLibrary("rust_lib_kanade")
            nativeSetKey(derive(context))
        } catch (e: Exception) {
            // 不影响启动；没有密钥时 Rust 读不出已保存的凭证，登录会报错。
            Log.e("SessionKey", "session key unavailable", e)
        }
    }

    private fun derive(context: Context): ByteArray {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        // 界面进程和播放进程可能同时首次启动，加文件锁保证只生成一次。
        val key = RandomAccessFile(File(context.noBackupFilesDir, "session_key.lock"), "rw").channel.use { channel ->
            channel.lock()
            store.getKey(ALIAS, null) as SecretKey?
                ?: KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_HMAC_SHA256, "AndroidKeyStore").run {
                    init(KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_SIGN).build())
                    generateKey()
                }
        }
        return Mac.getInstance("HmacSHA256").run {
            init(key)
            doFinal("kanade session v1".toByteArray())
        }
    }

    @JvmStatic
    private external fun nativeSetKey(key: ByteArray)
}
