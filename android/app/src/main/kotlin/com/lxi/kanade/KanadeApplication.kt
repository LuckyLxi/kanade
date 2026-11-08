package com.lxi.kanade

import android.app.ActivityManager
import android.app.Application
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.content.pm.PackageManager
import android.os.Build
import android.os.IBinder
import android.os.Process
import com.ryanheise.audioservice.AudioServicePlugin
import java.util.function.Consumer

class KanadeApplication : Application() {
    private var uiBound = false
    private val uiConnection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName, service: IBinder) = Unit
        override fun onServiceDisconnected(name: ComponentName) = Unit
    }

    @Suppress("DEPRECATION")
    val separateAndroidPlayback: Boolean by lazy {
        packageManager.getApplicationInfo(packageName, PackageManager.GET_META_DATA)
            .metaData?.getBoolean("kanade.separateAndroidPlayback") == true
    }

    override fun onCreate() {
        super.onCreate()
        if (!separateAndroidPlayback) return
        val process = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            getProcessName()
        } else {
            getSystemService(ActivityManager::class.java).runningAppProcesses
                ?.firstOrNull { it.pid == Process.myPid() }?.processName
        }
        val remote = process != "$packageName:playback"
        AudioServicePlugin.configurePlaybackProcess(
            remote,
            "androidPlaybackMain",
            MainActivity::class.java.name,
            if (remote) null else Consumer(::keepUiDuringPlayback),
        )
    }

    // 保留正在播放时的页面栈，界面停帧后仍能独立回收图形缓冲。
    private fun keepUiDuringPlayback(playing: Boolean) {
        if (playing == uiBound) return
        if (playing) {
            uiBound = bindService(
                Intent(this, PlaybackUiService::class.java),
                uiConnection,
                Context.BIND_AUTO_CREATE or Context.BIND_IMPORTANT or Context.BIND_NOT_FOREGROUND,
            )
        } else {
            unbindService(uiConnection)
            uiBound = false
        }
    }
}
