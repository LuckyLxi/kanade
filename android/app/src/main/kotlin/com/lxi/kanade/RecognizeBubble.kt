package com.lxi.kanade

import android.animation.ValueAnimator
import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.BitmapShader
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.PixelFormat
import android.graphics.RectF
import android.graphics.Shader
import android.graphics.drawable.Drawable
import android.os.Build
import android.provider.Settings
import android.text.TextPaint
import android.text.TextUtils
import android.util.TypedValue
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.view.WindowManager
import android.view.animation.DecelerateInterpolator
import android.view.animation.LinearInterpolator
import java.net.URL
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min

/**
 * 听歌识曲时切到别的软件，屏幕边上浮着的按钮。正在听是圆按钮，外圈走 15 秒进度；
 * 认出来展开成胶囊（封面、歌名、播放键），没认出来是短胶囊带重新识别键。
 * 能拖到任意位置，松手贴到最近的左右边，拖到底部的 × 上结束识曲。
 *
 * 点击通过 [onAction] 告诉 Dart：open（回到 Kanade）、play、retry、close。
 */
class RecognizeBubble(private val context: Context, private val onAction: (String) -> Unit) {
    private val wm = context.getSystemService(WindowManager::class.java)
    private val prefs = context.getSharedPreferences("recognize_bubble", Context.MODE_PRIVATE)
    private val density = context.resources.displayMetrics.density

    private val pad = dp(8f) // 窗口比按钮大一圈，留给「正在听」的波纹
    private val size = dp(52f)
    private val edge = dp(8f)
    private val maxWidth = dp(230f)

    private val bubble = BubbleView()
    private val target = TargetView()
    private val params = overlayParams()
    private val targetParams = overlayParams().apply {
        flags = flags or WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE
        gravity = Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL
        width = dp(80f).toInt()
        height = dp(80f).toInt()
        y = dp(48f).toInt()
    }

    private var shown = false
    private var dockRight = prefs.getBoolean("right", true)
    private var slide: ValueAnimator? = null
    private var resize: ValueAnimator? = null
    private var progressAnim: ValueAnimator? = null

    private var mode = "listening"
    private var title = ""
    private var artist = ""
    private var message = ""
    private var coverUrl = ""
    private var cover: Bitmap? = null
    private var progress = 0f
    private var pulse = 0f
    private var fade = 1f

    /** 当前按钮宽度，动画中途也是这个值；[targetWidth] 是这次要变到的宽度。 */
    private var bubbleWidth = size
    private var targetWidth = size

    private val pulseAnim = ValueAnimator.ofFloat(0f, 1f).apply {
        duration = 1600
        repeatCount = ValueAnimator.INFINITE
        interpolator = LinearInterpolator()
        addUpdateListener {
            pulse = it.animatedValue as Float
            bubble.invalidate()
        }
    }

    fun show() {
        if (shown || !Settings.canDrawOverlays(context)) return
        shown = true
        bubbleWidth = targetWidth
        params.y = prefs.getInt("y", screenHeight() / 3)
        layout()
        // × 先加，叠在按钮下面；平时隐藏，拖动时才显示
        target.visibility = View.INVISIBLE
        wm.addView(target, targetParams)
        wm.addView(bubble, params)
        if (mode == "listening") pulseAnim.start()
    }

    fun hide() {
        if (!shown) return
        shown = false
        slide?.cancel()
        resize?.cancel()
        pulseAnim.cancel()
        wm.removeView(bubble)
        wm.removeView(target)
    }

    fun update(args: Map<String, Any?>) {
        val nextMode = args["mode"] as String
        title = args["title"] as String? ?: ""
        artist = args["artist"] as String? ?: ""
        message = args["message"] as String? ?: ""
        setCover(args["cover"] as String? ?: "")
        setProgress((args["seconds"] as Int? ?: 0) / 15f)
        if (nextMode != mode) {
            mode = nextMode
            if (mode == "listening") {
                if (shown) pulseAnim.start()
            } else {
                pulseAnim.cancel()
            }
            animateWidth(widthFor(mode))
        } else {
            bubble.invalidate()
        }
    }

