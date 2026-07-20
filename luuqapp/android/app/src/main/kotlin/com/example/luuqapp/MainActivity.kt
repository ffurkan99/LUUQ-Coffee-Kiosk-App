package com.example.luuqapp

import android.media.AudioAttributes
import android.media.SoundPool
import io.flutter.FlutterInjector
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.view.KeyEvent
import android.view.View
import android.util.Log

class MainActivity : FlutterActivity() {
    companion object {
        private const val TAG = "LuuqKiosk"
    }

    private val channelName = "luuqapp/spin_sound"
    private var soundPool: SoundPool? = null
    private var tickSoundId: Int = 0
    private var tickStreamId: Int = 0
    private var isTickLoaded: Boolean = false
    private var resultSoundId: Int = 0
    private var isResultLoaded: Boolean = false

    private var isKioskModeEnabled: Boolean = false

    private fun isLockTaskActive(): Boolean {
        val activityManager = getSystemService(android.content.Context.ACTIVITY_SERVICE) as android.app.ActivityManager
        return if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.M) {
            activityManager.lockTaskModeState != android.app.ActivityManager.LOCK_TASK_MODE_NONE
        } else {
            @Suppress("DEPRECATION")
            activityManager.isInLockTaskMode
        }
    }

    private fun restoreKioskModeOrThrow() {
        isKioskModeEnabled = true
        if (!isLockTaskActive()) {
            startLockTask()
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val audioAttributes = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_ASSISTANCE_SONIFICATION)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()
        soundPool = SoundPool.Builder()
            .setMaxStreams(1)
            .setAudioAttributes(audioAttributes)
            .build()
        soundPool?.setOnLoadCompleteListener { _, sampleId, status ->
            if (sampleId == tickSoundId && status == 0) {
                isTickLoaded = true
            }
            if (sampleId == resultSoundId && status == 0) {
                isResultLoaded = true
            }
        }

        val flutterLoader = FlutterInjector.instance().flutterLoader()
        val assetKey = flutterLoader
            .getLookupKeyForAsset("assets/sounds/wheel_tick.wav")
        assets.openFd(assetKey).use { descriptor ->
            tickSoundId = soundPool?.load(descriptor, 1) ?: 0
        }
        val resultSoundIdFd = flutterLoader
            .getLookupKeyForAsset("assets/sounds/result_chime.wav")
        assets.openFd(resultSoundIdFd).use { descriptor ->
            resultSoundId = soundPool?.load(descriptor, 1) ?: 0
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "tick" -> {
                        val vol = (call.argument<Double>("volume") ?: 1.0).toFloat()
                        if (isTickLoaded && tickSoundId != 0) {
                            if (tickStreamId != 0) {
                                soundPool?.stop(tickStreamId)
                            }
                            tickStreamId = soundPool?.play(tickSoundId, vol, vol, 1, 0, 1f) ?: 0
                        }
                        result.success(null)
                    }
                    "result" -> {
                        val vol = (call.argument<Double>("volume") ?: 0.65).toFloat()
                        if (isResultLoaded && resultSoundId != 0) {
                            soundPool?.play(resultSoundId, vol, vol, 1, 0, 1f)
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "luuqapp/apk_install")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "enableKioskMode" -> {
                        try {
                            isKioskModeEnabled = true
                            startLockTask()
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("LOCK_TASK_FAILED", e.message, e.stackTraceToString())
                        }
                    }
                    "disableKioskMode" -> {
                        try {
                            isKioskModeEnabled = false
                            stopLockTask()
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("LOCK_TASK_FAILED", e.message, e.stackTraceToString())
                        }
                    }
                    "isLockTaskActive" -> {
                        result.success(isLockTaskActive())
                    }
                    "stopLockTaskForUpdate" -> {
                        try {
                            // Keep the desired kiosk state enabled. onResume and Dart's
                            // update guard will restore LockTask after the external UI.
                            isKioskModeEnabled = true
                            if (isLockTaskActive()) {
                                stopLockTask()
                            }
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("LOCK_TASK_FAILED", e.message, e.stackTraceToString())
                        }
                    }
                    "restoreKioskModeAfterUpdateCancel" -> {
                        try {
                            restoreKioskModeOrThrow()
                            result.success(true)
                        } catch (e: Exception) {
                            Log.e(TAG, "Failed to restore LockTask after update flow", e)
                            result.error("LOCK_TASK_FAILED", e.message, e.stackTraceToString())
                        }
                    }
                    "readApkPackageInfo" -> {
                        val apkPath = call.argument<String>("path")
                        if (apkPath == null) {
                            result.error("INVALID_PATH", "Path is null", null)
                            return@setMethodCallHandler
                        }
                        try {
                            val file = java.io.File(apkPath)
                            if (!file.exists()) {
                                result.error("FILE_NOT_FOUND", "File does not exist at $apkPath", null)
                                return@setMethodCallHandler
                            }
                            val context = applicationContext
                            val packageManager = context.packageManager
                            val info = packageManager.getPackageArchiveInfo(apkPath, 0)
                            if (info == null) {
                                result.error("READ_FAILED", "Failed to get archive info for $apkPath", null)
                                return@setMethodCallHandler
                            }
                            
                            val name = info.packageName
                            val versionName = info.versionName ?: "0.0.0"
                            val versionCode = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.P) {
                                info.longVersionCode
                            } else {
                                @Suppress("DEPRECATION")
                                info.versionCode.toLong()
                            }
                            
                            val map = mapOf(
                                "packageName" to name,
                                "versionName" to versionName,
                                "versionCode" to versionCode
                            )
                            result.success(map)
                        } catch (e: Exception) {
                            result.error("READ_FAILED", e.message, e.stackTraceToString())
                        }
                    }
                    "checkInstallPermission" -> {
                        val context = applicationContext
                        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                            result.success(context.packageManager.canRequestPackageInstalls())
                        } else {
                            result.success(true)
                        }
                    }
                    "openInstallSettings" -> {
                        try {
                            val context = applicationContext
                            val settingsIntent = android.content.Intent(android.provider.Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES).apply {
                                data = android.net.Uri.parse("package:${context.packageName}")
                                addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            context.startActivity(settingsIntent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("SETTINGS_FAILED", e.message, null)
                        }
                    }
                    "installApk" -> {
                        val path = call.argument<String>("path")
                        if (path == null) {
                            result.error("INVALID_PATH", "Path is null", null)
                            return@setMethodCallHandler
                        }
                        try {
                            val file = java.io.File(path)
                            if (!file.exists()) {
                                result.error("FILE_NOT_FOUND", "File does not exist at $path", null)
                                return@setMethodCallHandler
                            }
                            
                            val context = applicationContext
                            val apkUri = androidx.core.content.FileProvider.getUriForFile(
                                context,
                                "${context.packageName}.fileprovider",
                                file
                            )
                            
                            val intent = android.content.Intent(android.content.Intent.ACTION_VIEW).apply {
                                setDataAndType(apkUri, "application/vnd.android.package-archive")
                                addFlags(android.content.Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            
                            context.startActivity(intent)
                            result.success("intent_started")
                        } catch (e: Exception) {
                            result.error("INSTALL_FAILED", e.message, e.stackTraceToString())
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onDestroy() {
        soundPool?.release()
        soundPool = null
        super.onDestroy()
    }

    override fun onResume() {
        super.onResume()
        if (isKioskModeEnabled) {
            try {
                restoreKioskModeOrThrow()
            } catch (e: Exception) {
                // Never hide a failed restore: Dart verifies LockTask on resume and
                // moves the update dialog into a blocking maintenance state.
                Log.e(TAG, "Failed to restore LockTask from onResume", e)
            }
        }
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) {
            window.decorView.systemUiVisibility = (
                View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                or View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
                or View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
                or View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                or View.SYSTEM_UI_FLAG_FULLSCREEN
                or View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
            )
        }
    }

    override fun onBackPressed() {
        // Do absolutely nothing to ignore all system-level swipe back gestures
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent?): Boolean {
        if (keyCode == KeyEvent.KEYCODE_BACK) {
            return true // Intercept physical back key and suppress default behavior
        }
        return super.onKeyDown(keyCode, event)
    }
}
