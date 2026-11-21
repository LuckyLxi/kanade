package com.lxi.kanade

import android.annotation.SuppressLint
import android.app.ActivityManager
import android.app.KeyguardManager
import android.content.BroadcastReceiver
import android.content.ComponentCallbacks
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.res.Configuration
import android.graphics.Canvas
import android.graphics.LinearGradient
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.PixelFormat
import android.graphics.RectF
import android.graphics.Shader
import android.graphics.Typeface
import android.hardware.input.InputManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.os.SystemClock
import android.provider.Settings
import android.util.TypedValue
import android.view.Choreographer
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.view.WindowManager
import androidx.core.content.ContextCompat
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * 悬浮歌词：离开 Kanade 后浮在其他应用上面，占满屏宽，只能上下拖。点一下弹出控制条，几秒没动就收起。
 * 锁定后点击会穿过歌词，在通知栏或设置页解锁。在 Kanade 里、锁屏和灭屏时不显示。
 *
 * 跑在播放所在的进程里，lib/player/floating_lyrics.dart 推设置、歌词和进度过来，
 * 排版和 Windows 桌面歌词（windows/runner/desktop_lyrics.cpp）一样。
 */
class FloatingLyrics private constructor(private val context: Context, private val channel: MethodChannel) {
    companion object {
        private const val ACTION_UI = "com.lxi.kanade.UI_VISIBLE"
        private const val EMPTY = -1
        private const val TITLE = -2
        private const val MIN_FONT = 14
        private const val MAX_FONT = 40
        private const val FONT_STEP = 2
        private const val ROW_HEIGHT = 1.45f
        private const val SUB_SCALE = 0.8f
        private const val STAGGER_INDENT = 3f
        private const val SCROLL_ANCHOR = 0.6f
        private const val BAR_TIMEOUT = 4000L
        private const val ALIGN_LEFT = 0
        private const val ALIGN_CENTER = 1
        private const val ALIGN_RIGHT = 2
        private const val ALIGN_STAGGER = 3
        private val GROUPS = listOf(
            listOf("previous", "toggle", "next"),
            listOf("smaller", "bigger"),
            listOf("translation", "romaji"),
            listOf("lock", "close"),
        )

        fun attach(context: Context, engine: FlutterEngine) {
            val channel = MethodChannel(engine.dartExecutor.binaryMessenger, "kanade/lyrics")
            val lyrics = FloatingLyrics(context.applicationContext, channel)
            channel.setMethodCallHandler(lyrics::onCall)
            engine.addEngineLifecycleListener(object : FlutterEngine.EngineLifecycleListener {
                override fun onPreEngineRestart() {}

                override fun onEngineWillDestroy() = lyrics.dispose()
            })
        }

        /** 界面进程的 Activity 看得见、看不见时告诉播放进程。 */
        fun uiVisible(context: Context, visible: Boolean) {
            context.sendBroadcast(Intent(ACTION_UI).setPackage(context.packageName).putExtra("visible", visible))
        }
    }

    private class Line(val time: Long, val text: String, val trans: String, val roma: String, val words: IntArray)

    /** 一行排好的文字：[charX] 是每个字左边的位置，最后一个是行尾。 */
    private class Slot {
        var line = EMPTY
        var version = -1
        var text = ""
        var size = 0f
        var width = 0f
        var charX = FloatArray(0)
    }

    private val wm = context.getSystemService(WindowManager::class.java)
    private val keyguard = context.getSystemService(KeyguardManager::class.java)
    private val density = context.resources.displayMetrics.density
    private val handler = Handler(Looper.getMainLooper())

    private var enabled = false
    private var locked = false
    private var fontSize = 22
    private var sung = 0xFFD4FF3A.toInt()
    private var unsung = 0xFFFFFFFF.toInt()
    private var singleLine = false
    private var outlined = true
    private var align = ALIGN_STAGGER
    private var translation = false
    private var romaji = false
    private var icons = mapOf<String, String>()

    private var title = ""
    private var lines = listOf<Line>()
    private var hasTrans = false
    private var hasRoma = false
    private var basePosition = 0L
    private var baseTime = 0L
    private var playing = false

    /** 排版变了（字号、歌词、颜色）就加一，各行重新排。 */
    private var version = 0

    private var uiVisible = uiInForeground()
    private var screenUsable = context.getSystemService(PowerManager::class.java).isInteractive && !keyguard.isKeyguardLocked
    private var shown = false
    private var barShown = false
    private var dragging = false
    private var ticking = false