    private fun widthFor(mode: String): Float = when (mode) {
        "found" -> min(
            maxWidth,
            max(dp(140f), dp(6f + 40f + 8f + 8f + 34f + 6f) + max(bubble.titlePaint.measureText(title), bubble.artistPaint.measureText(artist))),
        )
        "message" -> min(maxWidth, dp(14f + 8f + 34f + 6f) + bubble.messagePaint.measureText(message))
        else -> size
    }

    private fun animateWidth(to: Float) {
        resize?.cancel()
        targetWidth = to
        if (!shown) {
            bubbleWidth = to
            fade = 1f
            return
        }
        val from = bubbleWidth
        resize = ValueAnimator.ofFloat(0f, 1f).apply {
            duration = 300
            interpolator = DecelerateInterpolator(2f)
            addUpdateListener {
                val f = it.animatedValue as Float
                bubbleWidth = from + (to - from) * f
                fade = f
                layout()
                wm.updateViewLayout(bubble, params)
                bubble.invalidate()
            }
            start()
        }
    }

    private fun setProgress(to: Float) {
        progressAnim?.cancel()
        if (to <= 0f || !shown) {
            progress = to
            return
        }
        progressAnim = ValueAnimator.ofFloat(progress, min(to, 1f)).apply {
            duration = 1000
            interpolator = LinearInterpolator()
            addUpdateListener {
                progress = it.animatedValue as Float
                bubble.invalidate()
            }
            start()
        }
    }

    private fun setCover(url: String) {
        if (url == coverUrl) return
        coverUrl = url
        cover = null
        if (url.isEmpty()) return
        Thread {
            val bitmap = try {
                URL(url).openStream().use { BitmapFactory.decodeStream(it) }
            } catch (_: Exception) {
                null
            }
            bubble.post {
                if (coverUrl != url) return@post
                cover = bitmap
                bubble.invalidate()
            }
        }.start()
    }

    /** 按贴着的那一边算窗口位置：贴右边时变宽往左长，贴左边往右长。 */
    private fun layout() {
        params.width = (bubbleWidth + pad * 2).toInt()
        params.height = (size + pad * 2).toInt()
        params.x = if (dockRight) (screenWidth() - bubbleWidth - pad - edge).toInt() else (edge - pad).toInt()
    }

    private fun snap() {
        val center = params.x + params.width / 2
        dockRight = center > screenWidth() / 2
        val from = params.x
        val to = if (dockRight) (screenWidth() - bubbleWidth - pad - edge).toInt() else (edge - pad).toInt()
        params.y = params.y.coerceIn(0, screenHeight() - params.height)
        prefs.edit().putBoolean("right", dockRight).putInt("y", params.y).apply()
        slide = ValueAnimator.ofInt(from, to).apply {
            duration = 250
            interpolator = DecelerateInterpolator(2f)
            addUpdateListener {
                params.x = it.animatedValue as Int
                if (shown) wm.updateViewLayout(bubble, params)
            }
            start()
        }
    }

    private fun overTarget(rawX: Float, rawY: Float): Boolean {
        if (target.visibility != View.VISIBLE) return false
        val loc = IntArray(2)
        target.getLocationOnScreen(loc)
        val cx = loc[0] + target.width / 2f
        val cy = loc[1] + target.height / 2f
        return hypot(rawX - cx, rawY - cy) < dp(56f)
    }

