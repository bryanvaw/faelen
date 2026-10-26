package com.faelen.app

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PersistableBundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * FlutterFragmentActivity because the fingerprint prompt (local_auth) needs a FragmentActivity.
 * Also hosts the Vault's native helpers: block screenshots, and a sensitive clipboard copy that
 * clears itself (only if the clipboard still holds our copy).
 */
class MainActivity : FlutterFragmentActivity() {
    private val handler = Handler(Looper.getMainLooper())
    private var clearTask: Runnable? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "faelen/secure").setMethodCallHandler { call, result ->
            when (call.method) {
                "setSecure" -> {
                    val on = call.argument<Boolean>("on") ?: false
                    runOnUiThread {
                        if (on) window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        else window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    }
                    result.success(null)
                }
                "copy" -> {
                    val text = call.argument<String>("text") ?: ""
                    val sensitive = call.argument<Boolean>("sensitive") ?: false
                    val clearAfterMs = (call.argument<Number>("clearAfterMs") ?: 0).toLong()
                    copy(text, sensitive, clearAfterMs)
                    result.success(null)
                }
                "clear" -> {
                    clearTask?.let { handler.removeCallbacks(it) }
                    clearIfOurs()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun clipboard() = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager

    private fun copy(text: String, sensitive: Boolean, clearAfterMs: Long) {
        val clip = ClipData.newPlainText(CLIP_LABEL, text)
        if (sensitive && Build.VERSION.SDK_INT >= 33) {
            // Hides the value from the clipboard preview Android shows after a copy.
            clip.description.extras = PersistableBundle().apply {
                putBoolean("android.content.extra.IS_SENSITIVE", true)
            }
        }
        clipboard().setPrimaryClip(clip)
        clearTask?.let { handler.removeCallbacks(it) }
        clearTask = null
        if (clearAfterMs > 0) {
            val task = Runnable { clearIfOurs() }
            clearTask = task
            handler.postDelayed(task, clearAfterMs)
        }
    }

    /** Clears the clipboard only when what is on it is our copy, never something copied since. */
    private fun clearIfOurs() {
        val cm = clipboard()
        val label = cm.primaryClipDescription?.label?.toString()
        if (label != CLIP_LABEL) return
        if (Build.VERSION.SDK_INT >= 28) cm.clearPrimaryClip()
        else cm.setPrimaryClip(ClipData.newPlainText("", ""))
    }

    companion object {
        private const val CLIP_LABEL = "faelen-vault"
    }
}