    private val view = LyricsView()
    private val bar = BarView()
    private val params = overlayParams().apply {
        width = WindowManager.LayoutParams.MATCH_PARENT
        y = -1
    }
    private val barParams = overlayParams().apply {
        width = WindowManager.LayoutParams.MATCH_PARENT
        height = dp(52f).toInt()
    }

    private val hideBar = Runnable { setBar(false) }

    /** 界面崩了收不到 onStop 的广播，靠这个把 [uiVisible] 改回来。 */
    private val recheckUi = Runnable {
        uiVisible = uiInForeground()
        refresh()
    }

    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(c: Context, intent: Intent) {
            when (intent.action) {
                ACTION_UI -> uiVisible = intent.getBooleanExtra("visible", false)
                Intent.ACTION_SCREEN_OFF -> screenUsable = false
                Intent.ACTION_SCREEN_ON -> screenUsable = !keyguard.isKeyguardLocked
                Intent.ACTION_USER_PRESENT -> screenUsable = true
            }
            refresh()
        }
    }

    private val configCallbacks = object : ComponentCallbacks {
        override fun onConfigurationChanged(newConfig: Configuration) {
            // 转屏后屏幕高度变了，位置要重新夹一下
            if (shown) handler.post { relayout() }
        }

        @Deprecated("Deprecated in Java")
        override fun onLowMemory() {}
    }

    private val frame = object : Choreographer.FrameCallback {
        override fun doFrame(frameTimeNanos: Long) {
            ticking = false
            if (!shown || !playing) return
            if (view.frameChanged()) view.invalidate()
            tick()
        }
    }

    init {
        val filter = IntentFilter().apply {
            addAction(ACTION_UI)
            addAction(Intent.ACTION_SCREEN_OFF)
            addAction(Intent.ACTION_SCREEN_ON)
            addAction(Intent.ACTION_USER_PRESENT)
        }
        ContextCompat.registerReceiver(context, receiver, filter, ContextCompat.RECEIVER_NOT_EXPORTED)
        context.registerComponentCallbacks(configCallbacks)
    }

    private fun dispose() {
        enabled = false
        handler.removeCallbacks(recheckUi)
        refresh()
        context.unregisterReceiver(receiver)
        context.unregisterComponentCallbacks(configCallbacks)
    }

    /** 播放进程起来时界面多半在前台，那时还收不到界面发的广播，先自己查一次。 */
    private fun uiInForeground(): Boolean =
        context.getSystemService(ActivityManager::class.java).runningAppProcesses?.any {
            it.processName == context.packageName &&
                it.importance == ActivityManager.RunningAppProcessInfo.IMPORTANCE_FOREGROUND
        } == true

    private fun onCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "lyricsConfig" -> setConfig(call.arguments as Map<*, *>)
            "lyricsContent" -> setContent(call.arguments as Map<*, *>)
            "lyricsSync" -> {
                val args = call.arguments as Map<*, *>
                basePosition = (args["position"] as Number).toLong()
                baseTime = SystemClock.elapsedRealtime()
                playing = args["playing"] == true
                view.invalidate()
                bar.invalidate()
                tick()
            }
            "uiDisconnected" -> {
                // 界面进程刚死时系统可能还没把它从进程表里拿掉，稍等再查
                handler.removeCallbacks(recheckUi)
                handler.postDelayed(recheckUi, 1000)
            }
            else -> {
                result.notImplemented()
                return
            }
        }
        result.success(null)
    }

    private fun setConfig(args: Map<*, *>) {
        enabled = args["visible"] == true
        val wasLocked = locked
        locked = args["locked"] == true
        fontSize = (args["fontSize"] as Number? ?: fontSize).toInt().coerceIn(MIN_FONT, MAX_FONT)
        // ARGB 超过 Int 范围时 Dart 那边传来的是 Long
        sung = (args["sung"] as Number).toInt()
        unsung = (args["unsung"] as Number).toInt()
        singleLine = args["singleLine"] == true
        outlined = args["outline"] != false
        align = (args["align"] as Number? ?: ALIGN_STAGGER).toInt()
        translation = args["translation"] == true
        romaji = args["romaji"] == true
        if (!dragging) (args["y"] as Number?)?.let { params.y = it.toInt() }
        icons = (args["icons"] as Map<*, *>? ?: emptyMap<String, Int>()).entries.associate { (k, v) ->
            k as String to String(Character.toChars((v as Number).toInt()))
        }
        version++
        if (locked) setBar(false)
        if (locked != wasLocked) applyLock()
        view.setColors()
        refresh()
        relayout()
    }

    private fun setContent(args: Map<*, *>) {
        title = args["title"] as String? ?: ""
        lines = (args["lines"] as List<*>).map {
            val line = it as Map<*, *>
            Line(
                (line["time"] as Number).toLong(),
                line["text"] as String? ?: "",
                line["trans"] as String? ?: "",
                line["roma"] as String? ?: "",
                line["words"] as IntArray? ?: IntArray(0),
            )
        }
        hasTrans = lines.any { it.trans.isNotEmpty() }
        hasRoma = lines.any { it.roma.isNotEmpty() }
        version++
        view.invalidate()
    }

    private fun report() {
        channel.invokeMethod(
            "lyricsState",
            mapOf(
                "visible" to enabled,
                "locked" to locked,
                "fontSize" to fontSize,
                "translation" to translation,
                "romaji" to romaji,
                "x" to 0,
                "y" to params.y,
            ),
        )
    }

    private fun refresh() {
        val want = enabled && !uiVisible && screenUsable && Settings.canDrawOverlays(context)
        if (want == shown) return
        if (want) {
            layoutParams()
            try {
                wm.addView(view, params)
            } catch (_: Exception) {
                return
            }
            shown = true
            tick()
        } else {
            setBar(false)
            shown = false
            wm.removeView(view)
        }
    }

    private fun tick() {
        if (ticking || !shown || !playing) return
        ticking = true
        Choreographer.getInstance().postFrameCallback(frame)
    }

    private fun applyLock() {
        if (locked) {
            params.flags = params.flags or WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE
            // 点击能穿过的窗口不能比系统规定的更不透明，否则下面的应用收不到点击
            params.alpha = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                context.getSystemService(InputManager::class.java).maximumObscuringOpacityForTouch
            } else {
                0.8f
            }
        } else {
            params.flags = params.flags and WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE.inv()
            params.alpha = 1f
        }
    }

    private fun layoutParams() {
        params.height = windowHeight().roundToInt()
        val screen = screenHeight()
        if (params.y < 0) params.y = screen / 6
        params.y = params.y.coerceIn(0, max(0, screen - params.height))
    }

    private fun relayout() {
        layoutParams()
        if (!shown) return
        wm.updateViewLayout(view, params)
        view.invalidate()
        if (barShown) placeBar()
    }

    private fun setBar(show: Boolean) {
        handler.removeCallbacks(hideBar)
        if (show) handler.postDelayed(hideBar, BAR_TIMEOUT)
        if (show == barShown) return
        barShown = show
        if (show) {
            placeBar()
            wm.addView(bar, barParams)
        } else {
            wm.removeView(bar)
        }
        view.invalidate()
    }

    /** 控制条放在歌词下面，下面放不下就放上面。 */
    private fun placeBar() {
        val gap = dp(4f).toInt()
        val below = params.y + params.height + gap
        barParams.y = if (below + barParams.height <= screenHeight()) {
            below
        } else {
            max(0, params.y - gap - barParams.height)
        }
        if (barShown && bar.isAttachedToWindow) wm.updateViewLayout(bar, barParams)
    }

    private fun press(id: String) {
        when (id) {
            "previous", "toggle", "next" -> {
                channel.invokeMethod("action", id)
                return
            }
            "smaller", "bigger" -> {
                fontSize = (fontSize + if (id == "bigger") FONT_STEP else -FONT_STEP).coerceIn(MIN_FONT, MAX_FONT)
                version++
                relayout()
            }
            "translation" -> {
                translation = !translation
                relayout()
            }
            "romaji" -> {
                romaji = !romaji
                relayout()
            }
            "lock" -> {
                locked = true
                setBar(false)
                applyLock()
                relayout()
            }
            "close" -> {
                enabled = false
                refresh()
            }
        }
        bar.invalidate()
        report()
    }

    private fun position(): Long =
        if (playing) basePosition + SystemClock.elapsedRealtime() - baseTime else basePosition

    private fun currentLine(position: Long): Int {
        var lo = 0
        var hi = lines.size - 1
        var ans = -1
        while (lo <= hi) {
            val mid = (lo + hi) ushr 1
            if (lines[mid].time <= position) {
                ans = mid
                lo = mid + 1
            } else {
                hi = mid - 1
            }
        }
        return ans
    }

    private fun fontPx() = sp(fontSize.toFloat())

    private fun windowHeight(): Float {
        val row = fontPx() * ROW_HEIGHT
        var lyrics = if (singleLine) row else row * 2
        val subs = (if (translation) 1 else 0) + (if (romaji) 1 else 0)
        if (subs > 0) lyrics = max(lyrics, row + row * SUB_SCALE * subs)
        return lyrics + dp(6f) * 2
    }

    private fun screenHeight(): Int = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
        wm.currentWindowMetrics.bounds.height()
    } else {
        context.resources.displayMetrics.heightPixels
    }

    private fun overlayParams() = WindowManager.LayoutParams(
        WindowManager.LayoutParams.WRAP_CONTENT,
        WindowManager.LayoutParams.WRAP_CONTENT,
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        },
        WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED,
        PixelFormat.TRANSLUCENT,
    ).apply {
        gravity = Gravity.TOP or Gravity.START
        // 拖动时窗口挪位置别带系统的移动动画，不然跟不上手指
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) setCanPlayMoveAnimation(false)
    }

    private fun dp(v: Float) = v * density

    private fun sp(v: Float) =
        TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_SP, v, context.resources.displayMetrics)

    private val panel = 0x99000000.toInt()

    private fun drawPanel(canvas: Canvas, view: View, paint: Paint, rect: RectF) {
        paint.shader = null
        paint.style = Paint.Style.FILL
        paint.color = panel
        rect.set(dp(8f), 0f, view.width - dp(8f), view.height.toFloat())
        canvas.drawRoundRect(rect, dp(14f), dp(14f), paint)
    }

    @SuppressLint("ViewConstructor")
    private inner class LyricsView : View(context) {
        private val slots = Array(4) { Slot() }
        private val rows = IntArray(4) { EMPTY }
        private var active = -1
        private var edge = -1f
        private var single = false

        /** 上次画的帧，见 [frameChanged]。 */
        private val drawnRows = IntArray(4) { EMPTY }
        private var drawnEdge = Int.MIN_VALUE
        private var drawnVersion = -1

        private val fill = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
        }
        private val outline = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            typeface = fill.typeface
            style = Paint.Style.STROKE
            strokeJoin = Paint.Join.ROUND
            color = 0xB3000000.toInt()
        }
        private val background = Paint(Paint.ANTI_ALIAS_FLAG)
        private val rect = RectF()
        private val gradientMatrix = Matrix()
        private var gradient: Shader? = null
        private val slop = ViewConfiguration.get(context).scaledTouchSlop

        private var downY = 0f
        private var startY = 0

        fun setColors() {
            // 已唱和未唱之间留一道软边，按位置把这段渐变平移过去
            gradient = LinearGradient(0f, 0f, 1f, 0f, sung, unsung, Shader.TileMode.CLAMP)
            invalidate()
        }

        private fun computeFrame() {
            rows.fill(EMPTY)
            active = -1
            val position = position()
            single = singleLine || (romaji && hasRoma) || (translation && hasTrans)
            if (lines.isEmpty()) {
                rows[0] = TITLE
            } else if (single) {
                val current = currentLine(position)
                val line = max(current, 0)
                rows[0] = line
                active = if (current >= 0) 0 else -1
                if (romaji && hasRoma) rows[2] = line
                if (translation && hasTrans) rows[3] = line
            } else {
                // 两行轮流：一行在唱时另一行显示下一句
                val current = currentLine(position)
                if (current < 0) {
                    rows[0] = 0
                    rows[1] = 1
                } else {
                    active = current % 2
                    rows[active] = current
                    rows[1 - active] = current + 1
                }
                for (i in rows.indices) if (rows[i] >= lines.size) rows[i] = EMPTY
            }
            for (i in slots.indices) {
                if (slots[i].line != rows[i] || slots[i].version != version) layoutSlot(slots[i], rows[i], i)
            }
            edge = if (active >= 0) fillEdge(slots[active], position) else -1f
        }

        /** 帧里看得见的东西变了才重画，进度每帧都在走，但已唱的边界不一定挪了一个像素。 */
        fun frameChanged(): Boolean {
            computeFrame()
            return !rows.contentEquals(drawnRows) || edgeKey() != drawnEdge || version != drawnVersion
        }

        /** 已唱边界按半像素算。 */
        private fun edgeKey() = (edge * 2).roundToInt()

        private fun layoutSlot(slot: Slot, line: Int, index: Int) {
            slot.line = line
            slot.version = version
            slot.text = when {
                line == TITLE -> title
                line < 0 -> ""
                index == 2 -> lines[line].roma
                index == 3 -> lines[line].trans
                else -> lines[line].text
            }
            slot.size = fontPx() * if (index >= 2) SUB_SCALE else 1f
            fill.textSize = slot.size
            val n = slot.text.length
            slot.charX = FloatArray(n + 1) { fill.getRunAdvance(slot.text, 0, n, 0, n, false, it) }
            slot.width = slot.charX[n]
        }

        private fun fillEdge(slot: Slot, position: Long): Float {
            if (slot.line < 0 || slot.text.isEmpty()) return -1f
            val line = lines[slot.line]
            val end = slot.width
            val words = line.words
            if (words.isEmpty()) {
                // 和播放页一样：离下一句太远时按 6 秒算
                val next = if (slot.line + 1 < lines.size) lines[slot.line + 1].time else line.time + 5000
                val span = (next - line.time).toFloat().coerceIn(800f, 6000f)
                return end * ((position - line.time) / span).coerceIn(0f, 1f)
            }
            var chars = 0.0
            var i = 0
            while (i + 2 < words.size) {
                val start = words[i]
                val duration = words[i + 1]
                val length = words[i + 2]
                i += 3
                if (position < start) break
                if (position >= start + duration || duration <= 0) {
                    chars += length
                    continue
                }
                chars += length * (position - start).toDouble() / duration
                break
            }
            val last = slot.charX.size - 1
            chars = chars.coerceIn(0.0, last.toDouble())
            val c = chars.toInt()
            if (c >= last) return end
            return (slot.charX[c] + (slot.charX[c + 1] - slot.charX[c]) * (chars - c)).toFloat()
        }

        /** 太长放不下的行跟着已唱的位置往左滚，翻译和罗马音跟着上面那行的进度滚。 */
        private fun slotX(slot: Slot, fit: Float, edge: Float, progress: Float): Float {
            val pad = dp(20f)
            val avail = width - pad * 2
            if (slot.width <= avail) return fit
            val overflow = slot.width - avail
            val offset = if (edge >= 0) {
                (edge - avail * SCROLL_ANCHOR).coerceIn(0f, overflow)
            } else {
                overflow * progress.coerceIn(0f, 1f)
            }
            return pad - offset
        }

        override fun onDraw(canvas: Canvas) {
            computeFrame()
            rows.copyInto(drawnRows)
            drawnEdge = edgeKey()
            drawnVersion = version
            if (barShown || dragging) drawPanel(canvas, this, background, rect)

            val main = slots[0]
            val progress = if (edge >= 0 && main.width > 0) edge / main.width else 0f
            val mode = if (single && align == ALIGN_STAGGER) ALIGN_CENTER else align
            val pad = dp(20f)
            val font = fontPx()
            val row = font * ROW_HEIGHT
            val sub = row * SUB_SCALE
            val top = dp(6f)
            val ys = floatArrayOf(top, top + row, top + row, top + row + if (rows[2] != EMPTY) sub else 0f)
            canvas.save()
            canvas.clipRect(dp(6f), 0f, width - dp(6f), height.toFloat())
            for (i in slots.indices) {
                val slot = slots[i]
                if (slot.text.isEmpty()) continue
                val fit = when {
                    slot.line == TITLE || mode == ALIGN_CENTER -> (width - slot.width) / 2
                    mode == ALIGN_LEFT || (mode == ALIGN_STAGGER && i == 0) -> pad
                    mode == ALIGN_RIGHT -> width - pad - slot.width
                    // 错开的第二行：比第一行往右一点，短句挨得近，但不超出右边
                    else -> min(pad + font * STAGGER_INDENT, width - pad - slot.width)
                }
                val slotEdge = if (i == active) edge else -1f
                val x = slotX(slot, fit, slotEdge, if (i >= 2) progress else 0f)
                drawSlot(canvas, slot, x, ys[i], if (i >= 2) sub else row, slotEdge)
            }
            canvas.restore()
        }

        private fun drawSlot(canvas: Canvas, slot: Slot, x: Float, top: Float, height: Float, edge: Float) {
            fill.textSize = slot.size
            outline.textSize = slot.size
            outline.strokeWidth = max(dp(1f), slot.size / 9)
            val fm = fill.fontMetrics
            val baseline = top + (height - (fm.descent - fm.ascent)) / 2 - fm.ascent
            if (outlined) canvas.drawText(slot.text, x, baseline, outline)
            val shader = gradient
            if (edge < 0 || shader == null) {
                fill.shader = null
                fill.color = unsung
            } else {
                val soft = dp(3f)
                gradientMatrix.setScale(soft, 1f)
                gradientMatrix.postTranslate(x + edge - soft / 2, 0f)
                shader.setLocalMatrix(gradientMatrix)
                fill.shader = shader
            }
            canvas.drawText(slot.text, x, baseline, fill)
            fill.shader = null
        }

        @SuppressLint("ClickableViewAccessibility")
        override fun onTouchEvent(event: MotionEvent): Boolean {
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    downY = event.rawY
                    startY = params.y
                    dragging = false
                }
                MotionEvent.ACTION_MOVE -> {
                    val dy = event.rawY - downY
                    if (!dragging && abs(dy) > slop) {
                        dragging = true
                        invalidate()
                    }
                    if (dragging) {
                        params.y = (startY + dy.toInt()).coerceIn(0, max(0, screenHeight() - params.height))
                        wm.updateViewLayout(this, params)
                        if (barShown) {
                            placeBar()
                            setBar(true)
                        }
                    }
                }
                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                    if (dragging) {
                        dragging = false
                        invalidate()
                        report()
                    } else if (event.actionMasked == MotionEvent.ACTION_UP) {
                        setBar(!barShown)
                    }
                }
            }
            return true
        }
    }

    @SuppressLint("ViewConstructor")
    private inner class BarView : View(context) {
        private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        private val iconPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            textAlign = Paint.Align.CENTER
            // 图标用 App 自带的 Material Icons 字体画，码位由 Dart 那边给
            typeface = try {
                val key = FlutterInjector.instance().flutterLoader().getLookupKeyForAsset("fonts/MaterialIcons-Regular.otf")
                Typeface.createFromAsset(context.assets, key)
            } catch (_: Exception) {
                null
            }
        }
        private val rect = RectF()
        private val centers = HashMap<String, Float>()
        private var unit = 0f
        private var pressed: String? = null

        private fun layoutButtons() {
            centers.clear()
            val buttons = GROUPS.sumOf { it.size }
            val gaps = GROUPS.size - 1
            // 一个按钮占一格，组和组之间空半格
            unit = min(dp(44f), (width - dp(16f) * 2) / (buttons + gaps * 0.5f))
            var x = (width - unit * (buttons + gaps * 0.5f)) / 2
            for (group in GROUPS) {
                for (id in group) {
                    centers[id] = x + unit / 2
                    x += unit
                }
                x += unit / 2
            }
        }

        override fun onDraw(canvas: Canvas) {
            layoutButtons()
            drawPanel(canvas, this, paint, rect)
            val cy = height / 2f
            val radius = min(unit, height.toFloat()) * 0.42f
            iconPaint.textSize = min(unit * 0.55f, dp(24f))
            val fm = iconPaint.fontMetrics
            for ((id, cx) in centers) {
                val on = (id == "translation" && translation) || (id == "romaji" && romaji)
                val circle = when {
                    id == pressed -> 0x33FFFFFF
                    on -> 0x1AFFFFFF
                    else -> 0
                }
                if (circle != 0) {
                    paint.color = circle
                    canvas.drawCircle(cx, cy, radius, paint)
                }
                val name = if (id == "toggle") (if (playing) "pause" else "play") else id
                val glyph = icons[name] ?: continue
                iconPaint.color = if (on) sung else 0xFFFFFFFF.toInt()
                canvas.drawText(glyph, cx, cy - (fm.ascent + fm.descent) / 2, iconPaint)
            }
        }

        private fun hit(x: Float): String? =
            centers.entries.firstOrNull { abs(x - it.value) <= unit / 2 }?.key

        @SuppressLint("ClickableViewAccessibility")
        override fun onTouchEvent(event: MotionEvent): Boolean {
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    pressed = hit(event.x)
                    setBar(true)
                    invalidate()
                }
                MotionEvent.ACTION_UP -> {
                    val id = pressed
                    pressed = null
                    invalidate()
                    if (id != null && hit(event.x) == id) press(id)
                }
                MotionEvent.ACTION_CANCEL -> {
                    pressed = null
                    invalidate()
                }
            }
            return true
        }
    }
}
