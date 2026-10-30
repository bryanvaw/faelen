package com.faelen.app

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PersistableBundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

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
        // Settings > Open links with: list the installed browsers, open a link in a chosen one, or
        // show Android's own app picker ("Ask every time").
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "faelen/links").setMethodCallHandler { call, result ->
            when (call.method) {
                "browsers" -> result.success(installedBrowsers())
                "chooser", "open" -> {
                    val url = call.argument<String>("url")
                    if (url == null) {
                        result.success(false)
                        return@setMethodCallHandler
                    }
                    try {
                        val view = Intent(Intent.ACTION_VIEW, Uri.parse(url)).addCategory(Intent.CATEGORY_BROWSABLE)
                        val pkg = call.argument<String>("package")
                        if (call.method == "open" && pkg != null) {
                            view.setPackage(pkg)
                            startActivity(view)
                        } else {
                            startActivity(Intent.createChooser(view, "Open with"))
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        // Browser uninstalled, or nothing can open the link: Dart falls back to the default.
                        result.success(false)
                    }
                }
                else -> result.notImplemented()
            }
        }
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

    /** The app's launcher icon as PNG bytes, so Settings can show the real Chrome, Brave, ... icon. */
    private fun iconPng(pkg: String): ByteArray? = try {
        val size = 96
        val drawable = packageManager.getApplicationIcon(pkg)
        val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        drawable.setBounds(0, 0, size, size)
        drawable.draw(Canvas(bitmap))
        ByteArrayOutputStream().also { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }.toByteArray()
    } catch (e: Exception) {
        null // the sheet falls back to a plain icon
    }

    /** Apps that can open a web link, as [{package, label, icon}], without duplicates and without Faelen. */
    private fun installedBrowsers(): List<Map<String, Any?>> {
        val probe = Intent(Intent.ACTION_VIEW, Uri.parse("https://example.com")).addCategory(Intent.CATEGORY_BROWSABLE)
        val flags = if (Build.VERSION.SDK_INT >= 23) PackageManager.MATCH_ALL else 0
        return packageManager.queryIntentActivities(probe, flags)
            .map { it.activityInfo.packageName to it.loadLabel(packageManager).toString() }
            .filter { it.first != packageName }
            .distinctBy { it.first }
            .sortedBy { it.second.lowercase() }
            .map { mapOf("package" to it.first, "label" to it.second, "icon" to iconPng(it.first)) }
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
