package com.lxi.kanade

import android.app.ActivityManager
import android.app.Application
import android.content.pm.PackageManager
import android.os.Build
import android.os.Process
import com.ryanheise.audioservice.AudioServicePlugin

class KanadeApplication : Application() {
    @Suppress("DEPRECATION")
    val separateAndroidPlayback: Boolean by lazy {
        packageManager.getApplicationInfo(packageName, PackageManager.GET_META_DATA)
            .metaData?.getBoolean("kanade.separateAndroidPlayback") == true
    }

    override fun onCreate() {
        super.onCreate()
        SessionKey.install(this)
        MediaStoreBridge.install(this)
        // 播放所在的引擎（单独的播放进程里，或不分进程时界面的引擎）由 audio_service 建，悬浮歌词接在它上面
        AudioServicePlugin.setEngineListener { FloatingLyrics.attach(this, it) }
        if (!separateAndroidPlayback) return
        val process = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            getProcessName()
        } else {
            getSystemService(ActivityManager::class.java).runningAppProcesses
                ?.firstOrNull { it.pid == Process.myPid() }?.processName
        }
        // 界面进程不随播放保活：后台播放时系统可以单独回收它，播放进程不受影响。
        AudioServicePlugin.configurePlaybackProcess(
            process != "$packageName:playback",
            "androidPlaybackMain",
            MainActivity::class.java.name,
            null,
        )
    }
}
