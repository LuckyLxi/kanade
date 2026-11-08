package com.lxi.kanade

import android.app.Service
import android.content.Intent
import android.os.Binder
import android.os.IBinder

class PlaybackUiService : Service() {
    private val token = Binder()

    override fun onBind(intent: Intent): IBinder = token
}
