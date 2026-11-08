package com.lxi.kanade

import android.content.Context
import android.content.Intent
import android.net.Uri
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {
    override fun provideFlutterEngine(context: Context): FlutterEngine? =
        if ((application as KanadeApplication).separateAndroidPlayback) null
        else super.provideFlutterEngine(context)

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
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
    }
}
