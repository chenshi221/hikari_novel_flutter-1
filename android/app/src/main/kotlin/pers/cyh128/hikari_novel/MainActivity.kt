package pers.cyh128.hikari_novel

import android.content.Intent
import android.content.pm.PackageManager
import android.view.KeyEvent
import android.view.WindowManager
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// 生物识别锁（local_auth）要求 Activity 是 FragmentActivity
class MainActivity : FlutterFragmentActivity() {
    private val intentChannelName = "hikari/system_intents"
    private val readerVolumeChannelName = "hikari/reader_volume_keys"
    private var readerVolumeChannel: MethodChannel? = null
    private var readerVolumeKeyHandlingEnabled = false

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        readerVolumeChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, readerVolumeChannelName)
        readerVolumeChannel?.setMethodCallHandler { call, result ->
            if (call.method == "setEnabled") {
                readerVolumeKeyHandlingEnabled = call.argument<Boolean>("enabled") ?: false
                result.success(null)
            } else {
                result.notImplemented()
            }
        }

        // 阅读器自定义亮度：value 在 0~1 之间设窗口亮度，负数交还给系统
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "hikari/screen").setMethodCallHandler { call, result ->
            if (call.method == "setBrightness") {
                val v = (call.argument<Double>("value") ?: -1.0).toFloat()
                val lp = window.attributes
                lp.screenBrightness = if (v < 0f) WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_NONE else v.coerceIn(0.01f, 1f)
                window.attributes = lp
                result.success(null)
            } else {
                result.notImplemented()
            }
        }

        // 防截屏、隐藏最近任务里的预览
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "hikari/secure").setMethodCallHandler { call, result ->
            if (call.method == "setSecure") {
                if (call.argument<Boolean>("secure") == true) {
                    window.setFlags(WindowManager.LayoutParams.FLAG_SECURE, WindowManager.LayoutParams.FLAG_SECURE)
                } else {
                    window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                }
                result.success(null)
            } else {
                result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, intentChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "openTtsSettings" -> {
                        try {
                            val candidates = arrayListOf(
                                Intent("android.speech.tts.engine.TTS_SETTINGS"),
                                Intent("com.android.settings.TTS_SETTINGS"),
                                Intent(android.provider.Settings.ACTION_SETTINGS)
                            )
                            var launched = false
                            var lastErr: Exception? = null
                            for (it in candidates) {
                                try {
                                    it.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                    startActivity(it)
                                    launched = true
                                    break
                                } catch (e: Exception) {
                                    lastErr = e
                                }
                            }
                            if (launched) {
                                result.success(true)
                            } else {
                                result.error(
                                    "INTENT_FAILED",
                                    lastErr?.message ?: "no activity found",
                                    null
                                )
                            }
                        } catch (e: Exception) {
                            result.error("INTENT_FAILED", e.message, null)
                        }
                    }

                    "openApp" -> {
                        val pkg = call.argument<String>("package")
                        if (pkg.isNullOrBlank()) {
                            result.error("ARG_ERROR", "package is null/blank", null)
                            return@setMethodCallHandler
                        }
                        try {
                            val pm: PackageManager = applicationContext.packageManager
                            val launchIntent = pm.getLaunchIntentForPackage(pkg)
                            if (launchIntent != null) {
                                launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                startActivity(launchIntent)
                                result.success(true)
                            } else {
                                result.error("NOT_FOUND", "app not found: $pkg", null)
                            }
                        } catch (e: Exception) {
                            result.error("INTENT_FAILED", e.message, null)
                        }
                    }

                    else -> result.notImplemented()
                }
            }
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent?): Boolean {
        if (readerVolumeKeyHandlingEnabled &&
            (keyCode == KeyEvent.KEYCODE_VOLUME_UP || keyCode == KeyEvent.KEYCODE_VOLUME_DOWN) &&
            (event?.repeatCount ?: 0) > 0
        ) {
            // Ignore long-press repeats so one press turns exactly one page.
            return true
        }
        if (event?.repeatCount ?: 0 > 0) {
            return super.onKeyDown(keyCode, event)
        }
        when (keyCode) {
            KeyEvent.KEYCODE_VOLUME_UP -> {
                if (readerVolumeKeyHandlingEnabled) {
                    readerVolumeChannel?.invokeMethod("volumeUp", null)
                    return true
                }
            }
            KeyEvent.KEYCODE_VOLUME_DOWN -> {
                if (readerVolumeKeyHandlingEnabled) {
                    readerVolumeChannel?.invokeMethod("volumeDown", null)
                    return true
                }
            }
        }
        return super.onKeyDown(keyCode, event)
    }
}