    private fun screenWidth(): Int = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
        wm.currentWindowMetrics.bounds.width()
    } else {
        context.resources.displayMetrics.widthPixels
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
        WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
        PixelFormat.TRANSLUCENT,
    ).apply { gravity = Gravity.TOP or Gravity.START }

    private fun dp(v: Float) = v * density

    private fun sp(v: Float) =
        TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_SP, v, context.resources.displayMetrics)

    private fun icon(id: Int, color: Int): Drawable = context.getDrawable(id)!!.mutate().apply { setTint(color) }

    @SuppressLint("ViewConstructor")
    private inner class BubbleView : View(context) {
        private val lime = 0xFFD4FF3A.toInt()
        private val fill = Paint(Paint.ANTI_ALIAS_FLAG)
        private val stroke = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE }
        val titlePaint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply { textSize = sp(13f); color = 0xFFF2F2F2.toInt() }
        val artistPaint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply { textSize = sp(11f); color = 0xFF8A8A8A.toInt() }
        val messagePaint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply { textSize = sp(13f); color = 0xFFBDBDBD.toInt() }
        private val mic = icon(R.drawable.ic_bubble_mic, lime)
        private val music = icon(R.drawable.ic_bubble_music, lime)
        private val play = icon(R.drawable.ic_bubble_play, Color.BLACK)
        private val refresh = icon(R.drawable.ic_bubble_refresh, 0xFFF2F2F2.toInt())
        private val rect = RectF()
        private val slop = ViewConfiguration.get(context).scaledTouchSlop

        private var downX = 0f
        private var downY = 0f
        private var startX = 0
        private var startY = 0
        private var dragging = false

        override fun onDraw(canvas: Canvas) {
            val top = pad
            val left = pad
            val radius = size / 2
            // 内容按最终宽度排好，贴右边时从右往左露出来，贴左边时从左往右
            val origin = if (dockRight) left + bubbleWidth - targetWidth else left
            val cy = top + radius

            if (mode == "listening" && pulseAnim.isRunning) {
                stroke.color = lime
                stroke.strokeWidth = dp(1.5f)
                stroke.alpha = (128 * (1 - pulse)).toInt()
                canvas.drawCircle(origin + radius, cy, radius * (1 + 0.25f * pulse), stroke)
                stroke.alpha = 255
            }

            rect.set(left, top, left + bubbleWidth, top + size)
            fill.color = Color.BLACK
            canvas.drawRoundRect(rect, radius, radius, fill)
            stroke.color = 0xFF3A3A3A.toInt()
            stroke.strokeWidth = max(1f, dp(0.5f))
            canvas.drawRoundRect(rect, radius, radius, stroke)

            canvas.save()
            canvas.clipRect(rect)
            val alpha = (255 * fade).toInt()
            when (mode) {
                "listening" -> drawListening(canvas, origin + radius, cy, alpha)
                "found" -> drawFound(canvas, origin, cy, alpha)
                else -> drawMessage(canvas, origin, cy, alpha)
            }
            canvas.restore()
        }

        private fun drawListening(canvas: Canvas, cx: Float, cy: Float, alpha: Int) {
            val ring = dp(22f)
            stroke.strokeWidth = dp(2.5f)
            stroke.color = 0xFF2A2A2A.toInt()
            stroke.alpha = alpha
            canvas.drawCircle(cx, cy, ring, stroke)
            stroke.color = lime
            stroke.alpha = alpha
            stroke.strokeCap = Paint.Cap.ROUND
            rect.set(cx - ring, cy - ring, cx + ring, cy + ring)
            canvas.drawArc(rect, -90f, 360f * progress, false, stroke)
            stroke.strokeCap = Paint.Cap.BUTT
            stroke.alpha = 255
            drawIcon(canvas, mic, cx, cy, dp(22f), alpha)
        }

        private fun drawFound(canvas: Canvas, origin: Float, cy: Float, alpha: Int) {
            val coverSize = dp(40f)
            val coverX = origin + dp(6f)
            val image = cover
            fill.alpha = alpha
            if (image != null) {
                val shader = BitmapShader(image, Shader.TileMode.CLAMP, Shader.TileMode.CLAMP)
                val scale = coverSize / min(image.width, image.height)
                shader.setLocalMatrix(Matrix().apply {
                    setScale(scale, scale)
                    postTranslate(coverX, cy - coverSize / 2)
                })
                fill.shader = shader
                canvas.drawCircle(coverX + coverSize / 2, cy, coverSize / 2, fill)
                fill.shader = null
            } else {
                fill.color = 0xFF2B3310.toInt()
                fill.alpha = alpha
                canvas.drawCircle(coverX + coverSize / 2, cy, coverSize / 2, fill)
                drawIcon(canvas, music, coverX + coverSize / 2, cy, dp(18f), alpha)
            }

            val button = dp(34f)
            val buttonCx = origin + targetWidth - dp(6f) - button / 2
            val textX = coverX + coverSize + dp(8f)
            val textWidth = buttonCx - button / 2 - dp(8f) - textX
            titlePaint.alpha = alpha
            artistPaint.alpha = alpha
            canvas.drawText(ellipsize(title, titlePaint, textWidth), textX, cy - dp(2f), titlePaint)
            canvas.drawText(ellipsize(artist, artistPaint, textWidth), textX, cy + dp(13f), artistPaint)

            fill.color = lime
            fill.alpha = alpha
            canvas.drawCircle(buttonCx, cy, button / 2, fill)
            drawIcon(canvas, play, buttonCx, cy, dp(16f), alpha)
        }

        private fun drawMessage(canvas: Canvas, origin: Float, cy: Float, alpha: Int) {
            val button = dp(34f)
            val buttonCx = origin + targetWidth - dp(6f) - button / 2
            val textX = origin + dp(14f)
            messagePaint.alpha = alpha
            val text = ellipsize(message, messagePaint, buttonCx - button / 2 - dp(8f) - textX)
            val fm = messagePaint.fontMetrics
            canvas.drawText(text, textX, cy - (fm.ascent + fm.descent) / 2, messagePaint)
            fill.color = 0xFF262626.toInt()
            fill.alpha = alpha
            canvas.drawCircle(buttonCx, cy, button / 2, fill)
            drawIcon(canvas, refresh, buttonCx, cy, dp(16f), alpha)
        }

        private fun ellipsize(text: String, paint: TextPaint, width: Float) =
            TextUtils.ellipsize(text, paint, max(0f, width), TextUtils.TruncateAt.END).toString()

        private fun drawIcon(canvas: Canvas, icon: Drawable, cx: Float, cy: Float, s: Float, alpha: Int) {
            icon.setBounds((cx - s / 2).toInt(), (cy - s / 2).toInt(), (cx + s / 2).toInt(), (cy + s / 2).toInt())
            icon.alpha = alpha
            icon.draw(canvas)
        }

        @SuppressLint("ClickableViewAccessibility")
        override fun onTouchEvent(event: MotionEvent): Boolean {
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    slide?.cancel()
                    downX = event.rawX
                    downY = event.rawY
                    startX = params.x
                    startY = params.y
                    dragging = false
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = event.rawX - downX
                    val dy = event.rawY - downY
                    if (!dragging && hypot(dx, dy) > slop) {
                        dragging = true
                        target.visibility = View.VISIBLE
                    }
                    if (dragging) {
                        params.x = startX + dx.toInt()
                        params.y = startY + dy.toInt()
                        wm.updateViewLayout(this, params)
                        target.setActive(overTarget(event.rawX, event.rawY))
                    }
                }
                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                    if (dragging) {
                        val close = event.actionMasked == MotionEvent.ACTION_UP && overTarget(event.rawX, event.rawY)
                        target.visibility = View.INVISIBLE
                        target.setActive(false)
                        if (close) {
                            hide()
                            onAction("close")
                        } else {
                            snap()
                        }
                    } else if (event.actionMasked == MotionEvent.ACTION_UP) {
                        onAction(actionAt(event.x))
                    }
                }
            }
            return true
        }

        /** 胶囊右边的圆键是播放 / 重新识别，其余地方都是回到 Kanade。 */
        private fun actionAt(x: Float): String {
            if (mode == "listening") return "open"
            val origin = if (dockRight) pad + bubbleWidth - targetWidth else pad
            val buttonLeft = origin + targetWidth - dp(6f + 34f + 6f)
            if (x < buttonLeft) return "open"
            return if (mode == "found") "play" else "retry"
        }
    }

    @SuppressLint("ViewConstructor")
    private inner class TargetView : View(context) {
        private val fill = Paint(Paint.ANTI_ALIAS_FLAG)
        private val close = context.getDrawable(R.drawable.ic_bubble_close)!!.mutate()
        private var active = false

        fun setActive(value: Boolean) {
            if (value == active) return
            active = value
            invalidate()
        }

        override fun onDraw(canvas: Canvas) {
            val cx = width / 2f
            val cy = height / 2f
            val r = dp(if (active) 32f else 28f)
            fill.color = if (active) 0xFFD4FF3A.toInt() else 0xFF1A1A1A.toInt()
            canvas.drawCircle(cx, cy, r, fill)
            close.setTint(if (active) Color.BLACK else 0xFFF2F2F2.toInt())
            val s = dp(24f)
            close.setBounds((cx - s / 2).toInt(), (cy - s / 2).toInt(), (cx + s / 2).toInt(), (cy + s / 2).toInt())
            close.draw(canvas)
        }
    }
}
